/// A wallet app (Mobile Wallet Adapter) held to the same shape checks as the
/// wallets with no second screen.
///
/// A wallet app shows its own simulation, but the phone does not lean on it:
/// before the app is opened, this runs the exact check the Chumbucket wallet
/// and the wallet on this phone run — `checkPantaBuyForEmbeddedSigning` for a
/// buy, `checkPantaClaimForEmbeddedSigning` for a win claim — on its own copy
/// of the bytes, hands the app that same copy, and keeps the answer only if it
/// is that copy with nothing but the owner's slot filled (`adoptSignerAnswer`).
/// Transfers (`MoneyTransferSigner`) and swaps (`checkGaslessSwap` before any
/// signer, `acceptSignedSwap` after) already work this way.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/chumbucket_wallet/signed_transaction.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'panta_embedded_claim.dart' show checkPantaClaimForEmbeddedSigning;
import 'panta_embedded_wallet.dart'
    show PantaReviewedBuy, checkPantaBuyForEmbeddedSigning;

/// Checks a copy, signs that copy, adopts only the same transaction back.
class CheckedPantaWalletPort implements PantaWalletPort {
  CheckedPantaWalletPort({
    required PantaWalletPort inner,
    required Future<void> Function(Uint8List copy) check,
  }) : _inner = inner,
       _check = check;

  final PantaWalletPort _inner;
  final Future<void> Function(Uint8List copy) _check;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    final copy = Uint8List.fromList(unsigned);
    // Refused here, the wallet app never opens.
    await _check(Uint8List.fromList(copy));
    final answer = await _inner.signTransaction(Uint8List.fromList(copy));
    try {
      return adoptSignerAnswer(copy, answer);
    } on SignedTransactionMismatch {
      throw const PantaException(PantaErrorCode.signingFailed);
    }
  }
}

/// The reviewed Panta buy, approved in the wallet app for [owner].
PantaWalletPort walletAppBuyPort(
  MwaAuthProvider app, {
  required String owner,
  required PantaReviewedBuy reviewed,
  PantaWalletPort? inner,
}) => CheckedPantaWalletPort(
  inner: inner ?? PantaMwaWallet(app),
  check: (copy) async {
    final amount = reviewed.amountBaseUnits();
    if (amount == null) {
      throw const PantaException(PantaErrorCode.signingFailed);
    }
    await checkPantaBuyForEmbeddedSigning(
      copy,
      owner: owner,
      venueMarketId: reviewed.venueMarketId,
      side: reviewed.side,
      amountBaseUnits: amount,
    );
  },
);

/// The reviewed win claim, approved in the wallet app.
PantaWalletPort walletAppClaimPort(
  MwaAuthProvider app, {
  required PantaClaimSigningIntent intent,
  PantaWalletPort? inner,
}) => CheckedPantaWalletPort(
  inner: inner ?? PantaMwaWallet(app),
  check: (copy) => checkPantaClaimForEmbeddedSigning(copy, intent),
);
