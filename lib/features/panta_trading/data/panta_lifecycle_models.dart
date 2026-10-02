/// Typed contracts for a funded Panta position after the buy: the owner's
/// positions, claims, and the order on a call. Mirrors the BFF's
/// `pantaTrading.positions / callOrder / claimPrepare / claimSubmit / claim`.
///
/// Every money figure arrives as integer USDC base units in a string and stays
/// a [BigInt]; prices and share counts are decimal strings. Nothing here is
/// rounded through a double before it reaches the screen. Anything that does
/// not match the contract is refused with fixed local copy, never shown.
library;

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;

import 'panta_trading_models.dart';

/// Panta's public market page. The authenticated API URL is never shown.
Uri pantaMarketUri(String venueMarketId) =>
    Uri.https('panta.market', '/market/$venueMarketId');

/// Where a funded position stands. Labels are the only copy for each state.
enum PantaPositionStatus {
  pending('pending', 'Order pending'),
  failed('failed', 'Order failed'),
  open('open', 'Open'),
  awaitingResult('awaiting_result', 'Awaiting result'),
  wonClaimable('won_claimable', 'Won · ready to claim'),
  won('won', 'Won'),
  claiming('claiming', 'Claiming'),
  claimed('claimed', 'Claimed'),
  lost('lost', 'Lost'),
  voided('void', 'Void');

  const PantaPositionStatus(this.wire, this.label);
  final String wire;
  final String label;

  static PantaPositionStatus fromWire(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: _invalid);

  bool get isSettled =>
      this == won ||
      this == wonClaimable ||
      this == claiming ||
      this == claimed ||
      this == lost ||
      this == voided;
  bool get needsRefresh => this == pending || this == claiming;
}

enum PantaClaimState {
  built('BUILT'),
  submitted('SUBMITTED'),
  confirmed('CONFIRMED'),
  failed('FAILED');

  const PantaClaimState(this.wire);
  final String wire;
  static PantaClaimState fromWire(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: _invalid);
}

class PantaPositionClaim {
  const PantaPositionClaim({
    required this.claimId,
    required this.state,
    required this.signature,
    required this.payoutBaseUnits,
  });
  final String claimId;
  final PantaClaimState state;
  final String? signature;
  final BigInt? payoutBaseUnits;

  factory PantaPositionClaim.fromJson(Object? value) {
    final json = _object(value);
    final state = PantaClaimState.fromWire(json['state']);
    _expect(state != PantaClaimState.built);
    return PantaPositionClaim(
      claimId: _uuid(_string(json, 'claimId')),
      state: state,
      signature: _nullableString(json, 'signature'),
      payoutBaseUnits: _nullableBaseUnits(json, 'payoutBaseUnits'),
    );
  }
}

class PantaPosition {
  const PantaPosition({
    required this.orderId,
    required this.callId,
    required this.marketId,
    required this.venueMarketId,
    required this.question,
    required this.side,
    required this.owner,
    required this.status,
    required this.costBaseUnits,
    required this.shares,
    required this.entryPrice,
    required this.currentPrice,
    required this.priceObservedAt,
    required this.valueBaseUnits,
    required this.pnlBaseUnits,
    required this.walletShares,
    required this.claim,
    required this.submittedAt,
    required this.filledAt,
  });
  final String orderId;
  final String callId;
  final String marketId;
  final String venueMarketId;
  final String? question;
  final Side side;
  final String owner;
  final PantaPositionStatus status;
  final BigInt costBaseUnits;
  final String? shares;
  final String? entryPrice;
  final String? currentPrice;
  final int? priceObservedAt;
  final BigInt? valueBaseUnits;
  final BigInt? pnlBaseUnits;
  final String? walletShares;
  final PantaPositionClaim? claim;
  final int submittedAt;
  final int? filledAt;

  /// Built from the venue id; the server's own link is never trusted as text.
  Uri get pantaUrl => pantaMarketUri(venueMarketId);

  factory PantaPosition.fromJson(Object? value) {
    final json = _object(value);
    final owner = _string(json, 'owner');
    validatePantaWallet(owner);
    final venueMarketId = _string(json, 'venueMarketId');
    validatePantaWallet(venueMarketId);
    final status = PantaPositionStatus.fromWire(json['status']);
    final value_ = _nullableSignedBaseUnits(json, 'valueBaseUnits');
    final pnl = _nullableSignedBaseUnits(json, 'pnlBaseUnits');
    _expect((value_ == null) == (pnl == null));
    _expect(value_ == null || value_ >= BigInt.zero);
    final url = json['pantaUrl'];
    _expect(url == null || url == pantaMarketUri(venueMarketId).toString());
    return PantaPosition(
      orderId: _string(json, 'orderId'),
      callId: _uuid(_string(json, 'callId')),
      marketId: _string(json, 'marketId'),
      venueMarketId: venueMarketId,
      question: _nullableString(json, 'question'),
      side: switch (json['side']) {
        'YES' => Side.yes,
        'NO' => Side.no,
        _ => _invalid(),
      },
      owner: owner,
      status: status,
      costBaseUnits: _baseUnits(json, 'costBaseUnits'),
      shares: _nullableDecimal(json, 'shares'),
      entryPrice: _nullableDecimal(json, 'entryPrice'),
      currentPrice: _nullableDecimal(json, 'currentPrice'),
      priceObservedAt: _nullableTimestamp(json, 'priceObservedAt'),
      valueBaseUnits: value_,
      pnlBaseUnits: pnl,
      walletShares: _nullableDecimal(json, 'walletShares'),
      claim:
          json['claim'] == null
              ? null
              : PantaPositionClaim.fromJson(json['claim']),
      submittedAt: _timestamp(json, 'submittedAt'),
      filledAt: _nullableTimestamp(json, 'filledAt'),
    );
  }
}

enum PantaHoldingsState { live, unavailable, none }

class PantaPositionsPage {
  const PantaPositionsPage({
    required this.positions,
    required this.totalCost,
    required this.totalValue,
    required this.totalPnl,
    required this.counted,
    required this.holdings,
    required this.servedAt,
  });
  final List<PantaPosition> positions;
  final BigInt totalCost;
  final BigInt totalValue;
  final BigInt totalPnl;

  /// Positions whose value is known and included in the totals.
  final int counted;
  final PantaHoldingsState holdings;
  final int servedAt;

  /// Panta's public API has no sell; selling and managing happen on Panta.
  bool get sellSupported => false;

  bool get needsRefresh => positions.any((p) => p.status.needsRefresh);

  factory PantaPositionsPage.fromJson(Object? value) {
    final json = _object(value);
    _expect(json['attribution'] == pantaAttribution);
    final sell = _object(json['sell']);
    _expect(sell['supported'] == false);
    final totals = _object(json['totals']);
    final list = json['positions'];
    _expect(list is List && list.length <= 500);
    return PantaPositionsPage(
      positions: [
        for (final item in list as List) PantaPosition.fromJson(item),
      ],
      totalCost: _baseUnits(totals, 'costBaseUnits'),
      totalValue: _baseUnits(totals, 'valueBaseUnits'),
      totalPnl: _signedBaseUnits(totals, 'pnlBaseUnits'),
      counted: switch (totals['counted']) {
        final int n when n >= 0 => n,
        _ => _invalid(),
      },
      holdings: switch (json['holdings']) {
        'live' => PantaHoldingsState.live,
        'unavailable' => PantaHoldingsState.unavailable,
        'none' => PantaHoldingsState.none,
        _ => _invalid(),
      },
      servedAt: _timestamp(json, 'servedAt'),
    );
  }
}

class PantaClaimView {
  const PantaClaimView({
    required this.claimId,
    required this.orderId,
    required this.venueMarketId,
    required this.owner,
    required this.state,
    required this.signature,
    required this.payoutBaseUnits,
    required this.expiresAt,
  });
  final String claimId;
  final String orderId;
  final String venueMarketId;
  final String owner;
  final PantaClaimState state;
  final String? signature;
  final BigInt? payoutBaseUnits;
  final int? expiresAt;

  factory PantaClaimView.fromJson(Object? value) {
    final json = _object(value);
    _expect(json['attribution'] == pantaAttribution);
    final owner = _string(json, 'owner');
    validatePantaWallet(owner);
    final state = PantaClaimState.fromWire(json['state']);
    final payout = _nullableBaseUnits(json, 'payoutBaseUnits');
    _expect((state == PantaClaimState.confirmed) == (payout != null));
    return PantaClaimView(
      claimId: _uuid(_string(json, 'claimId')),
      orderId: _string(json, 'orderId'),
      venueMarketId: _string(json, 'venueMarketId'),
      owner: owner,
      state: state,
      signature: _nullableString(json, 'signature'),
      payoutBaseUnits: payout,
      expiresAt: _nullableTimestamp(json, 'expiresAt'),
    );
  }
}

class PantaClaimReview {
  const PantaClaimReview({
    required this.outcome,
    required this.winningShares,
    required this.estimatedPayoutUsdc,
  });
  final Side outcome;
  final String winningShares;

  /// Panta: a resolved winner is worth about 1 USDC per share. An estimate.
  final String estimatedPayoutUsdc;

  factory PantaClaimReview.fromJson(Object? value) {
    final json = _object(value);
    _expect(json['attribution'] == pantaAttribution);
    return PantaClaimReview(
      outcome: switch (json['outcome']) {
        'YES' => Side.yes,
        'NO' => Side.no,
        _ => _invalid(),
      },
      winningShares: _decimal(json, 'winningShares'),
      estimatedPayoutUsdc: _decimal(json, 'estimatedPayoutUsdc'),
    );
  }
}

class PantaClaimPrepared {
  const PantaClaimPrepared({
    required this.claim,
    required this.transaction,
    required this.review,
  });
  final PantaClaimView claim;

  /// Null when this position already has a claim in flight or settled.
  final PantaUnsignedTransaction? transaction;
  final PantaClaimReview? review;

  factory PantaClaimPrepared.fromJson(Object? value) {
    final json = _object(value);
    final claim = PantaClaimView.fromJson(json['claim']);
    final tx =
        json['transaction'] == null
            ? null
            : PantaUnsignedTransaction.fromJson(json['transaction']);
    final review =
        json['review'] == null
            ? null
            : PantaClaimReview.fromJson(json['review']);
    _expect((tx == null) == (review == null));
    _expect(tx == null || claim.state == PantaClaimState.built);
    return PantaClaimPrepared(claim: claim, transaction: tx, review: review);
  }
}

class PantaCallOrder {
  const PantaCallOrder({required this.order});
  final PantaVenueOrder? order;
  factory PantaCallOrder.fromJson(Object? value) {
    final json = _object(value);
    _expect(json.containsKey('order'));
    return PantaCallOrder(
      order:
          json['order'] == null
              ? null
              : PantaVenueOrder.fromJson(json['order']),
    );
  }
}

/// Exact display of USDC base units and decimal strings. No doubles.
abstract final class PantaMoney {
  static final _million = BigInt.from(1000000);

  /// `12.5 USDC`, `-3.25 USDC` (or `+3.25 USDC` with [signed]).
  static String usdc(BigInt baseUnits, {bool signed = false}) {
    final negative = baseUnits.isNegative;
    final abs = baseUnits.abs();
    final whole = abs ~/ _million;
    var fraction = (abs % _million).toString().padLeft(6, '0');
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    if (fraction.length < 2) fraction = fraction.padRight(2, '0');
    final sign = negative ? '-' : (signed && abs > BigInt.zero ? '+' : '');
    return '$sign${_group(whole.toString())}.$fraction USDC';
  }

  /// A USDC/share decimal, trimmed to at most 4 places: `0.52`, `1`.
  static String price(String decimal) => _trim(decimal, 4);

  /// A share count, trimmed to at most 4 places.
  static String shares(String decimal) => _trim(decimal, 4);

  static String _trim(String decimal, int places) {
    final parts = decimal.split('.');
    if (parts.length == 1) return parts.first;
    var fraction = parts[1];
    if (fraction.length > places) fraction = fraction.substring(0, places);
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? parts.first : '${parts.first}.$fraction';
  }

  static String _group(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

// ── strict parsing helpers (private to this contract) ─────────────────────

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

String? _nullableString(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _string(json, key);

String _uuid(String value) {
  _expect(
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value),
  );
  return value;
}

int _timestamp(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is int && value >= 0 && value <= 8640000000000000
      ? value
      : _invalid();
}

int? _nullableTimestamp(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _timestamp(json, key);

BigInt _baseUnits(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  _expect(value.length <= 20 && RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value));
  return BigInt.parse(value);
}

BigInt? _nullableBaseUnits(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _baseUnits(json, key);

BigInt _signedBaseUnits(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  _expect(value.length <= 21 && RegExp(r'^(0|-?[1-9][0-9]*)$').hasMatch(value));
  return BigInt.parse(value);
}

BigInt? _nullableSignedBaseUnits(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _signedBaseUnits(json, key);

String _decimal(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  _expect(
    value.length <= 64 &&
        RegExp(r'^(0|[1-9][0-9]*)(?:\.[0-9]{1,18})?$').hasMatch(value),
  );
  return value;
}

String? _nullableDecimal(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : _decimal(json, key);
