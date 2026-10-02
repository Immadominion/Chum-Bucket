/// Staying signed in across uninstall/reinstall on Android (Block Store):
/// mirror every saved session, restore once on a fresh install, clear on an
/// explicit sign-out, and degrade to "sign in again" when Block Store is not
/// there. Plus the platform channel's shape, against a mocked channel.
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/continuity/block_store.dart';
import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import 'identity_fakes.dart';

const _accessToken = 'eyJhbGciOiJIUzI1NiJ9.access-token-never-backed-up.sig';

String persistedSession({
  String refreshToken = 'refresh-1',
  String sub = 'auth-user-1',
}) => jsonEncode({
  'access_token': _accessToken,
  'refresh_token': refreshToken,
  'expires_in': 3600,
  'token_type': 'bearer',
  'user': {'id': sub, 'email': 'person@example.com'},
});

class _Rig {
  _Rig({MemoryBlockStore? store, this.outcome = SessionAdoption.adopted})
    : store = store ?? MemoryBlockStore();

  final MemoryBlockStore store;
  final MemoryLastSignInStore lastSignIn = MemoryLastSignInStore();
  SessionAdoption outcome;
  String? local;
  final adopted = <String>[];

  late final continuity = SessionContinuity(
    store: store,
    lastSignIn: lastSignIn,
    adopt: (token) async {
      adopted.add(token);
      return outcome;
    },
    localSession: () async => local,
  );

  SessionBackup? get backup =>
      SessionBackup.decode(store.entries[SessionContinuity.sessionKey]);

  Future<void> settle() => Future<void>.delayed(Duration.zero);
}

/// A delegate store that records what reached disk.
class _Disk extends LocalStorage {
  String? value;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<void> persistSession(String persistSessionString) async =>
      value = persistSessionString;
  @override
  Future<void> removePersistedSession() async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mirroring the session', () {
    test(
      'every saved session is mirrored: refresh token, subject, method — never the access token',
      () async {
        final rig = _Rig();
        rig.lastSignIn.value = SignInMethod.google;
        rig.continuity.sessionPersisted(persistedSession());
        await rig.settle();
        final backup = rig.backup!;
        expect(backup.refreshToken, 'refresh-1');
        expect(backup.authUserId, 'auth-user-1');
        expect(backup.method, SignInMethod.google);
        final raw = utf8.decode(
          rig.store.entries[SessionContinuity.sessionKey]!,
        );
        expect(raw, isNot(contains(_accessToken)));
        expect(raw, isNot(contains('person@example.com')));
        expect(rig.store.cloudBackup[SessionContinuity.sessionKey], isTrue);
        expect('$backup', isNot(contains('refresh-1')));
      },
    );

    test(
      'a refreshed token replaces the old one; an unchanged one is not rewritten',
      () async {
        final rig = _Rig();
        rig.continuity.sessionPersisted(persistedSession());
        rig.continuity.sessionPersisted(persistedSession());
        rig.continuity.sessionPersisted(
          persistedSession(refreshToken: 'refresh-2'),
        );
        await rig.settle();
        expect(rig.backup!.refreshToken, 'refresh-2');
        expect(rig.store.writes, 2);
      },
    );

    test(
      'without a screen lock the session stays on the phone (no cloud copy)',
      () async {
        final rig = _Rig(store: MemoryBlockStore(endToEndEncrypted: false));
        rig.continuity.sessionPersisted(persistedSession());
        await rig.settle();
        expect(rig.backup, isNotNull);
        expect(rig.store.cloudBackup[SessionContinuity.sessionKey], isFalse);
      },
    );

    test(
      'AppSessionPersistence reports real writes and removals, never refused ones',
      () async {
        final disk = _Disk();
        final persistence = AppSessionPersistence(disk);
        final seen = <String>[];
        var removed = 0;
        persistence.onPersisted = seen.add;
        persistence.onRemoved = () => removed++;
        await persistence.persistSession(persistedSession());
        expect(seen, [persistedSession()]);
        await persistence.clearForSignOut();
        expect(removed, 1);
        // Locked after sign-out: a late write is refused and not announced.
        await persistence.persistSession(
          persistedSession(refreshToken: 'late'),
        );
        expect(seen, hasLength(1));
        expect(disk.value, isNull);
      },
    );
  });

  group('restoring on a fresh install', () {
    test(
      'no local session + a backup: adopted once, and the last-used method comes back',
      () async {
        final rig = _Rig();
        rig.store.entries[SessionContinuity.sessionKey] =
            const SessionBackup(
              refreshToken: 'refresh-9',
              authUserId: 'auth-user-1',
              method: SignInMethod.x,
            ).encode();
        expect(await rig.continuity.restoreOnLaunch(), isTrue);
        expect(await rig.continuity.restoreOnLaunch(), isTrue);
        expect(rig.adopted, ['refresh-9']);
        expect(rig.lastSignIn.value, SignInMethod.x);
        expect(rig.continuity.settled, isTrue);
      },
    );

    test(
      'a refused token is dead: the backup is deleted and the person signs in',
      () async {
        final rig = _Rig(outcome: SessionAdoption.rejected);
        rig.store.entries[SessionContinuity.sessionKey] =
            const SessionBackup(
              refreshToken: 'used-elsewhere',
              authUserId: 'auth-user-1',
            ).encode();
        expect(await rig.continuity.restoreOnLaunch(), isFalse);
        expect(rig.store.entries, isEmpty);
      },
    );

    test('offline: the backup is kept for the next launch', () async {
      final rig = _Rig(outcome: SessionAdoption.unreachable);
      rig.store.entries[SessionContinuity.sessionKey] =
          const SessionBackup(
            refreshToken: 'refresh-9',
            authUserId: 'auth-user-1',
          ).encode();
      expect(await rig.continuity.restoreOnLaunch(), isFalse);
      expect(rig.backup?.refreshToken, 'refresh-9');
    });

    test(
      'already signed in here: nothing is adopted, and the backup is brought up to date',
      () async {
        final rig = _Rig()..local = persistedSession(refreshToken: 'current');
        expect(await rig.continuity.restoreOnLaunch(), isFalse);
        expect(rig.adopted, isEmpty);
        await rig.settle();
        expect(rig.backup?.refreshToken, 'current');
      },
    );

    test(
      'no Block Store (no Play services, iOS): signs in as before, nothing thrown',
      () async {
        final rig = _Rig(store: MemoryBlockStore(available: false));
        expect(await rig.continuity.restoreOnLaunch(), isFalse);
        rig.continuity.sessionPersisted(persistedSession());
        await rig.settle();
        await rig.continuity.clearSession();
        expect(
          await rig.continuity.backupWalletSecret('u', kTestPhrase),
          WalletBackupOutcome.unavailable,
        );
      },
    );

    test(
      'a removal before launch settles cannot delete the backup it needs',
      () async {
        final rig = _Rig();
        rig.store.entries[SessionContinuity.sessionKey] =
            const SessionBackup(
              refreshToken: 'refresh-9',
              authUserId: 'auth-user-1',
            ).encode();
        rig.continuity.sessionRemoved();
        await rig.settle();
        expect(rig.backup, isNotNull);
        await rig.continuity.restoreOnLaunch();
        rig.continuity.sessionRemoved();
        await rig.settle();
        expect(
          rig.backup,
          isNull,
          reason: 'after launch, a dropped session is dead',
        );
      },
    );
  });

  group('signing out', () {
    test(
      'an explicit sign-out deletes the session backup; wallet keys stay',
      () async {
        final rig = _Rig();
        rig.continuity.sessionPersisted(persistedSession());
        await rig.continuity.backupWalletSecret('user-1', kTestPhrase);
        await rig.continuity.restoreOnLaunch();
        await rig.continuity.clearSession();
        expect(rig.backup, isNull);
        expect(
          await rig.continuity.restoreWalletSecret('user-1'),
          kTestPhrase,
          reason: 'deleting the only copy of a key can destroy its funds',
        );
      },
    );

    test(
      'a Block Store that refuses the delete fails the sign-out task (so it is retried)',
      () async {
        final rig = _Rig();
        rig.continuity.sessionPersisted(persistedSession());
        await rig.settle();
        rig.store.failDeletes = true;
        await expectLater(
          rig.continuity.clearSession(),
          throwsA(isA<BlockStoreFailure>()),
        );
        rig.store.failDeletes = false;
        await rig.continuity.clearSession();
        expect(rig.backup, isNull);
      },
    );
  });

  group('wallet keys', () {
    test('backed up only when end-to-end encrypted, per account', () async {
      final rig = _Rig();
      expect(
        await rig.continuity.backupWalletSecret('user-1', kTestPhrase),
        WalletBackupOutcome.backedUp,
      );
      expect(
        await rig.continuity.backupWalletSecret('user-2', kOtherTestPhrase),
        WalletBackupOutcome.backedUp,
      );
      expect(await rig.continuity.restoreWalletSecret('user-1'), kTestPhrase);
      expect(
        await rig.continuity.restoreWalletSecret('user-2'),
        kOtherTestPhrase,
      );
      expect(await rig.continuity.restoreWalletSecret('user-3'), isNull);
      expect(rig.store.cloudBackup[SessionContinuity.walletsKey], isTrue);

      final noLock = _Rig(store: MemoryBlockStore(endToEndEncrypted: false));
      expect(
        await noLock.continuity.backupWalletSecret('user-1', kTestPhrase),
        WalletBackupOutcome.notEncrypted,
      );
      expect(noLock.store.entries, isEmpty);
    });

    test('a backed-up key is never replaced by a different one', () async {
      final rig = _Rig();
      await rig.continuity.backupWalletSecret('user-1', kTestPhrase);
      expect(
        await rig.continuity.backupWalletSecret('user-1', kOtherTestPhrase),
        WalletBackupOutcome.otherWalletBackedUp,
      );
      expect(await rig.continuity.restoreWalletSecret('user-1'), kTestPhrase);
    });

    test(
      'an unreadable backup is reported as such, never as "no key"',
      () async {
        final rig = _Rig();
        await rig.continuity.backupWalletSecret('user-1', kTestPhrase);
        rig.store.failReads = true;
        await expectLater(
          rig.continuity.restoreWalletSecret('user-1'),
          throwsA(isA<WalletBackupUnreadable>()),
        );
        // No Block Store at all is simply "none".
        rig.store.available = false;
        expect(await rig.continuity.restoreWalletSecret('user-1'), isNull);
      },
    );
  });

  group('the platform channel', () {
    const channel = MethodChannel(MethodChannelBlockStore.channelName);
    final calls = <MethodCall>[];
    Future<Object?> Function(MethodCall call)? reply;

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return reply?.call(call);
          });
    });
    tearDown(() {
      reply = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('speaks the four methods with fixed argument shapes', () async {
      reply =
          (call) async => switch (call.method) {
            'availability' => {'available': true, 'e2ee': true},
            'retrieve' => Uint8List.fromList([1, 2, 3]),
            _ => null,
          };
      const store = MethodChannelBlockStore();
      final availability = await store.availability();
      expect(availability.available, isTrue);
      expect(availability.endToEndEncrypted, isTrue);
      expect(await store.read('chumbucket.session.v1'), [1, 2, 3]);
      await store.write(
        'chumbucket.session.v1',
        Uint8List.fromList([9]),
        backupToCloud: true,
      );
      await store.delete('chumbucket.session.v1');
      expect(calls.map((c) => c.method), [
        'availability',
        'retrieve',
        'store',
        'delete',
      ]);
      expect(calls[2].arguments, {
        'key': 'chumbucket.session.v1',
        'bytes': Uint8List.fromList([9]),
        'backupToCloud': true,
      });
    });

    test(
      '"unavailable" from Android, or no plugin at all, is BlockStoreUnavailable',
      () async {
        reply =
            (call) async =>
                throw PlatformException(code: 'unavailable', message: 'x');
        const store = MethodChannelBlockStore();
        await expectLater(
          store.read('chumbucket.session.v1'),
          throwsA(isA<BlockStoreUnavailable>()),
        );
        expect((await store.availability()).available, isFalse);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await expectLater(
          store.delete('chumbucket.session.v1'),
          throwsA(isA<BlockStoreUnavailable>()),
        );
      },
    );

    test('any other failure carries nothing from the platform', () async {
      reply =
          (call) async =>
              throw PlatformException(code: 'failed', message: 'secret-ish');
      const store = MethodChannelBlockStore();
      Object? caught;
      try {
        await store.read('chumbucket.session.v1');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<BlockStoreFailure>());
      expect('$caught', isNot(contains('secret-ish')));
    });
  });
}
