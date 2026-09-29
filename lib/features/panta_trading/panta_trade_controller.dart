import 'dart:async';
import 'dart:convert';

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'data/panta_trading_client.dart';
import 'data/panta_trading_models.dart';
import 'domain/panta_transaction_validator.dart';
import 'domain/panta_wallet_port.dart';

enum PantaTradePhase {
  amount,
  preparing,
  review,
  approving,
  signed,
  submitting,
  order,
  cancelled,
}

/// One user intent, bound to an existing call/account/wallet. Keep this instance
/// alive across an uncertain submit so retries reuse the signed bytes in memory.
/// Status polling is manual: no timer or background broadcast belongs to mobile.
class PantaTradeController extends ChangeNotifier {
  PantaTradeController({
    required this.callId,
    required this.marketId,
    required this.venueMarketId,
    required this.side,
    required this.wallet,
    required PantaTradingClient client,
    required PantaWalletPort walletPort,
    required PantaSelectedWalletProvider selectedWallet,
    DateTime Function()? now,
    String Function()? newIdempotencyKey,
    this.walletApprovalTimeout = const Duration(minutes: 2),
  }) : _client = client,
       _walletPort = walletPort,
       _selectedWallet = selectedWallet,
       _now = now ?? DateTime.now,
       _newKey = newIdempotencyKey ?? const Uuid().v4 {
    validatePantaWallet(wallet);
    if (callId.isEmpty ||
        marketId.isEmpty ||
        venueMarketId.isEmpty ||
        walletApprovalTimeout <= Duration.zero) {
      throw ArgumentError('An existing call, market, and wallet are required.');
    }
  }

  final String callId;

  /// The existing catalog's local market ID; never added to the wire input.
  final String marketId;

  /// The existing market's Panta venueMarketId, used to bind the reviewed quote.
  final String venueMarketId;
  final Side side;
  final String wallet;
  final PantaTradingClient _client;
  final PantaWalletPort _walletPort;
  final PantaSelectedWalletProvider _selectedWallet;
  final DateTime Function() _now;
  final String Function() _newKey;
  final Duration walletApprovalTimeout;
  final _validator = const PantaTransactionValidator();

  PantaTradePhase _phase = PantaTradePhase.amount;
  PantaTradingStatus? _status;
  PantaPreparedTrade? _prepared;
  PantaVenueOrder? _order;
  PantaException? _error;
  String _amountText = '';
  String? _intentKey;
  String? _accountId;
  String? _signedPayload;
  bool _submitAttempted = false;
  bool _inFlight = false;
  bool _disposed = false;
  int _revision = 0;

  PantaTradePhase get phase => _phase;
  PantaTradingStatus? get status => _status;
  PantaPreparedTrade? get prepared => _prepared;
  PantaVenueOrder? get order => _order;
  PantaException? get error => _error;
  String get amountText => _amountText;
  bool get isBusy => _inFlight;
  bool get isFunded => _order?.isFunded ?? false;
  bool get canCancel => !_submitAttempted && !_disposed;
  bool get canEditAmount =>
      !_inFlight && !_submitAttempted && _signedPayload == null;
  bool get canRetrySigned =>
      !_inFlight && _phase == PantaTradePhase.signed && _signedPayload != null;
  bool get canCheckOrder =>
      !_inFlight &&
      _orderId != null &&
      (_submitAttempted || _signedPayload != null);
  String? get _orderId => _prepared?.order.orderId ?? _order?.orderId;
  bool get quoteExpired => _prepared?.order.isExpiredAt(_now()) ?? false;
  bool get validAmount {
    try {
      PantaUsdcAmount.parse(_amountText);
      return true;
    } on PantaException {
      return false;
    }
  }

  /// Only an explicit edit or pre-submit cancellation can abandon an intent.
  void editAmount(String value) {
    if (_disposed ||
        !canEditAmount ||
        (value == _amountText && _phase != PantaTradePhase.cancelled)) {
      return;
    }
    _revision++;
    _amountText = value;
    _intentKey = null;
    _accountId = null;
    _prepared = null;
    _order = null;
    _error = null;
    _phase = PantaTradePhase.amount;
    _publish();
  }

  Future<void> loadStatus() => _run((revision) async {
    final status = await _client.status();
    if (!_current(revision)) return;
    _status = status;
    if (_prepared == null && _order == null && !_submitAttempted) {
      await _restoreForCall(revision, optionalSession: true);
    }
  });

  Future<void> prepare() {
    if (_disposed || _signedPayload != null || _submitAttempted) {
      return Future.value();
    }
    return _run(_prepareIntent);
  }

  Future<void> _prepareIntent(int revision) async {
    _phase = PantaTradePhase.preparing;
    _publish();
    final status = await _client.status();
    if (!_current(revision)) return;
    _status = status;
    await _checkContext(anchor: true);
    if (!_current(revision)) return;
    if (await _restoreForCall(revision)) return;
    if (!_current(revision)) return;
    if (!status.enabled) throw const PantaException(PantaErrorCode.unavailable);
    final amount = PantaUsdcAmount.parse(_amountText);
    _intentKey ??= _newKey();
    final prepared = await _client.prepare(
      PantaPrepareInput(
        callId: callId,
        wallet: wallet,
        amountBaseUnits: amount.baseUnits,
        idempotencyKey: _intentKey!,
      ),
      accountId: _accountId!,
    );
    if (!_current(revision)) return;
    final order = prepared.order;
    _require(
      order.owner == wallet &&
          order.side == side &&
          order.venueMarketId == venueMarketId &&
          order.amountBaseUnits == amount.baseUnits &&
          order.idempotencyKey == _intentKey,
    );
    _validator.validateUnsigned(order.transaction.bytes, wallet);
    if (order.isExpiredAt(_now())) {
      throw const PantaException(PantaErrorCode.expired);
    }
    _prepared = prepared;
    _phase = PantaTradePhase.review;
  }

  /// The ONLY entry into wallet approval; call this from the explicit Review CTA.
  /// An expired quote cannot be approved. The BFF does not renew a UUID, so
  /// an explicit edit/cancel must precede a fresh intent and another review.
  Future<void> approveReview() {
    if (_phase != PantaTradePhase.review || _prepared == null) {
      return Future.value();
    }
    return _run((revision) async {
      await _checkContext();
      if (!_current(revision)) return;
      if (quoteExpired) {
        throw const PantaException(PantaErrorCode.expired);
      }
      final quote = _prepared!;
      final unsigned = quote.order.transaction.bytes;
      _validator.validateUnsigned(unsigned, wallet);
      _phase = PantaTradePhase.approving;
      _publish();
      final Uint8List signed;
      try {
        signed = Uint8List.fromList(
          await _walletPort
              .signTransaction(Uint8List.fromList(unsigned))
              .timeout(walletApprovalTimeout),
        );
      } on PantaWalletCancelled {
        if (_current(revision)) {
          cancel();
          _error = const PantaException(PantaErrorCode.walletCancelled);
        }
        return;
      } on PantaException {
        rethrow;
      } catch (_) {
        throw const PantaException(PantaErrorCode.signingFailed);
      }
      if (!_current(revision)) return;
      _validator.validateSigned(unsigned, signed, wallet);
      await _checkContext();
      if (!_current(revision)) return;
      if (quote.order.isExpiredAt(_now())) {
        throw const PantaException(PantaErrorCode.expired);
      }
      _signedPayload = base64Encode(signed);
      _phase = PantaTradePhase.signed;
      await _submitSigned(revision);
    });
  }

  /// Even past quote expiry, an uncertain submit MUST reuse these exact bytes.
  /// The server handles replay/expiry; it may already have broadcast the order.
  Future<void> retrySignedSubmit() {
    if (!canRetrySigned) return Future.value();
    return _run(_submitSigned);
  }

  Future<void> _submitSigned(int revision) async {
    await _checkContext();
    if (!_current(revision)) return;
    _phase = PantaTradePhase.submitting;
    _submitAttempted = true;
    _publish();
    final order = await _client.submit(
      orderId: _prepared!.order.orderId,
      signedTransaction: _signedPayload!,
      accountId: _accountId!,
    );
    if (!_current(revision)) return;
    _acceptOrder(order);
  }

  Future<void> refreshOrder() {
    if (!canCheckOrder) return Future.value();
    return _run((revision) async {
      await _checkContext();
      if (!_current(revision)) return;
      final order = await _client.order(
        orderId: _orderId!,
        accountId: _accountId!,
      );
      if (_current(revision)) _acceptOrder(order);
    });
  }

  void _acceptOrder(PantaVenueOrder order) {
    final quote = _prepared?.order;
    _require(
      order.owner == wallet &&
          order.venueMarketId == venueMarketId &&
          order.side == side,
    );
    if (quote != null) {
      _require(
        order.orderId == quote.orderId &&
            order.amountBaseUnits == quote.amountBaseUnits &&
            (order.idempotencyKey == null ||
                order.idempotencyKey == quote.idempotencyKey),
      );
    }
    if (_order != null) {
      _require(
        order.orderId == _order!.orderId &&
            order.amountBaseUnits == _order!.amountBaseUnits &&
            order.idempotencyKey == _order!.idempotencyKey,
      );
      _require(order.updatedAt >= _order!.updatedAt);
      if (_order!.isFunded) _require(order.isFunded);
    }
    _order = order;
    _phase = PantaTradePhase.order;
  }

  Future<bool> _restoreForCall(
    int revision, {
    bool optionalSession = false,
  }) async {
    if (optionalSession) {
      final session = await _client.currentSession();
      if (!_current(revision)) return false;
      if (session == null ||
          session.accountId.isEmpty ||
          session.accessToken.isEmpty) {
        return false;
      }
      await _checkContext(anchor: true);
      if (!_current(revision)) return false;
    }
    final restored = await _client.forCall(
      callId: callId,
      wallet: wallet,
      accountId: _accountId!,
    );
    if (!_current(revision) || restored == null) return false;
    await _checkContext();
    if (!_current(revision)) return false;
    _require(
      restored.fundingState == PantaFundingState.submitted ||
          restored.fundingState == PantaFundingState.filled,
    );
    _acceptOrder(restored);
    _submitAttempted = true;
    _signedPayload = null;
    return true;
  }

  Future<void> _checkContext({bool anchor = false}) async {
    final session = await _client.currentSession();
    if (session == null ||
        session.accountId.isEmpty ||
        session.accessToken.isEmpty) {
      throw const PantaException(PantaErrorCode.signedOut);
    }
    if (anchor) _accountId ??= session.accountId;
    if (session.accountId != _accountId) {
      throw const PantaException(PantaErrorCode.sessionChanged);
    }
    final String? selected;
    try {
      selected = await Future<String?>.sync(
        _selectedWallet,
      ).timeout(_client.timeout);
    } catch (_) {
      throw const PantaException(PantaErrorCode.connection);
    }
    if (selected != wallet) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    final latest = await _client.currentSession();
    if (latest == null ||
        latest.accountId.isEmpty ||
        latest.accessToken.isEmpty) {
      throw const PantaException(PantaErrorCode.signedOut);
    }
    if (latest.accountId != _accountId) {
      throw const PantaException(PantaErrorCode.sessionChanged);
    }
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (_disposed || _inFlight) return;
    _inFlight = true;
    _error = null;
    final revision = _revision;
    _publish();
    try {
      await action(revision);
    } catch (error) {
      if (_current(revision)) {
        _error =
            error is PantaException
                ? error
                : const PantaException(PantaErrorCode.invalidResponse);
        if (_signedPayload != null && _phase != PantaTradePhase.order) {
          _phase = PantaTradePhase.signed;
        } else if (_phase == PantaTradePhase.approving) {
          _phase = PantaTradePhase.review;
        } else if (_phase == PantaTradePhase.preparing) {
          _prepared = null;
          _phase = PantaTradePhase.amount;
        }
      }
    } finally {
      _inFlight = false;
      _publish();
    }
  }

  /// False once submit may have reached the server: closing then is not an
  /// order cancellation, and must never label an uncertain order cancelled.
  bool cancel() {
    if (!canCancel) return false;
    _revision++;
    _intentKey = null;
    _accountId = null;
    _prepared = null;
    _signedPayload = null;
    _error = null;
    _phase = PantaTradePhase.cancelled;
    _publish();
    return true;
  }

  bool _current(int revision) => !_disposed && revision == _revision;
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void _require(bool condition) {
    if (!condition) throw const PantaException(PantaErrorCode.invalidResponse);
  }

  /// Caller owns the client separately. Disposal invalidates pending callbacks.
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _signedPayload = null;
    super.dispose();
  }
}
