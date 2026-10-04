/// Signs a USDC transfer (a cash out, or a top-up from one of your own
/// wallets) — only after [checkUsdcTransfer] has passed on this phone's own
/// copy of the bytes, whoever holds the key: the Chumbucket wallet, the
/// wallet on this phone, or a wallet app over Mobile Wallet Adapter.
///
/// The answer must be the same transaction with only the signer's slot
/// filled (`adoptSignerAnswer`); anything else is refused before it can
/// reach the BFF.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/chumbucket_wallet/signed_transaction.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart'
    show PantaWalletCancelled;

import 'usdc_transfer_check.dart';

/// The person backed out in their wallet. Nothing was signed.
class TransferSignCancelled implements Exception {
  const TransferSignCancelled();
}

/// The wallet could not sign the checked transfer. Nothing was sent.
class TransferSignFailed implements Exception {
  const TransferSignFailed();
}

/// Returns the signed transaction, a 64-byte signature, or throws
/// [PantaWalletCancelled] / [TransferSignCancelled] when declined.
typedef RawTransferSign =
    Future<Uint8List> Function(Uint8List unsigned, Uint8List message);

class MoneyTransferSigner {
  MoneyTransferSigner({
    required this.address,
    required RawTransferSign sign,
    this.opensWalletApp = false,
    this.check = checkUsdcTransfer,
  }) : _sign = sign;

  /// The wallet that pays and signs (`from`).
  final String address;
  final RawTransferSign _sign;

  /// A wallet app shows its own approval; the sheet says so.
  final bool opensWalletApp;
  final Future<Uint8List> Function(Uint8List, ExpectedUsdcTransfer) check;

  Future<Uint8List> signTransfer(
    Uint8List unsigned,
    ExpectedUsdcTransfer expected,
  ) async {
    if (expected.from != address) {
      throw const TransferCheckException('signer');
    }
    // On its own copy: nothing the wallet does can change what was checked.
    final copy = Uint8List.fromList(unsigned);
    final message = await check(copy, expected);
    final Uint8List answer;
    try {
      answer = await _sign(Uint8List.fromList(copy), message);
    } on PantaWalletCancelled {
      throw const TransferSignCancelled();
    } on TransferSignCancelled {
      rethrow;
    } catch (_) {
      throw const TransferSignFailed();
    }
    try {
      return adoptSignerAnswer(copy, answer);
    } on SignedTransactionMismatch {
      throw const TransferSignFailed();
    }
  }
}
