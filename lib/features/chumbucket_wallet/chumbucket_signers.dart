/// The Chumbucket wallet as every signer the app's money flows take: a Panta
/// buy, a Panta win claim, a gasless SOL top-up, and the deposit ownership
/// proof.
///
/// Like the on-phone wallet, the Chumbucket wallet shows no second screen:
/// the review sheet's button is the person's approval. So each adapter first
/// runs the same independent shape check the on-phone wallet runs
/// (`checkPantaBuyForEmbeddedSigning`, `checkPantaClaimForEmbeddedSigning`,
/// the swap check), and only then asks the wallet to sign those exact bytes.
/// The answer must be the same transaction with only the wallet's own slot
/// filled; the BFF re-checks and broadcasts it.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/deposits/data/device_deposit_wallet_source.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_claim.dart'
    show checkPantaClaimForEmbeddedSigning;
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart'
    show PantaReviewedBuy, checkPantaBuyForEmbeddedSigning;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart'
    show CheckedSwap;
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';

import 'chumbucket_wallet_controller.dart';

/// A reviewed Panta primary buy, signed by the Chumbucket wallet.
class PantaChumbucketWallet implements PantaWalletPort {
  PantaChumbucketWallet({
    required ChumbucketWalletSigner? Function() signer,
    required this.address,
    required this.reviewed,
  }) : _signer = signer;

  /// Re-read at signing: another account or wallet since review is refused.
  final ChumbucketWalletSigner? Function() _signer;
  final String address;
  final PantaReviewedBuy reviewed;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    final signer = _signer();
    if (signer == null || signer.address != address) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    final amount = reviewed.amountBaseUnits();
    if (amount == null) {
      throw const PantaException(PantaErrorCode.signingFailed);
    }
    await checkPantaBuyForEmbeddedSigning(
      unsigned,
      owner: address,
      venueMarketId: reviewed.venueMarketId,
      side: reviewed.side,
      amountBaseUnits: amount,
    );
    return _sign(signer, unsigned);
  }
}

/// A reviewed Panta win claim on the Chumbucket wallet's own position.
class PantaChumbucketClaimWallet implements PantaWalletPort {
  PantaChumbucketClaimWallet({
    required ChumbucketWalletSigner? Function() signer,
    required this.intent,
  }) : _signer = signer;

  final ChumbucketWalletSigner? Function() _signer;
  final PantaClaimSigningIntent intent;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    final signer = _signer();
    if (signer == null || signer.address != intent.owner) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    await checkPantaClaimForEmbeddedSigning(unsigned, intent);
    return _sign(signer, unsigned);
  }
}

Future<Uint8List> _sign(
  ChumbucketWalletSigner signer,
  Uint8List unsigned,
) async {
  try {
    return await signer.signTransaction(unsigned);
  } catch (_) {
    // Provider errors can describe keys and users: fixed copy only.
    throw const PantaException(PantaErrorCode.signingFailed);
  }
}

/// A checked gasless swap (USDC -> SOL for fees), signed in the owner's slot.
class ChumbucketSolTopUpSigner implements SolTopUpSigner {
  ChumbucketSolTopUpSigner({
    required ChumbucketWalletSigner? Function() signer,
    required this.address,
  }) : _signer = signer;

  final ChumbucketWalletSigner? Function() _signer;

  @override
  final String address;

  @override
  TopUpSignerKind get kind => TopUpSignerKind.thisPhone;

  @override
  Future<Uint8List> sign(Uint8List unsigned, CheckedSwap checked) async {
    final signer = _signer();
    if (signer == null || signer.address != address) {
      throw const TopUpSignRefused();
    }
    final Uint8List signed;
    try {
      signed = await signer.signTransaction(
        unsigned,
        slot: checked.ownerSignatureIndex,
      );
    } catch (_) {
      throw const TopUpSignRefused();
    }
    return acceptSignedSwap(
      unsigned: unsigned,
      signed: signed,
      checked: checked,
      address: address,
    );
  }
}

/// Add funds' ownership proof, signed by the Chumbucket wallet.
DeviceDepositWalletSource chumbucketDepositWalletSource(
  ChumbucketWalletController wallet,
  ChumbucketWalletSigner signer,
) => DeviceDepositWalletSource(
  address: signer.address,
  currentAddress: () => wallet.address,
  sign: (message) => signer.signMessage(message),
);
