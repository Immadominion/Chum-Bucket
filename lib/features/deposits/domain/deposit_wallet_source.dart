import 'dart:typed_data';

/// Where a wallet lives on this device.
enum DepositWalletKind {
  /// An external wallet app reached through Mobile Wallet Adapter.
  mwa,

  /// A key held by Chumbucket on this device (fleet/identity's device wallet).
  device,
}

/// The wallet this device trades from, as Add funds sees it.
///
/// Add funds never sends this address as a recipient. The BFF resolves the
/// recipient from the account's server-verified wallets; [address] only tells
/// it WHICH of those this device is using, and the server refuses an address
/// that isn't one of them. A device wallet plugs in by implementing this and
/// providing it above the app (see `depositWalletSourceOf`).
abstract interface class DepositWalletSource {
  DepositWalletKind get kind;

  /// The address currently selected on this device, or null.
  String? get address;

  /// False once the wallet was switched, disconnected or re-authorised since
  /// this source was captured.
  bool get isCurrent;

  /// Signs exactly [message] (UTF-8 bytes of Crossmint's ownership text) and
  /// returns the raw 64-byte ed25519 signature. Message signing only — this
  /// can never approve a transaction. Throws [DepositWalletDeclined] when the
  /// person says no or the wallet changed.
  Future<Uint8List> signMessage(Uint8List message);
}

class DepositWalletDeclined implements Exception {
  const DepositWalletDeclined();
}
