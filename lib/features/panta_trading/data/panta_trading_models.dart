import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:solana/base58.dart';

const pantaAttribution = 'Powered by Panta';
const pantaDefaultSlippageBps = 100;

enum PantaErrorCode {
  invalidAmount,
  unavailable,
  signedOut,
  sessionChanged,
  walletChanged,
  expired,
  invalidResponse,
  connection,
  rejected,
  walletCancelled,
  signingFailed,
}

/// Only fixed, local copy escapes this boundary; never a provider's message.
class PantaException implements Exception {
  const PantaException(this.code);
  final PantaErrorCode code;

  String get message => switch (code) {
    PantaErrorCode.invalidAmount =>
      'Enter more than 0 and at most 100 USDC, with up to 6 decimal places.',
    PantaErrorCode.unavailable => 'Panta funding is unavailable right now.',
    PantaErrorCode.signedOut => 'Sign in to your existing account to continue.',
    PantaErrorCode.sessionChanged =>
      'Your account changed. Return to the original account to continue.',
    PantaErrorCode.walletChanged =>
      'Your wallet changed. Select the reviewed wallet to continue.',
    PantaErrorCode.expired =>
      'This quote expired. Get a fresh quote to review.',
    PantaErrorCode.invalidResponse =>
      'The order could not be verified. Check its status before continuing.',
    PantaErrorCode.connection =>
      'The reply did not arrive. Retry this same request or check its status.',
    PantaErrorCode.rejected =>
      'The server could not accept this request. Check the order status.',
    PantaErrorCode.walletCancelled => 'Wallet approval was cancelled.',
    PantaErrorCode.signingFailed => 'Wallet approval could not be completed.',
  };

  @override
  String toString() => 'PantaException(${code.name}): $message';
}

/// Exact USDC conversion. The feature's local ceiling is 100 USDC.
/// No double, exponent, rounding, or truncation enters a request.
class PantaUsdcAmount {
  PantaUsdcAmount._(this.baseUnits);
  static final maxBaseUnits = BigInt.from(100000000);
  final String baseUnits;

  factory PantaUsdcAmount.parse(String input) {
    if (input.length > 32 ||
        !RegExp(r'^[0-9]+(?:\.[0-9]{1,6})?$').hasMatch(input)) {
      throw const PantaException(PantaErrorCode.invalidAmount);
    }
    final parts = input.split('.');
    final units =
        BigInt.parse(parts.first) * BigInt.from(1000000) +
        BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(6, '0'));
    if (units <= BigInt.zero || units > maxBaseUnits) {
      throw const PantaException(PantaErrorCode.invalidAmount);
    }
    return PantaUsdcAmount._(units.toString());
  }
}

enum PantaFundingState {
  none('NONE', 'No funding'),
  quoted('QUOTED', 'Quote ready'),
  submitted('SUBMITTED', 'Submitted · awaiting confirmation'),
  partial('PARTIAL', 'Partially filled'),
  filled('FILLED', 'Funded'),
  failed('FAILED', 'Order failed'),
  closed('CLOSED', 'Position closed'),
  claimable('CLAIMABLE', 'Ready to claim'),
  claimed('CLAIMED', 'Claimed');

  const PantaFundingState(this.wire, this.label);
  final String wire;
  final String label;

  static PantaFundingState fromWire(Object? value) =>
      values.firstWhere((state) => state.wire == value, orElse: _invalid);
}

class PantaTradingStatus {
  const PantaTradingStatus({required this.enabled, required this.reason});
  final bool enabled;

  /// Retained for the typed contract; never rendered as user-facing copy.
  final String? reason;
  String get venue => 'panta';
  String get attribution => pantaAttribution;

  factory PantaTradingStatus.fromJson(Object? value) {
    final json = _object(value);
    _panta(json);
    _expect(json['attribution'] == pantaAttribution);
    _expect(json['enabled'] is bool);
    return PantaTradingStatus(
      enabled: json['enabled'] as bool,
      reason: _nullableString(json, 'reason'),
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'reason': reason,
    'venue': venue,
    'attribution': attribution,
  };
}

class PantaPrepareInput {
  const PantaPrepareInput({
    required this.callId,
    required this.wallet,
    required this.amountBaseUnits,
    required this.idempotencyKey,
    this.maxSlippageBps = pantaDefaultSlippageBps,
  });
  final String callId;
  final String wallet;
  final String amountBaseUnits;
  final String idempotencyKey;
  final int maxSlippageBps;

  Map<String, Object?> toJson() {
    _expect(callId.isNotEmpty && callId.length <= 128);
    validatePantaWallet(wallet);
    final units = _baseUnits({'amount': amountBaseUnits}, 'amount');
    _expect(
      BigInt.parse(units) > BigInt.zero &&
          BigInt.parse(units) <= PantaUsdcAmount.maxBaseUnits,
    );
    _uuid(idempotencyKey);
    _expect(maxSlippageBps == pantaDefaultSlippageBps);
    return {
      'callId': callId,
      'wallet': wallet,
      'amountBaseUnits': amountBaseUnits,
      'idempotencyKey': idempotencyKey,
      'maxSlippageBps': maxSlippageBps,
    };
  }
}

/// Identical fields to prediction/PredictionVenue.ts UnsignedTransaction.
class PantaUnsignedTransaction {
  const PantaUnsignedTransaction({
    required this.payload,
    required this.expiresAt,
  });
  final String payload;
  final int expiresAt;
  String get venue => 'panta';
  String get encoding => 'solana-tx-base64';
  bool get demo => false;

  factory PantaUnsignedTransaction.fromJson(Object? value) {
    final json = _object(value);
    _panta(json, executable: true);
    _expect(json['encoding'] == 'solana-tx-base64');
    final payload = _string(json, 'payload');
    decodePantaTransaction(payload);
    return PantaUnsignedTransaction(
      payload: payload,
      expiresAt: _timestamp(json, 'expiresAt'),
    );
  }

  Uint8List get bytes => decodePantaTransaction(payload);

  Map<String, Object?> toJson() => {
    'venue': venue,
    'encoding': encoding,
    'payload': payload,
    'expiresAt': expiresAt,
    'demo': demo,
  };
}

/// Identical fields to prediction/PredictionVenue.ts UnsignedOrder.
class PantaUnsignedOrder {
  const PantaUnsignedOrder({
    required this.orderId,
    required this.venueMarketId,
    required this.owner,
    required this.side,
    required this.amountBaseUnits,
    required this.quotedProbability,
    required this.transaction,
    required this.idempotencyKey,
    required this.createdAt,
    required this.expiresAt,
  });
  final String orderId;
  final String venueMarketId;
  final String owner;
  final Side side;
  final String amountBaseUnits;

  /// Legacy canonical field. Never used to display Panta share prices.
  final num? quotedProbability;
  final PantaUnsignedTransaction transaction;
  final String idempotencyKey;
  final int createdAt;
  final int expiresAt;
  String get venue => 'panta';
  bool get demo => false;
  PantaFundingState get fundingState => PantaFundingState.quoted;

  factory PantaUnsignedOrder.fromJson(Object? value) {
    final json = _object(value);
    _panta(json, executable: true);
    _expect(json['fundingState'] == 'QUOTED');
    final probability = json['quotedProbability'];
    _expect(
      json.containsKey('quotedProbability') &&
          (probability == null ||
              (probability is num &&
                  probability.isFinite &&
                  probability >= 0 &&
                  probability <= 1)),
    );
    final transaction = PantaUnsignedTransaction.fromJson(json['transaction']);
    final owner = _string(json, 'owner');
    validatePantaWallet(owner);
    final key = _string(json, 'idempotencyKey');
    _uuid(key);
    final createdAt = _timestamp(json, 'createdAt');
    final expiresAt = _timestamp(json, 'expiresAt');
    _expect(expiresAt > createdAt && transaction.expiresAt > createdAt);
    final amount = _baseUnits(json, 'amountBaseUnits');
    _expect(BigInt.parse(amount) > BigInt.zero);
    return PantaUnsignedOrder(
      orderId: _string(json, 'orderId'),
      venueMarketId: _string(json, 'venueMarketId'),
      owner: owner,
      side: _side(json['side']),
      amountBaseUnits: amount,
      quotedProbability: probability as num?,
      transaction: transaction,
      idempotencyKey: key,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  bool isExpiredAt(DateTime now) =>
      now.millisecondsSinceEpoch >= expiresAt ||
      now.millisecondsSinceEpoch >= transaction.expiresAt;

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'venue': venue,
    'venueMarketId': venueMarketId,
    'owner': owner,
    'side': side.wire,
    'amountBaseUnits': amountBaseUnits,
    'quotedProbability': quotedProbability,
    'fundingState': fundingState.wire,
    'transaction': transaction.toJson(),
    'idempotencyKey': idempotencyKey,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'demo': demo,
  };
}

class PantaOrderReview {
  const PantaOrderReview({
    required this.amountUsdc,
    required this.amountBaseUnits,
    required this.expectedShares,
    required this.avgPrice,
    required this.feeUsdc,
    required this.maxSlippageBps,
  });
  final String amountUsdc;
  final String amountBaseUnits;
  final String expectedShares;

  /// Independent decimal USDC/share; values above 1 are valid.
  final String avgPrice;
  final String feeUsdc;
  final int maxSlippageBps;
  String get attribution => pantaAttribution;

  factory PantaOrderReview.fromJson(Object? value) {
    final json = _object(value);
    _expect(
      json['attribution'] == pantaAttribution &&
          json['maxSlippageBps'] == pantaDefaultSlippageBps,
    );
    final amount = _decimal(json, 'amountUsdc', positive: true);
    final units = _baseUnits(json, 'amountBaseUnits');
    try {
      _expect(PantaUsdcAmount.parse(amount).baseUnits == units);
    } catch (_) {
      _invalid();
    }
    return PantaOrderReview(
      amountUsdc: amount,
      amountBaseUnits: units,
      expectedShares: _decimal(json, 'expectedShares', positive: true),
      avgPrice: _decimal(json, 'avgPrice', positive: true),
      feeUsdc: _decimal(json, 'feeUsdc'),
      maxSlippageBps: pantaDefaultSlippageBps,
    );
  }

  Map<String, Object?> toJson() => {
    'amountUsdc': amountUsdc,
    'amountBaseUnits': amountBaseUnits,
    'expectedShares': expectedShares,
    'avgPrice': avgPrice,
    'feeUsdc': feeUsdc,
    'maxSlippageBps': maxSlippageBps,
    'attribution': attribution,
  };
}

class PantaPreparedTrade {
  const PantaPreparedTrade({required this.order, required this.review});
  final PantaUnsignedOrder order;
  final PantaOrderReview review;

  factory PantaPreparedTrade.fromJson(Object? value) {
    final json = _object(value);
    final order = PantaUnsignedOrder.fromJson(json['order']);
    final review = PantaOrderReview.fromJson(json['review']);
    _expect(order.amountBaseUnits == review.amountBaseUnits);
    return PantaPreparedTrade(order: order, review: review);
  }

  Map<String, Object?> toJson() => {
    'order': order.toJson(),
    'review': review.toJson(),
  };
}

/// Identical fields to prediction/PredictionVenue.ts VenueOrder.
class PantaVenueOrder {
  const PantaVenueOrder({
    required this.orderId,
    required this.venueOrderId,
    required this.venueMarketId,
    required this.owner,
    required this.side,
    required this.amountBaseUnits,
    required this.filledBaseUnits,
    required this.fundingState,
    required this.fillTxSignature,
    required this.createdAt,
    required this.updatedAt,
    required this.idempotencyKey,
  });
  final String orderId;
  final String? venueOrderId;
  final String venueMarketId;
  final String owner;
  final Side side;
  final String amountBaseUnits;
  final String filledBaseUnits;
  final PantaFundingState fundingState;
  final String? fillTxSignature;
  final int createdAt;
  final int updatedAt;
  final String? idempotencyKey;
  String get venue => 'panta';
  bool get demo => false;
  bool get isFunded => fundingState == PantaFundingState.filled;

  factory PantaVenueOrder.fromJson(Object? value) {
    final json = _object(value);
    _panta(json, executable: true);
    final owner = _string(json, 'owner');
    validatePantaWallet(owner);
    final state = PantaFundingState.fromWire(json['fundingState']);
    final amount = _baseUnits(json, 'amountBaseUnits');
    final filled = _baseUnits(json, 'filledBaseUnits');
    _expect(BigInt.parse(amount) > BigInt.zero);
    final signature = _nullableString(json, 'fillTxSignature');
    if (signature != null) _base58Length(signature, 64);
    if (state == PantaFundingState.filled) {
      _expect(
        signature != null && BigInt.parse(filled) >= BigInt.parse(amount),
      );
    } else if (state == PantaFundingState.partial) {
      _expect(
        BigInt.parse(filled) > BigInt.zero &&
            BigInt.parse(filled) < BigInt.parse(amount),
      );
    } else if (state == PantaFundingState.quoted ||
        state == PantaFundingState.submitted ||
        state == PantaFundingState.none) {
      _expect(filled == '0' && signature == null);
    }
    final key = _nullableString(json, 'idempotencyKey');
    if (key != null) _uuid(key);
    final createdAt = _timestamp(json, 'createdAt');
    final updatedAt = _timestamp(json, 'updatedAt');
    _expect(updatedAt >= createdAt);
    return PantaVenueOrder(
      orderId: _string(json, 'orderId'),
      venueOrderId: _nullableString(json, 'venueOrderId'),
      venueMarketId: _string(json, 'venueMarketId'),
      owner: owner,
      side: _side(json['side']),
      amountBaseUnits: amount,
      filledBaseUnits: filled,
      fundingState: state,
      fillTxSignature: signature,
      createdAt: createdAt,
      updatedAt: updatedAt,
      idempotencyKey: key,
    );
  }

  Map<String, Object?> toJson() => {
    'orderId': orderId,
    'venueOrderId': venueOrderId,
    'venue': venue,
    'venueMarketId': venueMarketId,
    'owner': owner,
    'side': side.wire,
    'amountBaseUnits': amountBaseUnits,
    'filledBaseUnits': filledBaseUnits,
    'fundingState': fundingState.wire,
    'fillTxSignature': fillTxSignature,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'idempotencyKey': idempotencyKey,
    'demo': demo,
  };
}

class PantaForCallResult {
  const PantaForCallResult({required this.order});
  final PantaVenueOrder? order;

  factory PantaForCallResult.fromJson(Object? value) {
    final json = _object(value);
    _expect(json.containsKey('order'));
    return PantaForCallResult(
      order:
          json['order'] == null
              ? null
              : PantaVenueOrder.fromJson(json['order']),
    );
  }

  Map<String, Object?> toJson() => {'order': order?.toJson()};
}

Uint8List decodePantaTransaction(String payload) {
  try {
    _expect(
      payload.isNotEmpty &&
          payload.length <= 1644 &&
          RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(payload),
    );
    final bytes = base64Decode(payload);
    _expect(
      bytes.isNotEmpty &&
          bytes.length <= 1232 &&
          base64Encode(bytes) == payload,
    );
    return bytes;
  } catch (_) {
    return _invalid();
  }
}

void validatePantaWallet(String address) => _base58Length(address, 32);

Never _invalid() => throw const PantaException(PantaErrorCode.invalidResponse);
void _expect(bool condition) {
  if (!condition) _invalid();
}

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : _invalid();
String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty && value.length <= 4096
      ? value
      : _invalid();
}

String? _nullableString(Map<String, dynamic> json, String key) {
  _expect(json.containsKey(key));
  return json[key] == null ? null : _string(json, key);
}

int _timestamp(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is int && value >= 0 && value <= 8640000000000000
      ? value
      : _invalid();
}

String _baseUnits(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  _expect(
    value.length <= 20 &&
        RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value) &&
        BigInt.parse(value) <= BigInt.parse('18446744073709551615'),
  );
  return value;
}

String _decimal(
  Map<String, dynamic> json,
  String key, {
  bool positive = false,
}) {
  final value = _string(json, key);
  _expect(
    value.length <= 96 &&
        RegExp(r'^(0|[1-9][0-9]*)(?:\.[0-9]{1,36})?$').hasMatch(value),
  );
  if (positive) _expect(BigInt.parse(value.replaceAll('.', '')) > BigInt.zero);
  return value;
}

Side _side(Object? value) => switch (value) {
  'YES' => Side.yes,
  'NO' => Side.no,
  _ => _invalid(),
};
void _panta(Map<String, dynamic> json, {bool executable = false}) {
  _expect(json['venue'] == 'panta');
  if (executable) _expect(json['demo'] == false);
}

void _uuid(String value) => _expect(
  RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value),
);
void _base58Length(String value, int length) {
  try {
    final decoded = value.length <= 100 ? base58decode(value) : const <int>[];
    _expect(
      value.isNotEmpty &&
          value.length <= 100 &&
          decoded.length == length &&
          (length != 64 || decoded.any((byte) => byte != 0)),
    );
  } catch (_) {
    _invalid();
  }
}
