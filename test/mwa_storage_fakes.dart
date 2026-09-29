import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:chumbucket/features/authentication/session/mwa_auth_result.dart';
import 'package:chumbucket/features/authentication/session/mwa_session_storage.dart';

MwaAuthResult walletFixture({
  String token = 'synthetic-reauthorization-only',
}) => MwaAuthResult(
  walletAddress: '11111111111111111111111111111111',
  authToken: token,
  publicKeyBytes: Uint8List(32),
  accountLabel: 'Existing account',
  walletUriBase: Uri.parse('https://wallet.example.invalid'),
  snsDomain: 'same-person.skr',
);

class MemoryWalletSecrets implements WalletCredentialStore {
  String? value;
  bool failRead = false,
      failWrite = false,
      failDelete = false,
      ignoreDelete = false;
  bool corruptWrite = false;
  int writes = 0, deletes = 0;
  Completer<void>? holdWrite, holdRead;
  final events = <String>[];
  @override
  Future<String?> read() async {
    events.add('read');
    await holdRead?.future;
    if (failRead) throw StateError('synthetic-private-error-detail');
    return value;
  }

  @override
  Future<void> write(String next) async {
    events.add('write');
    writes++;
    await holdWrite?.future;
    if (failWrite) throw StateError('synthetic-private-error-detail');
    value = corruptWrite ? 'invalid-synthetic-record' : next;
  }

  @override
  Future<void> delete() async {
    events.add('delete');
    deletes++;
    if (failDelete) throw StateError('synthetic-private-error-detail');
    if (!ignoreDelete) value = null;
  }
}

class MemoryWalletPreferences implements WalletMigrationPreferences {
  String? status, legacy;
  bool loggedIn = false, failState = false, failRemoval = false;
  int removals = 0;
  void Function()? beforeRemoval;
  @override
  Future<String?> state() async => status;
  @override
  Future<void> setState(String value) async {
    if (failState) throw StateError('synthetic-private-error-detail');
    status = value;
  }

  @override
  Future<String?> legacyCredential() async => legacy;
  @override
  Future<bool> legacyLoggedIn() async => loggedIn;
  @override
  Future<void> removeLegacy() async {
    removals++;
    beforeRemoval?.call();
    if (failRemoval) throw StateError('synthetic-private-error-detail');
    legacy = null;
    loggedIn = false;
  }
}

class WalletStorageRig {
  WalletStorageRig({bool legacyLogin = true}) {
    if (legacyLogin) {
      prefs.legacy = jsonEncode(walletFixture().toJson());
      prefs.loggedIn = true;
    }
    storage = MwaSessionStorage(secure: secure, preferences: prefs);
  }
  final secure = MemoryWalletSecrets();
  final prefs = MemoryWalletPreferences();
  late final MwaSessionStorage storage;
  MwaSessionStorage restart() =>
      MwaSessionStorage(secure: secure, preferences: prefs);
}
