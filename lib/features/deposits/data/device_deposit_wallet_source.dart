import 'package:flutter/foundation.dart';

import '../domain/deposit_wallet_source.dart';

/// A wallet whose key lives on this phone (fleet/identity's device wallet).
///
/// Built from two closures so this feature never imports the key store: one
/// reads the address the device signer holds RIGHT NOW, the other signs with
/// it. Captured once, like the MWA source: if the account, the key or the
/// wallet changes afterwards, [isCurrent] turns false and nothing is signed.
///
/// Wired in `depositWalletSourceOf` from `EmbeddedWalletController.signer`.
class DeviceDepositWalletSource implements DepositWalletSource {
  DeviceDepositWalletSource({
    required String this.address,
    required String? Function() currentAddress,
    required Future<Uint8List> Function(Uint8List message) sign,
  }) : _currentAddress = currentAddress,
       _sign = sign;

  final String? Function() _currentAddress;
  final Future<Uint8List> Function(Uint8List message) _sign;

  @override
  final String? address;

  @override
  DepositWalletKind get kind => DepositWalletKind.device;

  @override
  bool get isCurrent {
    try {
      return address != null && _currentAddress() == address;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    if (!isCurrent) throw const DepositWalletDeclined();
    final Uint8List signature;
    try {
      signature = await _sign(Uint8List.fromList(message));
    } catch (_) {
      // Key-store errors can describe the key; a fixed outcome only.
      throw const DepositWalletDeclined();
    }
    // The key changed mid-sign, or the signer returned something that is not
    // a single ed25519 signature: refuse rather than forward it.
    if (!isCurrent || signature.length != 64) {
      throw const DepositWalletDeclined();
    }
    return Uint8List.fromList(signature);
  }
}
