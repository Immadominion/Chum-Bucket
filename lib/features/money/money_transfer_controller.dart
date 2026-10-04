/// One USDC transfer: a cash out from the trading wallet to any Solana
/// address, or a top-up from one of the account's own wallets (a wallet app)
/// into the trading wallet.
///
/// prepare → review → sign (after [checkUsdcTransfer], on this phone) →
/// `money.transferSubmit` → `money.transferStatus` until the chain says. A
/// submit is never "done"; a lost reply resends the identical signed bytes.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:chumbucket/features/panta_trading/panta_trading.dart'
    show decodePantaTransaction;

import 'data/money_client.dart';
import 'data/money_models.dart';
import 'domain/money_gas.dart';
import 'domain/money_transfer_signer.dart';
import 'domain/usdc_transfer_check.dart';

enum MoneyTransferKind { cashOut, fromWallet }

enum MoneyTransferStep {
  idle,
  preparing,
  review,
  signing,
  submitting,

  /// Signed; the reply did not arrive. Resend the same bytes.
  sent,
  confirming,
  confirmed,
  failed,
}

class MoneyTransferController extends ChangeNotifier {
  MoneyTransferController({
    required MoneyClient client,
    required this.kind,
    required MoneyTransferSigner? Function(String wallet) signerFor,
    MoneyGasTopUp? topUp,
    String Function()? newIdempotencyKey,
    DateTime Function()? now,
    this.pollEvery = const Duration(seconds: 3),
    this.approvalTimeout = const Duration(minutes: 2),
  }) : _client = client,
       _signerFor = signerFor,
       _topUp = topUp,
       _newKey = newIdempotencyKey ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final MoneyClient _client;
  final MoneyTransferKind kind;
  final MoneyTransferSigner? Function(String wallet) _signerFor;
  final MoneyGasTopUp? _topUp;
  final String Function() _newKey;
  final DateTime Function() _now;
  final Duration pollEvery;

  /// How long a wallet may take to approve before the sheet gives up on it.
  final Duration approvalTimeout;

  /// A review that was never signed, still open on the server until then:
  /// a new one may be prepared only after it.
  int? _blockedUntil;

  MoneyTransferStep _step = MoneyTransferStep.idle;
  TransferReady? _ready;
  ExpectedUsdcTransfer? _expected;
  TransferView? _transfer;
  String? _signed;
  String? _error;
  bool _busy = false;
  bool _disposed = false;
  Timer? _poll;

  /// One key per review. Reused only to repeat a request whose reply never
  /// arrived; a review lives 60 s on the server, so anything else (a new
  /// amount or address, an expired or refused review) starts a new one.
  String? _key;
  String? _keyFor;
  bool _replyLost = false;

  MoneyTransferStep get step => _step;
  TransferReady? get ready => _ready;
  TransferView? get transfer => _transfer;
  String? get error => _error;
  bool get busy => _busy;
  bool get reviewExpired =>
      _ready != null && _now().millisecondsSinceEpoch >= _ready!.expiresAt;

  /// The signer opens a wallet app (its own approval screen).
  bool get opensWalletApp =>
      _ready != null &&
      (_signerFor(_ready!.review.from)?.opensWalletApp ?? false);

  /// Builds the reviewed transfer. [from] pays and signs; [to] receives.
  /// Cash out: [from] is the trading wallet, [to] the typed address. From a
  /// wallet: [from] is the person's wallet app, [to] the trading wallet.
  Future<void> prepare({
    required String from,
    required String to,
    required BigInt amountBaseUnits,
  }) => _run(() async {
    // A signed transfer that hasn't settled is never followed by another:
    // keep sending (or watching) that one.
    if (_inFlight) {
      _resumeInFlight();
      return;
    }
    final until = _blockedUntil;
    if (until != null && _now().millisecondsSinceEpoch < until) {
      throw const MoneyException(
        MoneyErrorKind.conflict,
        'Nothing was sent. Try again in a moment.',
      );
    }
    _blockedUntil = null;
    final request = '$from>$to:$amountBaseUnits';
    if (_keyFor != request || !_replyLost) {
      _key = _newKey();
      _keyFor = request;
    }
    _replyLost = false;
    _expected = null;
    _set(MoneyTransferStep.preparing);
    var gasRuns = 0;
    while (true) {
      final TransferPrepareResult result;
      try {
        result = await _prepareOnce(from, to, amountBaseUnits);
      } on MoneyException catch (e) {
        // Another transfer from this wallet is still going through: watch
        // that one (the server names it) instead of starting a second.
        final flying = e.inFlightTransferId;
        if (e.kind == MoneyErrorKind.conflict && flying != null) {
          await _watch(flying);
          return;
        }
        rethrow;
      }
      if (_disposed) return;
      switch (result) {
        case TransferSent(:final transfer):
          // This key was already signed: its actual state, never a review.
          _adopt(transfer);
          return;
        case TransferInvalid(:final message):
          // The server's words: "That's a token account, not a wallet."
          _keyFor = null;
          _error = message;
          _set(MoneyTransferStep.idle);
          return;
        case TransferNeedsGas(:final wallet, :final topUpBaseUnits):
          // Gas is only ever topped up on the wallet that pays this transfer.
          if (wallet.address != from) {
            throw const MoneyException(MoneyErrorKind.invalidResponse);
          }
          final topUp = _topUp;
          if (topUp == null || topUpBaseUnits == null || gasRuns >= 2) {
            throw const MoneyException(MoneyErrorKind.unavailable);
          }
          gasRuns++;
          await topUp(wallet.address, topUpBaseUnits);
          if (_disposed) return;
          continue;
        case TransferReady():
          final expected = ExpectedUsdcTransfer.fromReview(
            result.review,
            from: from,
            to: to,
            amountBaseUnits: amountBaseUnits,
          );
          decodePantaTransaction(result.payload);
          _ready = result;
          _expected = expected;
          _transfer = result.transfer;
          _set(MoneyTransferStep.review);
          return;
      }
    }
  });

  Future<TransferPrepareResult> _prepareOnce(
    String from,
    String to,
    BigInt amountBaseUnits,
  ) => switch (kind) {
    MoneyTransferKind.cashOut => _client.cashOutPrepare(
      destination: to,
      amountBaseUnits: amountBaseUnits,
      idempotencyKey: _key!,
    ),
    MoneyTransferKind.fromWallet => _client.depositFromWalletPrepare(
      fromWallet: from,
      amountBaseUnits: amountBaseUnits,
      idempotencyKey: _key!,
    ),
  };

  /// Signed bytes we hold, or a transfer the server is sending: either way
  /// nothing new may be prepared until it confirms or fails.
  bool get _inFlight =>
      _signed != null ||
      (_transfer?.state == TransferState.submitted);

  /// Picks up a transfer already on its way, by the server's id.
  Future<void> _watch(String transferId) async {
    final view = await _client.transferStatus(transferId);
    if (_disposed) return;
    if (view.transferId != transferId) {
      throw const MoneyException(MoneyErrorKind.invalidResponse);
    }
    _adopt(view);
  }

  void _adopt(TransferView view) {
    _ready = null;
    _expected = null;
    _transfer = view;
    _applyState(view);
    if (_step == MoneyTransferStep.confirming ||
        _step == MoneyTransferStep.sent) {
      _startPolling();
    }
    if (!_disposed) notifyListeners();
  }

  void _resumeInFlight() {
    _step =
        _signed != null && _transfer?.state != TransferState.submitted
            ? MoneyTransferStep.sent
            : MoneyTransferStep.confirming;
    _startPolling();
    if (!_disposed) notifyListeners();
  }

  /// While the outcome of signed bytes is unknown the sheet stays: closing
  /// would drop the only copy that may be resent.
  bool get canDismiss =>
      _step != MoneyTransferStep.signing &&
      _step != MoneyTransferStep.submitting &&
      _step != MoneyTransferStep.sent;

  /// Checks the exact bytes on this phone, signs them, and hands them over.
  Future<void> sign() {
    final ready = _ready, expected = _expected;
    if (_step != MoneyTransferStep.review || ready == null || expected == null) {
      return Future.value();
    }
    return _run(() async {
      if (reviewExpired) {
        _ready = null;
        _set(MoneyTransferStep.idle);
        throw const MoneyException(
          MoneyErrorKind.invalid,
          'That review expired. Nothing was signed.',
        );
      }
      final signer = _signerFor(expected.from);
      if (signer == null) {
        throw const MoneyException(
          MoneyErrorKind.unavailable,
          'This wallet can’t sign here.',
        );
      }
      _set(MoneyTransferStep.signing);
      final bytes = decodePantaTransaction(ready.payload);
      try {
        final signed = await signer
            .signTransfer(bytes, expected)
            .timeout(approvalTimeout);
        _signed = base64Encode(signed);
      } catch (e) {
        _step = MoneyTransferStep.review;
        throw switch (e) {
          TransferSignCancelled() => const MoneyException(
            MoneyErrorKind.unavailable,
            'Cancelled. Nothing was signed.',
          ),
          TransferCheckException() => const MoneyException(
            MoneyErrorKind.invalidResponse,
            'That transfer didn’t match. Nothing was signed.',
          ),
          _ => const MoneyException(
            MoneyErrorKind.unavailable,
            'Your wallet didn’t sign. Nothing was sent.',
          ),
        };
      }
      if (_disposed) return;
      await _submit();
    });
  }

  Future<void> resend() {
    if (_step != MoneyTransferStep.sent || _signed == null) {
      return Future.value();
    }
    return _run(_submit);
  }

  Future<void> _submit() async {
    final ready = _ready!;
    _set(MoneyTransferStep.submitting);
    try {
      final view = await _client.transferSubmit(
        transferId: ready.transfer.transferId,
        signedTransaction: _signed!,
      );
      if (_disposed) return;
      _accept(view);
    } on MoneyException catch (e) {
      if (_disposed) rethrow;
      // The server answered that these bytes can never be sent (the review
      // expired, or the approval doesn't match it): drop them, start again.
      if (e.reason == MoneyReason.reviewExpired || e.reason == 'BAD_SIGNATURE') {
        _signed = null;
        _ready = null;
        _expected = null;
        _transfer = null;
        _step = MoneyTransferStep.idle;
        rethrow;
      }
      _step = MoneyTransferStep.sent;
      _startPolling();
      rethrow;
    } catch (_) {
      if (!_disposed) {
        _step = MoneyTransferStep.sent;
        _startPolling();
      }
      rethrow;
    }
    _startPolling();
  }

  Future<void> refreshStatus() async {
    final id = _transfer?.transferId ?? _ready?.transfer.transferId;
    if (_disposed || id == null) return;
    try {
      final view = await _client.transferStatus(id);
      if (_disposed) return;
      _accept(view);
      notifyListeners();
    } on MoneyException {
      // The next read tries again.
    }
  }

  void _accept(TransferView view) {
    final ready = _ready;
    final same =
        ready != null
            ? view.transferId == ready.transfer.transferId &&
                view.from == ready.review.from &&
                view.to == ready.review.to &&
                view.amountBaseUnits == ready.review.amountBaseUnits
            : view.transferId == _transfer?.transferId &&
                view.from == _transfer?.from &&
                view.to == _transfer?.to &&
                view.amountBaseUnits == _transfer?.amountBaseUnits;
    if (!same) throw const MoneyException(MoneyErrorKind.invalidResponse);
    _transfer = view;
    _applyState(view);
  }

  void _applyState(TransferView view) {
    switch (view.state) {
      case TransferState.confirmed:
        _stopPolling();
        _signed = null;
        _step = MoneyTransferStep.confirmed;
      case TransferState.failed:
        _stopPolling();
        _signed = null;
        _step = MoneyTransferStep.failed;
      case TransferState.submitted:
        _step = MoneyTransferStep.confirming;
      case TransferState.built:
        if (_signed != null) {
          // Our bytes never arrived: keep the resend offer.
          _step = MoneyTransferStep.sent;
        } else {
          // Never signed: nothing was sent. A new review may follow once
          // this one's time is up on the server.
          _stopPolling();
          _blockedUntil = view.expiresAt;
          _error = 'Nothing was sent.';
          _step = MoneyTransferStep.idle;
        }
    }
  }

  /// Back to entry (a new address or amount), when nothing is in flight.
  void reset() {
    if (_busy ||
        _step == MoneyTransferStep.signing ||
        _step == MoneyTransferStep.submitting ||
        _step == MoneyTransferStep.sent ||
        _step == MoneyTransferStep.confirming) {
      return;
    }
    _ready = null;
    _expected = null;
    _transfer = null;
    _error = null;
    _set(MoneyTransferStep.idle);
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
    notifyListeners();
    try {
      await action();
    } catch (error) {
      if (_disposed) return;
      _error = switch (error) {
        MoneyException(:final message) => message,
        TransferCheckException() =>
          'That transfer didn’t match. Nothing was signed.',
        _ => const MoneyException(MoneyErrorKind.invalidResponse).message,
      };
      if (_step == MoneyTransferStep.preparing) {
        // No answer we could read: the review may exist under this key, so
        // the next try asks again with it (a replay is safe for 60 s, then
        // the server says start again and a new key follows).
        _replyLost =
            error is MoneyException &&
            (error.kind == MoneyErrorKind.connection ||
                error.kind == MoneyErrorKind.provider ||
                error.kind == MoneyErrorKind.invalidResponse);
        _step = MoneyTransferStep.idle;
      }
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _set(MoneyTransferStep step) {
    _step = step;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _signed = null;
    super.dispose();
  }
}
