/// One tap of a call with an amount: your own call, or Tail/Fade on someone
/// else's. The money contract's flow (a):
///
/// ```
/// prepareCall ─┬─ NEEDS_FUNDS → deposit → (funds land) → prepareCall again (same key)
///              ├─ NEEDS_GAS   → gasless top-up        → prepareCall again (same key)
///              └─ READY: call created PENDING (owner-only) + Panta quote
///                    → sign (the signer checks the buy) → pantaTrading.submit
///                    → money.callStatus (poll) → FUNDED
///                                              → FAILED: retry · keep free · discard
/// ```
///
/// Nothing here ever says a call is funded: only the server's `FUNDED` does,
/// after Panta's confirmation and an RPC-proven USDC debit. A signature is
/// not a fill, and a lost reply is never a failure — the identical signed
/// bytes are resent, never signed again.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:chumbucket/features/calls/data/call_models.dart'
    show CallVisibility, Side;
import 'package:chumbucket/features/calls/data/calls_repository.dart'
    show CallFeedEntry;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'data/money_client.dart';
import 'data/money_models.dart';
import 'domain/money_gas.dart';

/// What the person asked for, before anything exists on the server.
class MoneyCallRequest {
  const MoneyCallRequest({
    required this.kind,
    required this.side,
    required this.venueMarketId,
    required this.question,
    required this.amountBaseUnits,
    this.marketId,
    this.targetCallId,
    this.confidence,
    this.thesis,
    this.visibility = CallVisibility.public,
  }) : assert((kind == MoneyCallKind.own) == (marketId != null)),
       assert((kind != MoneyCallKind.own) == (targetCallId != null));

  final MoneyCallKind kind;

  /// The side the actor's own call takes (Fade: the opposite of theirs).
  final Side side;

  /// The market's Panta id: the buy is checked against it before signing.
  final String venueMarketId;
  final String question;
  final BigInt amountBaseUnits;
  final String? marketId;
  final String? targetCallId;
  final double? confidence;
  final String? thesis;
  final CallVisibility visibility;
}

/// Who signs the buy, chosen before the quote so the quote is for them.
class MoneyBuySigner {
  const MoneyBuySigner({
    required this.address,
    required this.port,
    required this.selectedWallet,
    this.opensWalletApp = false,
  });

  final String address;

  /// Runs the existing buy shape check (`checkPantaBuyForEmbeddedSigning`)
  /// before the Chumbucket wallet or the wallet on this phone signs; a wallet
  /// app shows its own simulation.
  final PantaWalletPort port;

  /// Re-read before signing: a change of wallet since review is refused.
  final String? Function() selectedWallet;
  final bool opensWalletApp;
}

enum MoneyCallStep {
  idle,
  preparing,

  /// Not enough USDC: the deposit sheet, then [MoneyCallController.continueAfterFunds].
  needsFunds,
  review,
  signing,
  submitting,

  /// Signed, but the submit's reply did not arrive: resend the same bytes.
  sent,

  /// On its way: shown as pending, never funded, until the server says so.
  pending,
  funded,

  /// The trade failed or its quote lapsed: retry, keep free, or discard.
  failed,
  free,
  discarded,
  expired,

  /// Nothing can be done here now ([MoneyCallController.error] says why).
  stopped,
}

class MoneyCallController extends ChangeNotifier {
  MoneyCallController({
    required MoneyClient client,
    required PantaTradingClient trading,
    required this.request,
    required this.signer,
    MoneyGasTopUp? topUp,
    String Function()? newIdempotencyKey,
    DateTime Function()? now,
    this.pollEvery = const Duration(seconds: 3),
    this.walletApprovalTimeout = const Duration(minutes: 2),
  }) : _client = client,
       _trading = trading,
       _topUp = topUp,
       _now = now ?? DateTime.now,
       _key = (newIdempotencyKey ?? const Uuid().v4)();

  /// Picks up a pending call (after a restart, or from its own screen).
  factory MoneyCallController.resume({
    required MoneyClient client,
    required PantaTradingClient trading,
    required MoneyCallView moneyCall,
    required CallFeedEntry call,
    required MoneyBuySigner signer,
    MoneyGasTopUp? topUp,
    DateTime Function()? now,
    Duration pollEvery = const Duration(seconds: 3),
  }) {
    final controller = MoneyCallController(
      client: client,
      trading: trading,
      request: MoneyCallRequest(
        kind: moneyCall.kind,
        side: moneyCall.side,
        venueMarketId: call.market.venueMarketId,
        question: call.market.question,
        amountBaseUnits: moneyCall.amountBaseUnits,
        marketId: moneyCall.kind == MoneyCallKind.own ? moneyCall.marketId : null,
        targetCallId: moneyCall.targetCallId,
      ),
      signer: signer,
      topUp: topUp,
      now: now,
      pollEvery: pollEvery,
    );
    controller._moneyCall = moneyCall;
    controller._call = call;
    controller._applyState(moneyCall);
    return controller;
  }

  final MoneyClient _client;
  final PantaTradingClient _trading;
  final MoneyGasTopUp? _topUp;
  final DateTime Function() _now;
  final String _key;
  final MoneyCallRequest request;
  final MoneyBuySigner signer;
  final Duration pollEvery;
  final Duration walletApprovalTimeout;
  final _validator = const PantaTransactionValidator();

  MoneyCallStep _step = MoneyCallStep.idle;
  MoneyCallView? _moneyCall;
  CallFeedEntry? _call;
  PantaPreparedTrade? _prepared;
  MoneyNeedsFunds? _needsFunds;
  String? _signedPayload;
  String? _accountId;
  String? _error;
  bool _busy = false;
  bool _disposed = false;
  int _gasRuns = 0;
  Timer? _poll;
  bool _polling = false;
  bool _retryRefused = false;

  MoneyCallStep get step => _step;
  MoneyCallView? get moneyCall => _moneyCall;

  /// The call this money funds: owner-only while pending.
  CallFeedEntry? get call => _call;
  PantaPreparedTrade? get prepared => _prepared;
  MoneyNeedsFunds? get needsFunds => _needsFunds;
  String? get error => _error;
  bool get busy => _busy;

  /// The server refused a fresh quote (the price moved past the slippage,
  /// or the call's time is up): only a new call can follow.
  bool get retryRefused => _retryRefused;

  /// The idempotency key of this tap, reused on every retry of it.
  String get idempotencyKey => _key;

  bool get quoteExpired => _prepared?.order.isExpiredAt(_now()) ?? false;

  /// Closing the sheet now leaves nothing behind the person didn't choose.
  bool get canClose => switch (_step) {
    MoneyCallStep.signing || MoneyCallStep.submitting => false,
    _ => !_busy,
  };

  /// The money call exists and is still the person's to decide.
  bool get isOpenPending =>
      _moneyCall?.isPending == true &&
      _step != MoneyCallStep.pending &&
      _step != MoneyCallStep.sent;

  /// Starts the tap (or continues it with the same key).
  Future<void> prepare() => _run(_prepareOnce);

  /// The deposit landed: carry on exactly where the call left off.
  Future<void> continueAfterFunds() =>
      _moneyCall == null ? prepare() : retry();

  Future<void> _prepareOnce() async {
    _set(MoneyCallStep.preparing);
    await _anchorAccount();
    final result = await _client.prepareCall(
      kind: request.kind,
      marketId: request.marketId,
      targetCallId: request.targetCallId,
      side: request.kind == MoneyCallKind.own ? request.side.wire : null,
      amountBaseUnits: request.amountBaseUnits,
      idempotencyKey: _key,
      wallet: signer.address,
      confidence: request.confidence,
      thesis: request.thesis,
      visibility: request.visibility.wire,
    );
    if (_disposed) return;
    await _accept(result, again: _prepareOnce);
  }

  Future<void> _accept(
    MoneyPrepareResult result, {
    required Future<void> Function() again,
  }) async {
    switch (result) {
      case MoneyNeedsFunds():
        _require(result.wallet.address == signer.address);
        _needsFunds = result;
        _set(MoneyCallStep.needsFunds);
      case MoneyNeedsGas(:final wallet, :final topUpBaseUnits):
        _require(wallet.address == signer.address);
        final topUp = _topUp;
        // Never ask the person for SOL: no top-up here is the error state.
        if (topUp == null || topUpBaseUnits == null || _gasRuns >= 2) {
          throw const MoneyException(MoneyErrorKind.unavailable);
        }
        _gasRuns++;
        await topUp(wallet.address, topUpBaseUnits);
        if (_disposed) return;
        await again();
      case MoneyReady():
        _acceptReady(result);
      case MoneySettled(:final moneyCall, :final call):
        _require(call.call.id == moneyCall.callId);
        _moneyCall = moneyCall;
        _call = call;
        _applyState(moneyCall);
    }
  }

  void _acceptReady(MoneyReady ready) {
    final money = ready.moneyCall;
    final order = ready.trade.order;
    final amount = request.amountBaseUnits;
    _require(
      money.isPending &&
          money.kind == request.kind &&
          money.side == request.side &&
          money.amountBaseUnits == amount &&
          money.wallet == signer.address &&
          (request.kind == MoneyCallKind.own
              ? money.marketId == request.marketId
              : money.targetCallId == request.targetCallId) &&
          (_moneyCall == null || _moneyCall!.callId == money.callId) &&
          ready.call.call.id == money.callId &&
          ready.call.call.side == request.side &&
          (money.orderId == null || money.orderId == order.orderId) &&
          order.owner == signer.address &&
          order.side == request.side &&
          order.venueMarketId == request.venueMarketId &&
          order.amountBaseUnits == amount.toString(),
    );
    _validator.validateUnsigned(order.transaction.bytes, signer.address);
    _moneyCall = money;
    _call = ready.call;
    _prepared = ready.trade;
    _needsFunds = null;
    _signedPayload = null;
    _set(MoneyCallStep.review);
  }

  /// The person's approval: sign the reviewed buy, then hand it to the BFF.
  /// A lapsed quote is quoted again first (same key) and shown for review.
  Future<void> sign() {
    if (_step != MoneyCallStep.review || _prepared == null) {
      return Future.value();
    }
    return _run(() async {
      await _checkContext();
      if (quoteExpired) {
        // Quoted again under the same call; the new numbers are reviewed.
        final call = _moneyCall;
        try {
          if (call == null) {
            await _prepareOnce();
          } else {
            await _retryOnce(call);
          }
        } on MoneyException catch (e) {
          // The price moved past the slippage, or the window passed: only a
          // new call can follow this one.
          if (e.needsNewCall && call != null) {
            _retryRefused = true;
            _step = MoneyCallStep.failed;
          }
          rethrow;
        }
        return;
      }
      final quote = _prepared!;
      final unsigned = quote.order.transaction.bytes;
      _validator.validateUnsigned(unsigned, signer.address);
      _set(MoneyCallStep.signing);
      final Uint8List signed;
      try {
        signed = Uint8List.fromList(
          await signer.port
              .signTransaction(Uint8List.fromList(unsigned))
              .timeout(walletApprovalTimeout),
        );
      } on PantaWalletCancelled {
        _step = MoneyCallStep.review;
        throw const PantaException(PantaErrorCode.walletCancelled);
      } on PantaException {
        _step = MoneyCallStep.review;
        rethrow;
      } catch (_) {
        _step = MoneyCallStep.review;
        throw const PantaException(PantaErrorCode.signingFailed);
      }
      if (_disposed) return;
      try {
        _validator.validateSigned(unsigned, signed, signer.address);
        await _checkContext();
        if (quote.order.isExpiredAt(_now())) {
          throw const PantaException(PantaErrorCode.expired);
        }
      } catch (_) {
        _step = MoneyCallStep.review;
        rethrow;
      }
      _signedPayload = base64Encode(signed);
      await _submit();
    });
  }

  /// The same signed bytes again, after a reply that never came.
  Future<void> resend() {
    if (_step != MoneyCallStep.sent || _signedPayload == null) {
      return Future.value();
    }
    return _run(_submit);
  }

  Future<void> _submit() async {
    final quote = _prepared!;
    _set(MoneyCallStep.submitting);
    try {
      final order = await _trading.submit(
        orderId: quote.order.orderId,
        signedTransaction: _signedPayload!,
        accountId: _accountId!,
      );
      if (_disposed) return;
      _require(
        order.orderId == quote.order.orderId &&
            order.owner == signer.address &&
            order.side == request.side &&
            order.venueMarketId == request.venueMarketId &&
            order.amountBaseUnits == quote.order.amountBaseUnits,
      );
    } catch (_) {
      // It may have reached Panta: never "failed" from here, never re-signed.
      if (!_disposed) {
        _step = MoneyCallStep.sent;
        _startPolling();
      }
      rethrow;
    }
    _set(MoneyCallStep.pending);
    _startPolling();
  }

  /// Re-reads the call; the server re-checks a submitted order on Panta and
  /// the chain. FUNDED only after that transition wrote FILLED.
  Future<void> refreshStatus() async {
    final call = _moneyCall;
    if (_disposed || call == null || _polling) return;
    _polling = true;
    try {
      final status = await _client.callStatus(call.callId);
      if (_disposed) return;
      _require(status.moneyCall.callId == call.callId);
      _moneyCall = status.moneyCall;
      _applyState(status.moneyCall);
    } on MoneyException {
      // A missed read changes nothing on screen; the next one tries again.
    } finally {
      _polling = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _applyState(MoneyCallView view) {
    switch (view.state) {
      case MoneyCallState.funded:
        _stopPolling();
        _step = MoneyCallStep.funded;
      case MoneyCallState.free:
        _stopPolling();
        _step = MoneyCallStep.free;
      case MoneyCallState.expired:
        _stopPolling();
        _step = MoneyCallStep.expired;
      case MoneyCallState.pending:
        switch (view.trade) {
          case MoneyTradeState.submitted:
            if (_step != MoneyCallStep.sent) _step = MoneyCallStep.pending;
            _startPolling();
          case MoneyTradeState.failed:
            _stopPolling();
            _signedPayload = null;
            _step = MoneyCallStep.failed;
          case MoneyTradeState.filled:
            // Filled on Panta, not yet stamped funded: still pending.
            _step = MoneyCallStep.pending;
            _startPolling();
          case MoneyTradeState.none || MoneyTradeState.quoted:
            // Our submit may still be in flight: keep the resend offer.
            if (_step == MoneyCallStep.sent) break;
            if (_step != MoneyCallStep.review) {
              _stopPolling();
              _step = MoneyCallStep.failed;
            }
        }
    }
  }

  /// A fresh quote for a pending call whose trade failed or lapsed.
  Future<void> retry() {
    final call = _moneyCall;
    if (call == null || _busy) return Future.value();
    return _run(() async {
      _gasRuns = 0;
      _set(MoneyCallStep.preparing);
      await _anchorAccount();
      try {
        await _retryOnce(call);
      } on MoneyException catch (e) {
        switch (e.reason) {
          case _ when e.needsNewCall:
            _retryRefused = true;
          case MoneyReason.inFlight:
            // A buy for this call is already going through: watch it.
            _step = MoneyCallStep.pending;
            _startPolling();
            return;
          case MoneyReason.state:
            // Funded, free or expired since: show what it is now.
            _step = MoneyCallStep.pending;
            _startPolling();
            await refreshStatus();
            return;
        }
        rethrow;
      }
    });
  }

  Future<void> _retryOnce(MoneyCallView call) async {
    final result = await _client.retry(call.callId, wallet: signer.address);
    if (_disposed) return;
    await _accept(result, again: () => _retryOnce(call));
  }

  /// Go free instead: the pending call is withdrawn and a NEW free call is
  /// made at today's price and time ([call] becomes that new call). If the
  /// buy filled after all, the server answers with the funded call.
  Future<void> keepFree() {
    final call = _moneyCall;
    if (call == null || _busy) return Future.value();
    return _run(() async {
      final kept = await _client.keepFree(call.callId);
      if (_disposed) return;
      final state = kept.moneyCall.state;
      _require(
        kept.moneyCall.callId == call.callId &&
            (state == MoneyCallState.free || state == MoneyCallState.funded) &&
            kept.call.call.side == request.side &&
            (state == MoneyCallState.funded
                ? kept.call.call.id == call.callId
                : kept.call.call.id != call.callId),
      );
      _moneyCall = kept.moneyCall;
      _call = kept.call;
      _stopPolling();
      _set(
        state == MoneyCallState.funded
            ? MoneyCallStep.funded
            : MoneyCallStep.free,
      );
    });
  }

  /// Gone for good: the call never shows.
  Future<void> discard() {
    final call = _moneyCall;
    if (call == null || _busy) return Future.value();
    return _run(() async {
      final gone = await _client.discard(call.callId);
      if (_disposed) return;
      _require(
        gone.callId == call.callId && gone.state == MoneyCallState.expired,
      );
      _moneyCall = gone;
      _stopPolling();
      _set(MoneyCallStep.discarded);
    });
  }

  Future<void> _anchorAccount() async {
    final session = await _trading.currentSession();
    if (session == null ||
        session.accountId.isEmpty ||
        session.accessToken.isEmpty) {
      throw const PantaException(PantaErrorCode.signedOut);
    }
    _accountId ??= session.accountId;
    if (session.accountId != _accountId) {
      throw const PantaException(PantaErrorCode.sessionChanged);
    }
  }

  Future<void> _checkContext() async {
    await _anchorAccount();
    if (signer.selectedWallet() != signer.address) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
  }

  void _startPolling() {
    if (_disposed || _poll != null) return;
    _poll = Timer.periodic(pollEvery, (_) => refreshStatus());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed || _busy) return;
    _busy = true;
    _error = null;
    if (!_disposed) notifyListeners();
    final before = _step;
    try {
      await action();
    } catch (error) {
      if (_disposed) return;
      _error = switch (error) {
        MoneyException(:final message) => message,
        PantaException(:final code) => _pantaCopy(code),
        _ => const MoneyException(MoneyErrorKind.invalidResponse).message,
      };
      if (_step == MoneyCallStep.preparing) {
        // Nothing created yet: stop. A pending call keeps its choices.
        _step =
            _moneyCall?.isPending == true
                ? MoneyCallStep.failed
                : before == MoneyCallStep.needsFunds
                ? MoneyCallStep.needsFunds
                : MoneyCallStep.stopped;
      }
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  static String _pantaCopy(PantaErrorCode code) => switch (code) {
    PantaErrorCode.walletCancelled => 'Cancelled. Nothing was signed.',
    PantaErrorCode.signingFailed => 'Your wallet didn’t sign. Nothing was sent.',
    PantaErrorCode.walletAltered =>
      'Your wallet changed the transaction, so nothing was sent.',
    PantaErrorCode.expired => 'That price moved. Check the new one.',
    PantaErrorCode.walletChanged => 'Your wallet changed. Nothing was signed.',
    PantaErrorCode.sessionChanged => 'Your account changed. Nothing was signed.',
    PantaErrorCode.signedOut => 'Sign in again to continue.',
    PantaErrorCode.connection => 'No answer yet. Send it again.',
    PantaErrorCode.walletNotLinked => 'Link this wallet first.',
    PantaErrorCode.unavailable => 'Trading is paused right now.',
    _ => 'Something didn’t check out. Nothing was signed.',
  };

  void _set(MoneyCallStep step) {
    _step = step;
    if (!_disposed) notifyListeners();
  }

  void _require(bool condition) {
    if (!condition) throw const MoneyException(MoneyErrorKind.invalidResponse);
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _signedPayload = null;
    super.dispose();
  }
}
