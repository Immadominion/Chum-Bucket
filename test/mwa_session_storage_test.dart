import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out_controller.dart';
import 'package:chumbucket/features/authentication/session/mwa_session_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mwa_storage_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageFailure = throwsA(
    isA<WalletStorageException>().having(
      (e) => e.toString(),
      'sanitized',
      isNot(contains('synthetic-private')),
    ),
  );

  test(
    'migration verifies secure bytes before removing old token, preserves account metadata',
    () async {
      final r = WalletStorageRig();
      r.prefs.beforeRemoval = () {
        expect(r.secure.value != null, isTrue);
        expect(r.prefs.status, MwaSessionStorage.active);
        expect(r.secure.events.last, 'read');
      };
      final result = await r.storage.restore();
      expect(result!.toJson(), walletFixture().toJson());
      expect(r.prefs.legacy, isNull);
      expect(r.prefs.loggedIn, isFalse);
      expect(r.secure.writes, 1);
      expect((await r.restart().restore())!.toJson(), walletFixture().toJson());
      expect(r.secure.writes, 1);
    },
  );
  test(
    'intact old login survives an interrupted migration before commit marker',
    () async {
      final r = WalletStorageRig();
      r.secure.value = r.prefs.legacy;
      expect(
        (await r.restart().restore())!.walletAddress,
        walletFixture().walletAddress,
      );
      expect(r.prefs.legacy, isNull);
      expect(r.secure.writes, 0);
    },
  );
  test(
    'old and secure records for different sessions cannot be silently reconciled',
    () async {
      final r = WalletStorageRig();
      r.secure.value = jsonEncode(
        walletFixture(token: 'synthetic-other').toJson(),
      );
      await expectLater(r.storage.restore(), storageFailure);
      expect(r.prefs.legacy != null, isTrue);
      expect(r.prefs.removals, 0);
    },
  );
  test(
    'orphan secure record without this-install marker is not a login',
    () async {
      final r = WalletStorageRig(legacyLogin: false);
      r.secure.value = jsonEncode(walletFixture().toJson());
      await expectLater(r.storage.restore(), storageFailure);
    },
  );
  for (final failure in ['read', 'write', 'verify', 'marker', 'remove']) {
    test(
      'migration $failure failure retains recoverable old state and never authenticates',
      () async {
        final r = WalletStorageRig();
        switch (failure) {
          case 'read':
            r.secure.failRead = true;
          case 'write':
            r.secure.failWrite = true;
          case 'verify':
            r.secure.corruptWrite = true;
          case 'marker':
            r.prefs.failState = true;
          case 'remove':
            r.prefs.failRemoval = true;
        }
        await expectLater(r.storage.restore(), storageFailure);
        expect(r.prefs.legacy != null, isTrue);
        expect(r.prefs.loggedIn, isTrue);
      },
    );
  }
  for (final missing in [true, false]) {
    test(
      'migrated state refuses plaintext downgrade when secure value is missing/corrupt ($missing)',
      () async {
        final r = WalletStorageRig();
        r.prefs.status = MwaSessionStorage.active;
        r.secure.value = missing ? null : 'broken-synthetic';
        await expectLater(r.storage.restore(), storageFailure);
        expect(r.secure.writes, 0);
        expect(r.prefs.legacy != null, isTrue);
      },
    );
  }
  test('fresh authorization and renewal write only secure storage', () async {
    final r = WalletStorageRig(legacyLogin: false);
    await r.storage.save(walletFixture());
    await r.storage.save(walletFixture(token: 'synthetic-renewed'));
    expect(r.prefs.legacy, isNull);
    expect(r.prefs.loggedIn, isFalse);
    expect(
      (await r.restart().restore())!.authToken == 'synthetic-renewed',
      isTrue,
    );
  });
  test(
    'legacy marker alone is not login and missing token stays unavailable',
    () async {
      final r = WalletStorageRig();
      r.prefs.legacy = null;
      await expectLater(r.storage.restore(), storageFailure);
    },
  );
  test('signed-out legacy copy is removed, never migrated', () async {
    final r = WalletStorageRig();
    r.prefs.loggedIn = false;
    expect(await r.storage.restore(), isNull);
    expect(r.secure.writes, 0);
    expect(r.prefs.legacy, isNull);
  });
  for (final mutation in [
    'address',
    'key',
    'empty token',
    'uri',
    'malformed',
  ]) {
    test(
      'invalid $mutation is sanitized and never copied to secure storage',
      () async {
        final r = WalletStorageRig();
        final json = walletFixture().toJson();
        switch (mutation) {
          case 'address':
            json['walletAddress'] = 'different-address';
          case 'key':
            json['publicKeyBytes'] = 'bad-base64!';
          case 'empty token':
            json['authToken'] = '';
          case 'uri':
            json['walletUriBase'] = 'http://unsafe.invalid';
          case 'malformed':
            break;
        }
        r.prefs.legacy =
            mutation == 'malformed'
                ? 'synthetic-private-not-json'
                : jsonEncode(json);
        await expectLater(r.storage.restore(), storageFailure);
        expect(r.secure.writes, 0);
        expect(r.prefs.removals, 0);
      },
    );
  }
  test(
    'model debug output redacts credential and invalid JSON never echoes values',
    () {
      expect(
        walletFixture().toString(),
        isNot(contains('synthetic-reauthorization')),
      );
      expect(
        () => MwaAuthResult.fromJson({'authToken': 'synthetic-private-value'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe',
            isNot(contains('synthetic-private')),
          ),
        ),
      );
    },
  );
  test(
    'logout tombstone prevents residual secure credential from restoring after restart',
    () async {
      final r = WalletStorageRig();
      await r.storage.restore();
      r.secure.failDelete = true;
      await expectLater(r.storage.clear(), storageFailure);
      expect(r.prefs.status, MwaSessionStorage.signedOut);
      await expectLater(r.restart().restore(), storageFailure);
      r.secure.failDelete = false;
      expect(await r.restart().restore(), isNull);
      expect(r.secure.value, isNull);
    },
  );
  test(
    'silent secure deletion failure is detected, not reported as successful logout',
    () async {
      final r = WalletStorageRig();
      await r.storage.restore();
      r.secure.ignoreDelete = true;
      await expectLater(r.storage.clear(), storageFailure);
      expect(r.prefs.status, MwaSessionStorage.signedOut);
    },
  );
  test(
    'all deletion targets attempted even when tombstone/secure removal fail',
    () async {
      final r = WalletStorageRig();
      r.prefs.failState = true;
      r.secure.failDelete = true;
      await expectLater(r.storage.clear(), storageFailure);
      expect(r.secure.deletes, 1);
      expect(r.prefs.removals, 1);
    },
  );
  for (final migration in [true, false]) {
    test(
      'logout wins over held ${migration ? 'migration' : 'renewal'} write',
      () async {
        final r = WalletStorageRig();
        final held = r.secure.holdWrite = Completer<void>();
        final operation =
            migration ? r.storage.restore() : r.storage.save(walletFixture());
        final rejected = expectLater(operation, storageFailure);
        for (var i = 0; i < 20 && r.secure.writes == 0; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(r.secure.writes, 1);
        final clearing = r.storage.clear();
        held.complete();
        await rejected;
        await clearing;
        expect(r.secure.value, isNull);
        expect(r.prefs.legacy, isNull);
        expect(await r.restart().restore(), isNull);
      },
    );
  }
  test('disposed provider callback cannot complete held restore', () async {
    final r = WalletStorageRig();
    var current = true;
    r.secure.holdRead = Completer<void>();
    final rejected = expectLater(
      r.storage.restore(isCurrent: () => current),
      storageFailure,
    );
    await Future<void>.delayed(Duration.zero);
    current = false;
    r.secure.holdRead!.complete();
    await rejected;
    expect(r.secure.writes, 0);
    expect(r.prefs.legacy != null, isTrue);
  });
  test('new explicit login after logout can save again', () async {
    final r = WalletStorageRig();
    await r.storage.restore();
    await r.storage.clear();
    await r.storage.save(walletFixture(token: 'synthetic-new-login'));
    expect(
      (await r.restart().restore())!.authToken == 'synthetic-new-login',
      isTrue,
    );
  });

  test(
    'provider restores same account and failed secure deletion keeps logout controller locked',
    () async {
      final r = WalletStorageRig();
      final client = SupabaseClient(
        'https://storage-test.invalid',
        'public-synthetic',
      );
      final provider = MwaAuthProvider(
        sessionStorage: r.storage,
        supabaseClient: client,
      );
      final exit = AppSignOutController();
      addTearDown(() async {
        provider.dispose();
        exit.dispose();
        await client.dispose();
      });
      await provider.initialize();
      expect(provider.isAuthenticated, isTrue);
      expect(provider.snsDomain, 'same-person.skr');
      final revision = provider.authRevision;
      r.secure.failDelete = true;
      await exit.signOut([provider.forgetSession]);
      expect(provider.authRevision, greaterThan(revision));
      expect(provider.authToken, isNull);
      expect(provider.isAuthenticated, isFalse);
      expect(exit.state, AppSignOutState.blocked);
      r.secure.failDelete = false;
      await exit.retry();
      expect(exit.state, AppSignOutState.active);
      expect(await provider.isLoggedIn(), isFalse);
    },
  );
  test(
    'provider does not report a plaintext-only login if secure store is unavailable',
    () async {
      final r = WalletStorageRig();
      r.secure.failRead = true;
      final client = SupabaseClient(
        'https://storage-test.invalid',
        'public-synthetic',
      );
      final provider = MwaAuthProvider(
        sessionStorage: r.storage,
        supabaseClient: client,
      );
      addTearDown(() async {
        provider.dispose();
        await client.dispose();
      });
      expect(await provider.isLoggedIn(), isFalse);
      await provider.initialize();
      expect(provider.isAuthenticated, isFalse);
      expect(provider.authToken, isNull);
      expect(provider.errorMessage, contains('unlock'));
      r.secure.failRead = false;
      await provider.initialize();
      expect(provider.isAuthenticated, isTrue);
      expect(provider.errorMessage, isNull);
    },
  );

  test(
    'device preferences remove only wallet keys and retain onboarding/history preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        mwaLegacyCredentialKey: 'synthetic-only',
        mwaLegacyLoginKey: true,
        'onboarding_complete': true,
        'arena_my_pots_synthetic': 'keep',
      });
      const prefs = DeviceWalletMigrationPreferences();
      await prefs.setState(MwaSessionStorage.active);
      await prefs.removeLegacy();
      final actual = await SharedPreferences.getInstance();
      expect(actual.getString(mwaStorageStateKey), MwaSessionStorage.active);
      expect(actual.getBool('onboarding_complete'), isTrue);
      expect(actual.getString('arena_my_pots_synthetic'), 'keep');
      expect(actual.containsKey(mwaLegacyCredentialKey), isFalse);
    },
  );
  test(
    'platform bridge uses exact key/options, never bulk delete, and redacts native failure',
    () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'read') {
              throw PlatformException(
                code: 'failed',
                message: 'synthetic-private',
              );
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const secure = DeviceWalletCredentialStore();
      await secure.write('synthetic-only');
      await secure.delete();
      final storage = MwaSessionStorage(
        secure: secure,
        preferences: MemoryWalletPreferences(),
      );
      await expectLater(storage.restore(), storageFailure);
      expect(calls.map((c) => c.method), ['write', 'delete', 'read']);
      for (final call in calls) {
        final args = call.arguments as Map;
        expect(args['key'], mwaSecureCredentialKey);
        expect(args['options'], isA<Map>());
      }
      // v9 selects via dart:io Platform, so this host test cannot impersonate
      // Android. Device dispatch is exercised separately on the Seeker.
      final android = mwaDeviceSecureStorage.aOptions.toMap();
      expect(android['encryptedSharedPreferences'], 'true');
      expect(android['resetOnError'], 'false');
      expect(android['sharedPreferencesName'], mwaSecurePreferencesName);
      expect(
        mwaDeviceSecureStorage.iOptions.toMap()['synchronizable'],
        'false',
      );
      expect(
        mwaDeviceSecureStorage.iOptions.toMap()['accessibility'],
        'unlocked_this_device',
      );
    },
  );
  test(
    'Android cloud and device-transfer backups exclude credentials and key wrapper',
    () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      for (final file in ['backup_rules.xml', 'data_extraction_rules.xml']) {
        final rules =
            File('android/app/src/main/res/xml/$file').readAsStringSync();
        final copies = file == 'backup_rules.xml' ? 1 : 2;
        expect(
          'path="chumbucket_wallet_secure.xml"'.allMatches(rules).length,
          copies,
        );
        expect(
          'path="FlutterSharedPreferences.xml"'.allMatches(rules).length,
          copies,
        );
        expect(
          'path="FlutterSecureKeyStorage.xml"'.allMatches(rules).length,
          copies,
        );
      }
    },
  );
}
