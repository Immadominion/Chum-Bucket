/// Where an on-phone wallet's recovery phrase lives: the Android Keystore-
/// backed secure storage, one entry per Chumbucket account, plus (when it would
/// be end-to-end encrypted) a Block Store copy so a reinstall gets it back.
///
/// Per account, never per device: if someone else signs in on this phone they
/// do not see, and cannot sign with, another account's wallet. Signing out does
/// not delete it — deleting the only copy of a key can destroy the funds it
/// holds — it simply waits for its account to sign in again.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';

import 'embedded_wallet_key.dart';

/// Same cipher choices as the MWA session store, in its own namespace.
const _embeddedWalletStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: false,
    sharedPreferencesName: 'chumbucket_embedded_wallet',
    preferencesKeyPrefix: 'chum_embedded_',
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  ),
  iOptions: IOSOptions(
    accountName: 'chumbucket_embedded_wallet',
    accessibility: KeychainAccessibility.unlocked_this_device,
    synchronizable: false,
  ),
);

abstract interface class EmbeddedWalletSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DeviceEmbeddedWalletSecretStore implements EmbeddedWalletSecretStore {
  const DeviceEmbeddedWalletSecretStore();
  @override
  Future<String?> read(String key) => _embeddedWalletStorage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _embeddedWalletStorage.write(key: key, value: value);
}

/// Secure storage refused (locked device, Keystore trouble). Carries nothing.
class EmbeddedWalletStorageException implements Exception {
  const EmbeddedWalletStorageException();
  @override
  String toString() => 'EmbeddedWalletStorageException';
}

/// One account's on-phone wallet as stored. [toString] is redacted.
class EmbeddedWalletRecord {
  const EmbeddedWalletRecord({
    required this.address,
    required this.recoveryPhrase,
    required this.linked,
    required this.createdAt,
    this.restoredFromBackup = false,
  });

  final String address;
  final String recoveryPhrase;

  /// The server has confirmed this wallet belongs to the account.
  final bool linked;
  final DateTime createdAt;

  /// Came back from Block Store on this launch rather than local storage.
  final bool restoredFromBackup;

  EmbeddedWalletRecord copyWith({bool? linked, bool? restoredFromBackup}) =>
      EmbeddedWalletRecord(
        address: address,
        recoveryPhrase: recoveryPhrase,
        linked: linked ?? this.linked,
        createdAt: createdAt,
        restoredFromBackup: restoredFromBackup ?? this.restoredFromBackup,
      );

  String encode() => jsonEncode({
    'v': 1,
    'address': address,
    'phrase': recoveryPhrase,
    'linked': linked,
    'createdAt': createdAt.toUtc().toIso8601String(),
  });

  static EmbeddedWalletRecord? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final map = jsonDecode(value);
      if (map is! Map || map['v'] != 1) return null;
      final address = map['address'];
      final phrase = map['phrase'];
      final created = DateTime.tryParse('${map['createdAt']}');
      if (address is! String || phrase is! String || created == null) {
        return null;
      }
      return EmbeddedWalletRecord(
        address: address,
        recoveryPhrase: phrase,
        linked: map['linked'] == true,
        createdAt: created,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'EmbeddedWalletRecord($address, linked: $linked, <phrase redacted>)';
}

class EmbeddedWalletVault {
  EmbeddedWalletVault({
    EmbeddedWalletSecretStore store = const DeviceEmbeddedWalletSecretStore(),
    this.continuity,
  }) : _store = store;

  final EmbeddedWalletSecretStore _store;

  /// Block Store backup, when the app has it. Null in tests that do not care.
  final SessionContinuity? continuity;

  /// One fixed entry per canonical account id.
  static String keyFor(String userId) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(userId)) {
      throw ArgumentError('Unexpected account id shape');
    }
    return 'embedded_wallet_v1_$userId';
  }

  /// This account's wallet on this phone — from secure storage, or from the
  /// Block Store backup after a reinstall (then written back locally). Null
  /// when the account has none here.
  Future<EmbeddedWalletRecord?> load(String userId) async {
    final String? stored;
    try {
      stored = await _store.read(keyFor(userId));
    } catch (_) {
      throw const EmbeddedWalletStorageException();
    }
    final local = EmbeddedWalletRecord.decode(stored);
    if (local != null) return local;
    final phrase = await continuity?.restoreWalletSecret(userId);
    if (phrase == null) return null;
    final EmbeddedWalletKey key;
    try {
      key = await EmbeddedWalletKey.fromRecoveryPhrase(phrase);
    } on EmbeddedWalletException {
      return null;
    }
    final restored = EmbeddedWalletRecord(
      address: key.address,
      recoveryPhrase: key.recoveryPhrase,
      // Re-proven with the server on first use (it answers "reaffirmed").
      linked: false,
      createdAt: DateTime.now().toUtc(),
      restoredFromBackup: true,
    );
    await save(userId, restored);
    return restored;
  }

  /// Writes and reads back. A key is never reported saved unless it is.
  Future<void> save(String userId, EmbeddedWalletRecord record) async {
    final key = keyFor(userId);
    final value = record.encode();
    try {
      await _store.write(key, value);
      if (await _store.read(key) != value) {
        throw const EmbeddedWalletStorageException();
      }
    } on EmbeddedWalletStorageException {
      rethrow;
    } catch (_) {
      throw const EmbeddedWalletStorageException();
    }
  }

  /// Backs the phrase up to Block Store when that copy would be end-to-end
  /// encrypted. Reports honestly when it was not.
  Future<WalletBackupOutcome> backUp(String userId, String phrase) async =>
      await continuity?.backupWalletSecret(userId, phrase) ??
      WalletBackupOutcome.unavailable;
}
