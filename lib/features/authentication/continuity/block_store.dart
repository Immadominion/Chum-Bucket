/// Google Block Store, from Dart. The Android half is
/// `android/app/src/main/kotlin/dev/cleva/chumbucket/BlockStoreChannel.kt`.
///
/// Block Store keeps up to 16 small entries (4 KB each) per app inside Google
/// Play services. They survive an uninstall when the person has Backup on, and
/// move to a new phone in its restore flow; the cloud copy is end-to-end
/// encrypted when the device has a screen lock. That is what lets someone who
/// deletes the app and reinstalls it come back still signed in.
///
/// iOS has no Block Store. The equivalent there is a Keychain item with
/// `kSecAttrSynchronizable` (iCloud Keychain, end-to-end encrypted) — not
/// built; on iOS every call below reports "unavailable" and the app simply
/// asks the person to sign in again after a reinstall.
library;

import 'package:flutter/services.dart';

class BlockStoreAvailability {
  const BlockStoreAvailability({
    required this.available,
    required this.endToEndEncrypted,
  });

  static const none = BlockStoreAvailability(
    available: false,
    endToEndEncrypted: false,
  );

  /// Google Play services and Block Store answered.
  final bool available;

  /// A cloud backup would be end-to-end encrypted (the device has a screen
  /// lock). Only then is anything asked to leave the phone.
  final bool endToEndEncrypted;

  @override
  String toString() =>
      'BlockStoreAvailability(available: $available, e2ee: $endToEndEncrypted)';
}

/// Block Store is not on this device (no Play services, iOS, a test).
class BlockStoreUnavailable implements Exception {
  const BlockStoreUnavailable();
  @override
  String toString() => 'BlockStoreUnavailable';
}

/// Block Store answered with a failure. Deliberately carries nothing else.
class BlockStoreFailure implements Exception {
  const BlockStoreFailure();
  @override
  String toString() => 'BlockStoreFailure';
}

abstract interface class BlockStorePort {
  Future<BlockStoreAvailability> availability();

  /// The bytes stored under [key], or null when there are none.
  Future<Uint8List?> read(String key);

  /// [backupToCloud] only when [BlockStoreAvailability.endToEndEncrypted].
  Future<void> write(
    String key,
    Uint8List bytes, {
    required bool backupToCloud,
  });

  Future<void> delete(String key);
}

/// The real port. Every platform error becomes one of the two exceptions
/// above; nothing from the platform (which could echo an entry) escapes.
class MethodChannelBlockStore implements BlockStorePort {
  const MethodChannelBlockStore([
    this._channel = const MethodChannel(channelName),
  ]);

  static const channelName = 'dev.cleva.chumbucket/block_store';
  final MethodChannel _channel;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      throw const BlockStoreUnavailable();
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') throw const BlockStoreUnavailable();
      throw const BlockStoreFailure();
    } catch (_) {
      throw const BlockStoreFailure();
    }
  }

  @override
  Future<BlockStoreAvailability> availability() async {
    try {
      final answer = await _invoke<Map<Object?, Object?>>('availability');
      if (answer == null || answer['available'] != true) {
        return BlockStoreAvailability.none;
      }
      return BlockStoreAvailability(
        available: true,
        endToEndEncrypted: answer['e2ee'] == true,
      );
    } on BlockStoreUnavailable {
      return BlockStoreAvailability.none;
    } on BlockStoreFailure {
      return BlockStoreAvailability.none;
    }
  }

  @override
  Future<Uint8List?> read(String key) =>
      _invoke<Uint8List>('retrieve', {'key': key});

  @override
  Future<void> write(
    String key,
    Uint8List bytes, {
    required bool backupToCloud,
  }) => _invoke<void>('store', {
    'key': key,
    'bytes': bytes,
    'backupToCloud': backupToCloud,
  });

  @override
  Future<void> delete(String key) => _invoke<void>('delete', {'key': key});
}
