/// Network fees stay invisible: when the server answers `NEEDS_GAS`, the app
/// runs the existing gasless USDC→SOL swap for the exact amount the server
/// named, on the wallet it named, and then asks again. The person is never
/// asked for SOL.
///
/// Same discipline as the "SOL for fees" sheet (`SolTopUpController`): the
/// swap Jupiter offers is checked on this phone (`checkGaslessSwap`) and held
/// to the server's review before any signer sees it. A wallet app still
/// shows its own approval; the Chumbucket wallet and the wallet on this
/// phone sign the checked swap without a second screen.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/sol_topup/data/sol_topup_client.dart';
import 'package:chumbucket/features/sol_topup/data/sol_topup_models.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart';
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';
import 'package:chumbucket/features/sol_topup/sol_topup_controller.dart'
    show SwapChecker;

import '../data/money_models.dart';

/// Tops [wallet] up with [amountBaseUnits] of USDC swapped for SOL. Throws a
/// [MoneyException] when it did not land (nothing else is attempted).
typedef MoneyGasTopUp =
    Future<void> Function(String wallet, BigInt amountBaseUnits);

/// The largest silent top-up ever signed here: the server's hard cap on
/// `SOL_TOPUP_MAX_USDC` ($25).
final maxGasTopUpBaseUnits = BigInt.from(25000000);

/// The least SOL a dollar must buy, as the transaction itself guarantees:
/// 1,000,000 lamports per USDC (SOL at $1,000 or less). Anything worse is not
/// a top-up worth signing without asking.
final minLamportsPerUsdc = BigInt.from(1000000);

Future<void> runGasTopUp({
  required SolTopUpClient client,
  required SolTopUpSigner? signer,
  required String wallet,
  required BigInt amountBaseUnits,
  SwapChecker check = checkGaslessSwap,
  DateTime Function() now = DateTime.now,
}) async {
  if (signer == null || signer.address != wallet) {
    throw const MoneyException(MoneyErrorKind.unavailable);
  }
  if (amountBaseUnits <= BigInt.zero || amountBaseUnits > maxGasTopUpBaseUnits) {
    throw const MoneyException(MoneyErrorKind.unavailable);
  }
  final TopUpOrder order;
  try {
    order = await client.order(
      wallet: wallet,
      amountBaseUnits: amountBaseUnits,
    );
  } on TopUpException catch (e) {
    // Already enough SOL: nothing to do, the caller asks again.
    if (e.kind == TopUpErrorKind.enoughSol) return;
    throw MoneyException(switch (e.kind) {
      TopUpErrorKind.signedOut => MoneyErrorKind.signedOut,
      TopUpErrorKind.connection => MoneyErrorKind.connection,
      _ => MoneyErrorKind.unavailable,
    });
  }
  final review = order.review;
  final unsigned = Uint8List.fromList(base64Decode(order.transaction));
  final CheckedSwap checked;
  try {
    checked = await check(
      unsigned,
      ExpectedSwap(
        owner: wallet,
        inAmount: amountBaseUnits,
        router: review.router,
        quotedOutLamports: review.solOutLamports,
        feeBps: review.feeBps,
        nowSeconds: now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
  } catch (_) {
    throw const MoneyException(MoneyErrorKind.invalidResponse);
  }
  // What the swap itself guarantees, per dollar spent: never a bad rate.
  final perUsdc =
      checked.minOutLamports * BigInt.from(1000000) ~/ amountBaseUnits;
  if (perUsdc < minLamportsPerUsdc) {
    throw const MoneyException(MoneyErrorKind.invalidResponse);
  }
  if (review.wallet != wallet ||
      review.usdcInBaseUnits != amountBaseUnits ||
      checked.feePayer != review.feePayer ||
      (review.router == SwapRouter.metis &&
          review.feePayer != jupiterGasWallet)) {
    throw const MoneyException(MoneyErrorKind.invalidResponse);
  }
  final Uint8List signed;
  try {
    signed = await signer.sign(Uint8List.fromList(unsigned), checked);
  } on TopUpSignCancelled {
    throw const MoneyException(MoneyErrorKind.unavailable, 'Cancelled.');
  } catch (_) {
    throw const MoneyException(MoneyErrorKind.unavailable);
  }
  final TopUpResult result;
  try {
    result = await client.execute(
      requestId: order.requestId,
      signedTransaction: base64Encode(signed),
    );
  } on TopUpException {
    throw const MoneyException(MoneyErrorKind.provider);
  }
  if (result.outcome != TopUpOutcome.success) {
    throw const MoneyException(MoneyErrorKind.provider);
  }
}
