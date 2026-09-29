import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mwa_auth_result.dart';

const mwaLegacyCredentialKey = 'mwa_auth_result';
const mwaLegacyLoginKey = 'mwa_is_logged_in';
const mwaStorageStateKey = 'mwa_secure_session_state';
const mwaSecureCredentialKey = 'mwa_session_v1';
const mwaSecurePreferencesName = 'chumbucket_wallet_secure';

/// Constructor options are fixed for all operations; never reset/delete all on
/// an encryption error. The namespace has no dependency on a user's identity.
const mwaDeviceSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: false,
    sharedPreferencesName: mwaSecurePreferencesName,
    preferencesKeyPrefix: 'chum_wallet_',
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  ),
  iOptions: IOSOptions(
    accountName: 'chumbucket_wallet',
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  ),
);

abstract interface class WalletCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class DeviceWalletCredentialStore implements WalletCredentialStore {
  const DeviceWalletCredentialStore();
  @override
  Future<String?> read() =>
      mwaDeviceSecureStorage.read(key: mwaSecureCredentialKey);
  @override
  Future<void> write(String value) =>
      mwaDeviceSecureStorage.write(key: mwaSecureCredentialKey, value: value);
  @override
  Future<void> delete() =>
      mwaDeviceSecureStorage.delete(key: mwaSecureCredentialKey);
}

abstract interface class WalletMigrationPreferences {
  Future<String?> state();
  Future<void> setState(String value);
  Future<String?> legacyCredential();
  Future<bool> legacyLoggedIn();
  Future<void> removeLegacy();
}

class DeviceWalletMigrationPreferences implements WalletMigrationPreferences {
  const DeviceWalletMigrationPreferences();
  @override
  Future<String?> state() async =>
      (await SharedPreferences.getInstance()).getString(mwaStorageStateKey);
  @override
  Future<void> setState(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(mwaStorageStateKey, value)) {
      throw const WalletStorageException();
    }
    await prefs.reload();
    if (prefs.getString(mwaStorageStateKey) != value) {
      throw const WalletStorageException();
    }
  }

  @override
  Future<String?> legacyCredential() async =>
      (await SharedPreferences.getInstance()).getString(mwaLegacyCredentialKey);
  @override
  Future<bool> legacyLoggedIn() async =>
      (await SharedPreferences.getInstance()).getBool(mwaLegacyLoginKey) ==
      true;
  @override
  Future<void> removeLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final removedCredential = await prefs.remove(mwaLegacyCredentialKey);
    final removedMarker = await prefs.remove(mwaLegacyLoginKey);
    await prefs.reload();
    if (!removedCredential ||
        !removedMarker ||
        prefs.containsKey(mwaLegacyCredentialKey) ||
        prefs.containsKey(mwaLegacyLoginKey)) {
      throw const WalletStorageException();
    }
  }
}

/// Deliberately carries neither platform exception nor serialized credential.
class WalletStorageException implements Exception {
  const WalletStorageException();
  @override
  String toString() =>
      'Wallet session storage unavailable. Retry after unlocking the device.';
}

/// One process-wide queue serializes migration, renewal and logout across
/// provider instances. Only the named wallet keys are ever removed.
class MwaSessionStorage {
  MwaSessionStorage({
    WalletCredentialStore? secure,
    WalletMigrationPreferences? preferences,
  }) : _secure = secure ?? const DeviceWalletCredentialStore(),
       _preferences = preferences ?? const DeviceWalletMigrationPreferences();
  static final device = MwaSessionStorage();
  final WalletCredentialStore _secure;
  final WalletMigrationPreferences _preferences;
  Future<void> _tail = Future.value();
  int _generation = 0;
  static const active = 'active_v1';
  static const signedOut = 'signed_out_v1';

  Future<T> _queue<T>(Future<T> Function() operation) {
    final pending = _tail.then((_) async {
      try {
        return await operation();
      } catch (_) {
        throw const WalletStorageException();
      }
    });
    _tail = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
  }

  Future<MwaAuthResult?> restore({bool Function()? isCurrent}) {
    final generation = _generation;
    void check() {
      if (generation != _generation || isCurrent?.call() == false) {
        throw const WalletStorageException();
      }
    }

    return _queue(() async {
      check();
      final state = await _preferences.state();
      check();
      if (state == signedOut) {
        // Complete an interrupted logout; a residual token cannot resurrect it.
        await _erase();
        check();
        return null;
      }
      if (state != null && state != active) {
        throw const WalletStorageException();
      }
      final saved = await _secure.read();
      check();
      if (saved != null) {
        final result = _decode(saved);
        if (state == null) {
          // Only an interrupted migration with the same old credential may
          // finish without a commit marker. Never adopt an orphan Keychain
          // record from another installation or overwrite conflicting accounts.
          final loggedIn = await _preferences.legacyLoggedIn();
          check();
          final legacy = await _preferences.legacyCredential();
          check();
          if (!loggedIn ||
              legacy == null ||
              jsonEncode(_decode(legacy).toJson()) !=
                  jsonEncode(result.toJson())) {
            throw const WalletStorageException();
          }
        }
        await _preferences.setState(active);
        check();
        await _preferences.removeLegacy();
        check();
        return result;
      }
      // Never downgrade a previously migrated account to a plaintext copy.
      if (state == active) throw const WalletStorageException();
      final wasLoggedIn = await _preferences.legacyLoggedIn();
      check();
      if (!wasLoggedIn) {
        await _preferences.setState(signedOut);
        check();
        await _preferences.removeLegacy();
        check();
        return null;
      }
      final legacy = await _preferences.legacyCredential();
      check();
      if (legacy == null) throw const WalletStorageException();
      final result = _decode(legacy);
      await _saveVerified(result, check);
      return result;
    });
  }

  Future<void> save(MwaAuthResult result, {bool Function()? isCurrent}) {
    final generation = _generation;
    void check() {
      if (generation != _generation || isCurrent?.call() == false) {
        throw const WalletStorageException();
      }
    }

    // Freeze the bytes before enqueuing; publicKeyBytes may otherwise mutate.
    final frozen = _decode(jsonEncode(result.toJson()));
    return _queue(() async {
      check();
      final state = await _preferences.state();
      check();
      if (state == null) {
        // A brand-new authorization interrupted before its commit cannot later
        // be mistaken for a migrated session. This marker contains no secret.
        await _preferences.setState(signedOut);
        check();
      } else if (state != active && state != signedOut) {
        throw const WalletStorageException();
      }
      await _saveVerified(frozen, check);
    });
  }

  Future<void> _saveVerified(
    MwaAuthResult result,
    void Function() check,
  ) async {
    check();
    final value = jsonEncode(result.toJson());
    await _secure.write(value);
    check();
    if (await _secure.read() != value) throw const WalletStorageException();
    check();
    await _preferences.setState(active);
    check();
    // Only now can plaintext be removed. A failure stays recoverable and is
    // reported; the caller cannot treat an incomplete migration as authenticated.
    await _preferences.removeLegacy();
    check();
  }

  Future<void> clear() {
    _generation++; // Invalidate an in-flight read/save before waiting on the queue.
    return _queue(() async {
      var failed = false;
      try {
        await _preferences.setState(signedOut);
      } catch (_) {
        failed = true;
      }
      try {
        await _erase();
      } catch (_) {
        failed = true;
      }
      if (failed) throw const WalletStorageException();
    });
  }

  Future<void> _erase() async {
    var failed = false;
    // Run both removals even if one fails. Existing sign-out controller stays
    // locked on any failure; tombstone prevents recovery of residual secrets.
    try {
      await _secure.delete();
      if (await _secure.read() != null) failed = true;
    } catch (_) {
      failed = true;
    }
    try {
      await _preferences.removeLegacy();
    } catch (_) {
      failed = true;
    }
    if (failed) throw const WalletStorageException();
  }

  static MwaAuthResult _decode(String value) {
    try {
      if (value.length > 65536) throw const FormatException();
      return MwaAuthResult.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      throw const WalletStorageException();
    }
  }
}
