import 'dart:async';
import 'dart:convert';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemorySessionStorage extends LocalStorage {
  String? value;
  Completer<void>? holdWrite;
  Completer<void>? holdRead;
  bool failRemoval = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async {
    final held = value;
    await holdRead?.future;
    return held;
  }

  @override
  Future<void> persistSession(String next) async {
    await holdWrite?.future;
    value = next;
  }

  @override
  Future<void> removePersistedSession() async {
    if (failRemoval) throw StateError('synthetic storage failure');
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String googleSession(String subject) => jsonEncode({
    'access_token': 'synthetic-only',
    'user': {'id': subject},
  });
  test(
    'unverified Google candidate never reaches disk, including after interactive launch',
    () async {
      final memory =
          MemorySessionStorage()..value = googleSession('old-subject');
      final storage = AppSessionPersistence(memory);
      await storage.beginAccountLink();
      storage.beginInteractiveSignIn();
      await storage.persistSession(googleSession('candidate'));
      expect(memory.value, isNull);
      // A fresh process sees no Google credential; old wallet keys are separate.
      expect(await AppSessionPersistence(memory).hasAccessToken(), isFalse);
      await storage.completeAccountLink('candidate');
      expect(memory.value, googleSession('candidate'));
      expect(await storage.hasAccessToken(), isTrue);
    },
  );
  test('candidate from another Google subject cannot be persisted', () async {
    final memory = MemorySessionStorage();
    final storage = AppSessionPersistence(memory);
    await storage.beginAccountLink();
    await storage.persistSession(googleSession('other'));
    await expectLater(
      storage.completeAccountLink('expected'),
      throwsStateError,
    );
    expect(memory.value, isNull);
  });
  test(
    'missing or malformed SDK candidate fails closed without raw error text',
    () async {
      final memory = MemorySessionStorage();
      final storage = AppSessionPersistence(memory);
      await storage.beginAccountLink();
      await expectLater(
        storage.completeAccountLink('expected'),
        throwsStateError,
      );
      await storage.persistSession('synthetic-secret-not-json');
      await expectLater(
        storage.completeAccountLink('expected'),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('synthetic-secret')),
          ),
        ),
      );
      expect(memory.value, isNull);
    },
  );
  test('signout serializes after held verified save and removes it', () async {
    final memory = MemorySessionStorage();
    final storage = AppSessionPersistence(memory);
    await storage.beginAccountLink();
    await storage.persistSession(googleSession('expected'));
    memory.holdWrite = Completer<void>();
    final saving = storage.completeAccountLink('expected');
    await Future<void>.delayed(Duration.zero);
    final clearing = storage.clearForSignOut();
    memory.holdWrite!.complete();
    await saving;
    await clearing;
    expect(memory.value, isNull);
    expect(storage.isLocked, isTrue);
    await expectLater(
      storage.completeAccountLink('expected'),
      throwsStateError,
    );
  });
  test(
    'only latest staged refresh is persisted after verified claim',
    () async {
      final memory = MemorySessionStorage();
      final storage = AppSessionPersistence(memory);
      await storage.beginAccountLink();
      await storage.persistSession(googleSession('expected'));
      final refreshed = jsonEncode({
        'access_token': 'synthetic-refreshed',
        'user': {'id': 'expected'},
      });
      await storage.persistSession(refreshed);
      await storage.completeAccountLink('expected');
      expect(memory.value, refreshed);
    },
  );
  test(
    'a rejected callback also clears the process-wide SDK session',
    () async {
      final storage = AppSessionPersistence(MemorySessionStorage());
      var discarded = 0;
      storage.discardLateAuthSession = () async {
        discarded++;
      };
      await storage.clearForSignOut();
      await storage.persistSession('late-synthetic-callback');
      expect(discarded, 1);
      expect(await storage.accessToken(), isNull);
      storage.beginInteractiveSignIn();
      await storage.persistSession('interactive-synthetic-session');
      expect(discarded, 1);
      expect(await storage.hasAccessToken(), isTrue);
    },
  );
  test('a held read cannot return a credential after logout', () async {
    final memory =
        MemorySessionStorage()
          ..value = 'synthetic-session'
          ..holdRead = Completer<void>();
    final storage = AppSessionPersistence(memory);
    final read = storage.accessToken();
    await storage.clearForSignOut();
    memory.holdRead!.complete();
    expect(await read, isNull);
  });

  test(
    'a recreated auth listener ignores old callbacks until interactive sign-in',
    () async {
      final storage = AppSessionPersistence(MemorySessionStorage());
      AppSessionPersistence.current = storage;
      addTearDown(() => AppSessionPersistence.current = null);
      await storage.clearForSignOut();
      final sdkEvents = StreamController<AuthState>();
      final received = <SupabaseAuthEvent>[];
      final subscription = SupabaseFlutterAuthPort.eventsOf(
        sdkEvents.stream,
      ).listen(received.add);
      sdkEvents.add(AuthState(AuthChangeEvent.signedIn, null));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      storage.beginInteractiveSignIn();
      sdkEvents.add(AuthState(AuthChangeEvent.signedIn, null));
      await Future<void>.delayed(Duration.zero);
      expect(received.single.kind, SupabaseAuthEventKind.signedIn);
      await subscription.cancel();
      await sdkEvents.close();
    },
  );

  test(
    'logout waits for an old save then deletes it; late saves stay blocked',
    () async {
      final memory = MemorySessionStorage()..holdWrite = Completer<void>();
      final storage = AppSessionPersistence(memory);
      final saving = storage.persistSession('synthetic-session');
      await Future<void>.delayed(Duration.zero);
      final clearing = storage.clearForSignOut();
      memory.holdWrite!.complete();
      await saving;
      await clearing;
      await storage.persistSession('late-session');
      expect(memory.value == null, isTrue);
      expect(await storage.hasAccessToken(), isFalse);
      storage.beginInteractiveSignIn();
      await storage.persistSession('new-session');
      expect(await storage.hasAccessToken(), isTrue);
    },
  );

  test('failed removal remains locked and can be retried', () async {
    final memory =
        MemorySessionStorage()
          ..value = 'synthetic-session'
          ..failRemoval = true;
    final storage = AppSessionPersistence(memory);
    await expectLater(storage.clearForSignOut(), throwsStateError);
    expect(storage.isLocked, isTrue);
    expect(await storage.accessToken(), isNull);
    memory.failRemoval = false;
    await storage.clearForSignOut();
    expect(memory.value == null, isTrue);
  });

  test(
    'only this project session and MWA keys are removed; onboarding survives',
    () async {
      SharedPreferences.setMockInitialValues({
        'sb-demo-auth-token': 'synthetic-session',
        'sb-other-auth-token': 'unrelated-project',
        'mwa_auth_result': 'synthetic-wallet-credential',
        'mwa_is_logged_in': true,
        'onboarding_complete': true,
      });
      final storage = AppSessionPersistence.forProject(
        'https://demo.supabase.co',
      );
      await storage.initialize();
      final wallet = MwaAuthProvider();
      addTearDown(wallet.dispose);
      await Future.wait([storage.clearForSignOut(), wallet.forgetSession()]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('sb-demo-auth-token'), isFalse);
      expect(prefs.containsKey('mwa_auth_result'), isFalse);
      expect(prefs.containsKey('mwa_is_logged_in'), isFalse);
      expect(prefs.containsKey('sb-other-auth-token'), isTrue);
      expect(prefs.getBool('onboarding_complete'), isTrue);
    },
  );
}
