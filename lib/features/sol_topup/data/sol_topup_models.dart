/// Wire models for the BFF's `solTopUp.*` procedures (gasless USDC -> SOL).
///
/// Strict about what matters — addresses, integer base units and lamports,
/// the router, who pays the fee — and tolerant of fields added later. A
/// malformed answer is an error, never a guessed default.
library;

import 'package:chumbucket/features/deposits/data/deposits_models.dart'
    show formatBaseUnits, usdcDecimals;

import '../domain/gasless_swap_check.dart' show SwapRouter;

enum TopUpErrorKind {
  signedOut,
  unavailable,
  notYours,
  needsUsdc,
  enoughSol,
  belowGaslessMinimum,
  notGasless,
  rejected,
  expired,
  rateLimited,
  provider,
  connection,
  invalidResponse,
}

class TopUpException implements Exception {
  const TopUpException(this.kind, [this.serverMessage]);
  final TopUpErrorKind kind;

  /// The BFF's own copy (never Jupiter's), when it sent one.
  final String? serverMessage;

  String get message =>
      serverMessage ??
      switch (kind) {
        TopUpErrorKind.signedOut => 'Sign in to swap for SOL.',
        TopUpErrorKind.unavailable =>
          'Swapping USDC for SOL isn’t available right now.',
        TopUpErrorKind.notYours =>
          'That wallet isn’t connected to your account.',
        TopUpErrorKind.needsUsdc =>
          'This wallet doesn’t have enough USDC. Add funds first.',
        TopUpErrorKind.enoughSol =>
          'This wallet already has SOL for network fees.',
        TopUpErrorKind.belowGaslessMinimum =>
          'Jupiter only pays the network fee on bigger swaps right now.',
        TopUpErrorKind.notGasless =>
          'Jupiter can’t cover the network fee for this swap right now.',
        TopUpErrorKind.rejected =>
          'The swap didn’t pass our checks. Nothing was signed.',
        TopUpErrorKind.expired =>
          'This quote expired. Get a fresh one. Nothing was sent.',
        TopUpErrorKind.rateLimited =>
          'That’s a lot of tries in a minute. Give it a moment.',
        TopUpErrorKind.provider =>
          'We couldn’t reach Jupiter just now. Nothing was signed.',
        TopUpErrorKind.connection =>
          'You’re offline or the connection dropped. Try again.',
        TopUpErrorKind.invalidResponse =>
          'Something didn’t look right. Nothing was signed. Try again.',
      };

  @override
  String toString() => 'TopUpException(${kind.name})';
}

Never _bad() => throw const TopUpException(TopUpErrorKind.invalidResponse);
T _as<T>(Object? value) => value is T ? value : _bad();

final _base58 = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
final _integer = RegExp(r'^[0-9]{1,20}$');
final _base64 = RegExp(
  r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
);

String _address(Object? value) {
  final s = _as<String>(value);
  if (!_base58.hasMatch(s)) _bad();
  return s;
}

BigInt _units(Object? value) {
  final s = _as<String>(value);
  if (!_integer.hasMatch(s)) _bad();
  return BigInt.parse(s);
}

const lamportsDecimals = 9;

/// "0.0085": SOL to four decimals, never rounded up.
String solLabel(BigInt lamports) =>
    formatBaseUnits(lamports, lamportsDecimals, maxDecimals: 4, minDecimals: 2);

/// "1.00": USDC to cents, never rounded up.
String usdcLabel(BigInt baseUnits) => formatBaseUnits(baseUnits, usdcDecimals);

class TopUpStatus {
  const TopUpStatus({
    required this.available,
    required this.reasonMessage,
    required this.minBaseUnits,
    required this.maxBaseUnits,
  });
  final bool available;
  final String? reasonMessage;
  final BigInt? minBaseUnits;
  final BigInt? maxBaseUnits;

  factory TopUpStatus.fromJson(Map<String, dynamic> json) {
    if (json['network'] != 'solana-mainnet') _bad();
    final reason = json['reason'];
    final limits = json['limits'];
    return TopUpStatus(
      available: _as<bool>(json['available']),
      reasonMessage:
          reason is Map && reason['message'] is String
              ? reason['message'] as String
              : null,
      minBaseUnits: limits is Map ? _units(limits['minBaseUnits']) : null,
      maxBaseUnits: limits is Map ? _units(limits['maxBaseUnits']) : null,
    );
  }
}

class TopUpSuggestion {
  const TopUpSuggestion({
    required this.amountBaseUnits,
    required this.estimatedLamports,
    required this.tradesCovered,
  });
  final BigInt amountBaseUnits;
  final BigInt estimatedLamports;
  final int tradesCovered;
}

class TopUpPlan {
  const TopUpPlan({
    required this.wallet,
    required this.lamports,
    required this.usdcBaseUnits,
    required this.perTradeLamports,
    required this.floorLamports,
    required this.tradesCoveredNow,
    required this.needsSol,
    required this.blocker,
    required this.suggestion,
    required this.minBaseUnits,
    required this.maxBaseUnits,
  });

  final String wallet;
  final BigInt lamports;
  final BigInt usdcBaseUnits;
  final BigInt perTradeLamports;
  final BigInt floorLamports;
  final int tradesCoveredNow;

  /// Not enough SOL for even one new Panta position.
  final bool needsSol;

  /// `ENOUGH_SOL` | `NEEDS_USDC` | null.
  final String? blocker;
  final TopUpSuggestion? suggestion;
  final BigInt minBaseUnits;
  final BigInt maxBaseUnits;

  factory TopUpPlan.fromJson(Map<String, dynamic> json) {
    if (json['network'] != 'solana-mainnet') _bad();
    final s = json['suggestion'];
    final limits = _as<Map<String, dynamic>>(json['limits']);
    final blocker = json['blocker'];
    if (blocker != null && blocker != 'ENOUGH_SOL' && blocker != 'NEEDS_USDC') {
      _bad();
    }
    return TopUpPlan(
      wallet: _address(json['wallet']),
      lamports: _units(json['lamports']),
      usdcBaseUnits: _units(json['usdcBaseUnits']),
      perTradeLamports: _units(json['perTradeLamports']),
      floorLamports: _units(json['floorLamports']),
      tradesCoveredNow: _as<num>(json['tradesCoveredNow']).toInt(),
      needsSol: _as<bool>(json['needsSol']),
      blocker: blocker as String?,
      suggestion:
          s == null
              ? null
              : TopUpSuggestion(
                amountBaseUnits: _units(_as<Map>(s)['amountBaseUnits']),
                estimatedLamports: _units(s['estimatedLamports']),
                tradesCovered: _as<num>(s['tradesCovered']).toInt(),
              ),
      minBaseUnits: _units(limits['minBaseUnits']),
      maxBaseUnits: _units(limits['maxBaseUnits']),
    );
  }
}

class TopUpReview {
  const TopUpReview({
    required this.wallet,
    required this.usdcInBaseUnits,
    required this.solOutLamports,
    required this.solOutMinLamports,
    required this.feeBps,
    required this.router,
    required this.paidByJupiter,
    required this.feePayer,
    required this.tradesCovered,
  });

  final String wallet;
  final BigInt usdcInBaseUnits;
  final BigInt solOutLamports;
  final BigInt solOutMinLamports;
  final int feeBps;
  final SwapRouter router;

  /// True: Jupiter pays the network fee. False: the quoting market maker does.
  final bool paidByJupiter;
  final String feePayer;
  final int tradesCovered;

  factory TopUpReview.fromJson(Map<String, dynamic> json) {
    final router = SwapRouter.parse(json['router']) ?? _bad();
    final paidBy = json['networkFeePaidBy'];
    if (paidBy != 'jupiter' && paidBy != 'market_maker') _bad();
    if ((router == SwapRouter.metis) != (paidBy == 'jupiter')) _bad();
    final feeBps = _as<num>(json['feeBps']).toInt();
    if (feeBps < 0 || feeBps > 10000) _bad();
    return TopUpReview(
      wallet: _address(json['wallet']),
      usdcInBaseUnits: _units(json['usdcInBaseUnits']),
      solOutLamports: _units(json['solOutLamports']),
      solOutMinLamports: _units(json['solOutMinLamports']),
      feeBps: feeBps,
      router: router,
      paidByJupiter: paidBy == 'jupiter',
      feePayer: _address(json['feePayer']),
      tradesCovered: _as<num>(json['tradesCovered']).toInt(),
    );
  }
}

class TopUpOrder {
  const TopUpOrder({
    required this.requestId,
    required this.transaction,
    required this.expiresAt,
    required this.review,
  });
  final String requestId;

  /// Base64 unsigned transaction. Never logged.
  final String transaction;
  final DateTime expiresAt;
  final TopUpReview review;

  factory TopUpOrder.fromJson(Map<String, dynamic> json) {
    final requestId = _as<String>(json['requestId']);
    if (!RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(requestId)) _bad();
    final transaction = _as<String>(json['transaction']);
    if (transaction.isEmpty ||
        transaction.length > 1644 ||
        !_base64.hasMatch(transaction)) {
      _bad();
    }
    return TopUpOrder(
      requestId: requestId,
      transaction: transaction,
      expiresAt: DateTime.tryParse(_as<String>(json['expiresAt'])) ?? _bad(),
      review: TopUpReview.fromJson(_as<Map<String, dynamic>>(json['review'])),
    );
  }
}

enum TopUpOutcome { success, failed, unknown }

class TopUpResult {
  const TopUpResult({
    required this.outcome,
    this.signature,
    this.solReceivedLamports,
    this.message,
  });
  final TopUpOutcome outcome;
  final String? signature;
  final BigInt? solReceivedLamports;
  final String? message;

  Uri? get explorerUri =>
      signature == null
          ? null
          : Uri.https('explorer.solana.com', '/tx/$signature');

  factory TopUpResult.fromJson(Map<String, dynamic> json) {
    switch (json['status']) {
      case 'SUCCESS':
        final signature = _as<String>(json['signature']);
        if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,100}$').hasMatch(signature)) {
          _bad();
        }
        final sol = json['solReceivedLamports'];
        return TopUpResult(
          outcome: TopUpOutcome.success,
          signature: signature,
          solReceivedLamports: sol == null ? null : _units(sol),
        );
      case 'FAILED':
        return TopUpResult(
          outcome: TopUpOutcome.failed,
          message: _as<String>(json['message']),
        );
      case 'UNKNOWN':
        return TopUpResult(
          outcome: TopUpOutcome.unknown,
          message: _as<String>(json['message']),
        );
      default:
        _bad();
    }
  }
}
