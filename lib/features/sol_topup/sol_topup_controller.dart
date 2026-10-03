import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/sol_topup_client.dart';
import 'data/sol_topup_models.dart';
import 'domain/gasless_swap_check.dart';
import 'domain/sol_topup_signer.dart';

enum SolTopUpStage {
  loading,

  /// Swaps are off, unconfigured, or the account can't be read.
  unavailable,

  /// This wallet already has SOL for its next trades.
  notNeeded,

  /// Not enough USDC to swap (add funds first).
  needsUsdc,

  /// The wallet's key isn't on this device (a wallet app not connected).
  noSigner,

  /// A suggested amount, before any quote.
  choose,
  preparing,
  review,
  signing,
  sending,
  done,

  /// The swap didn't happen (or we don't know yet: [SolTopUpController.unknown]).
  failed,
}

typedef SwapChecker =
    Future<CheckedSwap> Function(Uint8List bytes, ExpectedSwap expected);

/// One "SOL for fees" visit. Every number shown is the server's read or the
/// transaction's own promise, checked on this phone; nothing is estimated
/// here.
class SolTopUpController extends ChangeNotifier {
  SolTopUpController({
    required SolTopUpClient client,
    required SolTopUpSigner? Function(String wallet) signerFor,
    this.wallet,
    SwapChecker check = checkGaslessSwap,
    DateTime Function()? now,
  }) : _client = client,
       _signerFor = signerFor,
       _check = check,
       _now = now ?? DateTime.now;

  final SolTopUpClient _client;
  final SolTopUpSigner? Function(String wallet) _signerFor;
  final SwapChecker _check;
  final DateTime Function() _now;

  /// The wallet to top up; null lets the server pick the account's wallet.
  final String? wallet;

  SolTopUpStage _stage = SolTopUpStage.loading;
  TopUpPlan? _plan;
  BigInt? _amount;
  TopUpOrder? _order;
  CheckedSwap? _checked;
  SolTopUpSigner? _signer;
  TopUpResult? _result;
  String? _message;
  bool _unknown = false;
  bool _belowMinimum = false;
  BigInt? _refused;
  bool _disposed = false;
  int _revision = 0;

  SolTopUpStage get stage => _stage;
  TopUpPlan? get plan => _plan;
  BigInt? get amount => _amount;
  TopUpOrder? get order => _order;
  CheckedSwap? get checked => _checked;
  SolTopUpSigner? get signer => _signer;
  TopUpResult? get result => _result;

  /// Plain words for the current problem, when there is one.
  String? get message => _message;

  /// The send's outcome is not known yet (a lost reply).
  bool get unknown => _unknown;

  /// Jupiter said this amount is below its gas-sponsorship minimum.
  bool get belowMinimum => _belowMinimum;

  bool get busy => switch (_stage) {
    SolTopUpStage.loading ||
    SolTopUpStage.preparing ||
    SolTopUpStage.signing ||
    SolTopUpStage.sending => true,
    _ => false,
  };

  /// Never closed while a wallet is open or the swap is being sent.
  bool get canDismiss =>
      _stage != SolTopUpStage.signing && _stage != SolTopUpStage.sending;

  bool get reviewExpired {
    final o = _order;
    return o != null && !_now().isBefore(o.expiresAt);
  }

  /// Amounts worth offering: the suggestion, then $2 and $5 steps up to the
  /// server's cap and the USDC on hand. After "below the minimum", only
  /// larger ones.
  List<BigInt> get amountOptions {
    final p = _plan;
    if (p == null) return const [];
    final usdc = BigInt.from(1000000);
    final base = p.suggestion?.amountBaseUnits ?? p.minBaseUnits;
    final candidates = <BigInt>{
      base,
      usdc * BigInt.two,
      usdc * BigInt.from(5),
    }.where(
      (a) =>
          a >= p.minBaseUnits &&
          a <= p.maxBaseUnits &&
          a <= p.usdcBaseUnits &&
          (_refused == null || a > _refused!) &&
          a >= base,
    );
    return candidates.toList()..sort();
  }

  void _set(SolTopUpStage next, {String? message}) {
    _stage = next;
    _message = message;
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final revision = ++_revision;
    _set(SolTopUpStage.loading);
    try {
      final status = await _client.status();
      if (_stale(revision)) return;
      if (!status.available) {
        _set(
          SolTopUpStage.unavailable,
          message:
              status.reasonMessage ??
              'Swapping USDC for SOL isn’t available right now.',
        );
        return;
      }
      final plan = await _client.plan(wallet: wallet);
      if (_stale(revision)) return;
      _plan = plan;
      _signer = _signerFor(plan.wallet);
      _amount = plan.suggestion?.amountBaseUnits;
      _belowMinimum = false;
      _refused = null;
      if (plan.blocker == 'ENOUGH_SOL') {
        _set(SolTopUpStage.notNeeded);
      } else if (plan.blocker == 'NEEDS_USDC' || plan.suggestion == null) {
        _set(SolTopUpStage.needsUsdc);
      } else if (_signer == null) {
        _set(SolTopUpStage.noSigner);
      } else {
        _set(SolTopUpStage.choose);
      }
    } on TopUpException catch (e) {
      if (_stale(revision)) return;
      _set(SolTopUpStage.unavailable, message: e.message);
    }
  }

  bool _stale(int revision) => _disposed || revision != _revision;

  void selectAmount(BigInt amount) {
    if (_stage != SolTopUpStage.choose && _stage != SolTopUpStage.review) {
      return;
    }
    if (!amountOptions.contains(amount)) return;
    _amount = amount;
    _order = null;
    _checked = null;
    _set(SolTopUpStage.choose);
  }

  /// A fresh, checked quote for [amount]. Nothing is signed.
  Future<void> prepare() async {
    final p = _plan, amount = _amount, signer = _signer;
    if (p == null || amount == null || signer == null || busy) return;
    final revision = ++_revision;
    _order = null;
    _checked = null;
    _set(SolTopUpStage.preparing);
    try {
      final order = await _client.order(
        wallet: p.wallet,
        amountBaseUnits: amount,
      );
      if (_stale(revision)) return;
      final r = order.review;
      final checked = await _check(
        Uint8List.fromList(base64Decode(order.transaction)),
        ExpectedSwap(
          owner: p.wallet,
          inAmount: amount,
          router: r.router,
          quotedOutLamports: r.solOutLamports,
          feeBps: r.feeBps,
          nowSeconds: _now().millisecondsSinceEpoch ~/ 1000,
        ),
      );
      if (_stale(revision)) return;
      if (r.wallet != p.wallet ||
          r.usdcInBaseUnits != amount ||
          checked.feePayer != r.feePayer ||
          (r.router == SwapRouter.metis && r.feePayer != jupiterGasWallet)) {
        throw const SwapCheckException('review differs from transaction');
      }
      _order = order;
      _checked = checked;
      _belowMinimum = false;
      _set(SolTopUpStage.review);
    } on TopUpException catch (e) {
      if (_stale(revision)) return;
      switch (e.kind) {
        case TopUpErrorKind.enoughSol:
          _set(SolTopUpStage.notNeeded);
        case TopUpErrorKind.needsUsdc:
          _set(SolTopUpStage.needsUsdc, message: e.message);
        case TopUpErrorKind.belowGaslessMinimum:
          _belowMinimum = true;
          _refused = amount;
          final bigger = amountOptions;
          _set(
            SolTopUpStage.choose,
            message:
                bigger.isEmpty
                    ? '${e.message} Send a little SOL from another wallet '
                        'instead.'
                    : '${e.message} Try ${usdcLabel(bigger.first)} USDC.',
          );
          if (bigger.isNotEmpty) _amount = bigger.first;
          if (!_disposed) notifyListeners();
        default:
          _set(SolTopUpStage.choose, message: e.message);
      }
    } catch (_) {
      // SwapCheckException, or anything this phone couldn't even decode (a
      // malformed transaction or address): never left spinning, never signed.
      if (_stale(revision)) return;
      _set(
        SolTopUpStage.choose,
        message:
            'The swap Jupiter offered didn’t pass this phone’s checks. '
            'Nothing was signed. Try again in a moment.',
      );
    }
  }

  /// Signs the reviewed swap with the person's wallet, then sends it.
  Future<void> approve() async {
    final order = _order, checked = _checked, signer = _signer;
    if (_stage != SolTopUpStage.review ||
        order == null ||
        checked == null ||
        signer == null) {
      return;
    }
    if (reviewExpired) {
      _order = null;
      _checked = null;
      _set(
        SolTopUpStage.choose,
        message: 'That quote expired. Get a fresh one. Nothing was signed.',
      );
      return;
    }
    final revision = ++_revision;
    _set(SolTopUpStage.signing);
    final Uint8List signed;
    try {
      signed = await signer.sign(
        Uint8List.fromList(base64Decode(order.transaction)),
        checked,
      );
    } on TopUpSignCancelled {
      if (_stale(revision)) return;
      _set(SolTopUpStage.review, message: 'Cancelled. Nothing was signed.');
      return;
    } catch (_) {
      if (_stale(revision)) return;
      _set(
        SolTopUpStage.review,
        message:
            'Your wallet didn’t sign the reviewed swap, so nothing was sent.',
      );
      return;
    }
    if (_stale(revision)) return;
    _set(SolTopUpStage.sending);
    try {
      final result = await _client.execute(
        requestId: order.requestId,
        signedTransaction: base64Encode(signed),
      );
      if (_stale(revision)) return;
      _result = result;
      switch (result.outcome) {
        case TopUpOutcome.success:
          _unknown = false;
          _set(SolTopUpStage.done);
        case TopUpOutcome.failed:
          _unknown = false;
          _order = null;
          _checked = null;
          _set(SolTopUpStage.failed, message: result.message);
        case TopUpOutcome.unknown:
          _unknown = true;
          _set(SolTopUpStage.failed, message: result.message);
      }
    } catch (error) {
      if (_stale(revision)) return;
      // The reply never came (or couldn't be read), or the server refused
      // before sending. Only a refusal is known not to have been sent.
      final e = error is TopUpException ? error : null;
      _unknown =
          e == null ||
          e.kind == TopUpErrorKind.connection ||
          e.kind == TopUpErrorKind.invalidResponse ||
          e.kind == TopUpErrorKind.provider;
      _set(
        SolTopUpStage.failed,
        message:
            _unknown
                ? 'We couldn’t hear back. Check your balance in a moment '
                    'before trying again.'
                : e!.message,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
