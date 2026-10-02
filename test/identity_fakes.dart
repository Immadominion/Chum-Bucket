/// Fakes for the identity package tests (front door, usernames, continuity,
/// the on-phone wallet). No socket, no platform channel, no Supabase.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/authentication/continuity/block_store.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';

/// Block Store in memory: scriptable availability, encryption and failures.
class MemoryBlockStore implements BlockStorePort {
  MemoryBlockStore({this.available = true, this.endToEndEncrypted = true});

  bool available;
  bool endToEndEncrypted;
  bool failWrites = false;
  bool failDeletes = false;

  /// Block Store is there but a read fails (Play services not answering).
  bool failReads = false;
  final Map<String, Uint8List> entries = {};

  /// Whether each key's last write asked for cloud backup.
  final Map<String, bool> cloudBackup = {};
  int writes = 0;
  int deletes = 0;

  @override
  Future<BlockStoreAvailability> availability() async => BlockStoreAvailability(
    available: available,
    endToEndEncrypted: available && endToEndEncrypted,
  );

  @override
  Future<Uint8List?> read(String key) async {
    if (!available) throw const BlockStoreUnavailable();
    if (failReads) throw const BlockStoreFailure();
    return entries[key];
  }

  @override
  Future<void> write(
    String key,
    Uint8List bytes, {
    required bool backupToCloud,
  }) async {
    if (!available) throw const BlockStoreUnavailable();
    if (failWrites) throw const BlockStoreFailure();
    writes++;
    entries[key] = Uint8List.fromList(bytes);
    cloudBackup[key] = backupToCloud;
  }

  @override
  Future<void> delete(String key) async {
    if (!available) throw const BlockStoreUnavailable();
    if (failDeletes) throw const BlockStoreFailure();
    deletes++;
    entries.remove(key);
    cloudBackup.remove(key);
  }
}

/// The phone's secure storage, in memory.
class MemorySecretStore implements EmbeddedWalletSecretStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  /// Models storage that accepts a write but reads back something else.
  bool corruptReads = false;

  /// Models a read the Keystore refuses (a locked phone).
  bool failReads = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('keystore locked');
    return corruptReads && values.containsKey(key) ? 'corrupt' : values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('keystore locked');
    values[key] = value;
  }
}

/// The standard BIP-39 test phrase (all "abandon" + "about"). Public test
/// data — never a real wallet.
const kTestPhrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

/// A second valid public test phrase.
const kOtherTestPhrase =
    'legal winner thank year wave sausage worth useful legal winner thank '
    'yellow';
