/// Wire models for the BFF's `marketCreation.*` procedures.
///
/// Parsing is strict about the fields a screen depends on and tolerant of
/// additions, so a newer server never breaks an installed app. Times are unix
/// milliseconds on the wire and UTC [DateTime]s here. Money stays in USDC base
/// units (6 decimals) as strings and is only formatted for display.
library;

/// Thrown when a response is missing something a screen depends on.
class MarketCreationFormatException implements Exception {
  const MarketCreationFormatException(this.what);
  final String what;
  @override
  String toString() => 'MarketCreationFormatException: $what';
}

Map<String, dynamic> _map(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw MarketCreationFormatException(what);
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw MarketCreationFormatException(key);
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw MarketCreationFormatException(key);
}

DateTime _time(Map<String, dynamic> json, String key) =>
    DateTime.fromMillisecondsSinceEpoch(_int(json, key), isUtc: true);

bool _bool(Map<String, dynamic> json, String key) => json[key] == true;

/// Panta's create allowlist, in the order the server lists it.
enum MarketCategory {
  sports('sports', 'Sports'),
  crypto('crypto', 'Crypto'),
  politics('politics', 'Politics'),
  entertainment('entertainment', 'Entertainment'),
  finance('finance', 'Finance'),
  science('science', 'Science'),
  world('world', 'World'),
  other('other', 'Other');

  const MarketCategory(this.wire, this.label);
  final String wire;
  final String label;

  static MarketCategory? fromWire(String? value) {
    for (final category in values) {
      if (category.wire == value) return category;
    }
    return null;
  }
}

enum ProposalStatus {
  pendingReview('pending_review', 'In review'),
  approved('approved', 'Approved'),
  rejected('rejected', 'Not approved'),
  withdrawn('withdrawn', 'Withdrawn'),
  publishing('publishing', 'Publishing'),
  live('live', 'Live'),
  expired('expired', 'Expired');

  const ProposalStatus(this.wire, this.label);
  final String wire;
  final String label;

  static ProposalStatus fromWire(String value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    throw MarketCreationFormatException('status $value');
  }

  bool get isFinal =>
      this == rejected || this == withdrawn || this == live || this == expired;
}

enum ReviewReason {
  unclear('unclear', 'The question or rules are unclear'),
  unverifiable('unverifiable', 'The result can’t be checked from the sources'),
  duplicate('duplicate', 'This market already exists'),
  notAllowed('not_allowed', 'This topic isn’t allowed'),
  other('other', 'Another reason');

  const ReviewReason(this.wire, this.label);
  final String wire;
  final String label;

  static ReviewReason? fromWire(String? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

/// What a person fills in. Outcomes are always YES / NO (Panta is binary).
class MarketDraft {
  const MarketDraft({
    required this.question,
    required this.category,
    required this.closesAt,
    required this.resolvesAt,
    required this.rules,
    required this.sources,
    this.description,
  });

  final String question;
  final MarketCategory category;

  /// Trading closes (Panta `endTime`).
  final DateTime closesAt;

  /// The result is known by (Panta `resolutionTime`).
  final DateTime resolvesAt;
  final String rules;
  final List<String> sources;
  final String? description;

  /// Trimmed the way the server stores it.
  MarketDraft normalized() {
    final text = description?.trim() ?? '';
    final seen = <String>{};
    return MarketDraft(
      question: question.trim().replaceAll(RegExp(r'\s+'), ' '),
      category: category,
      closesAt: closesAt,
      resolvesAt: resolvesAt,
      rules: rules.trim(),
      sources: [
        for (final source in sources.map((s) => s.trim()))
          if (source.isNotEmpty && seen.add(source)) source,
      ],
      description: text.isEmpty ? null : text,
    );
  }

  Map<String, Object?> toJson({required String idempotencyKey}) => {
    'question': question,
    'category': category.wire,
    'closesAt': closesAt.toUtc().millisecondsSinceEpoch,
    'resolvesAt': resolvesAt.toUtc().millisecondsSinceEpoch,
    'rules': rules,
    'sources': sources,
    'description': description,
    'idempotencyKey': idempotencyKey,
  };
}

class MarketProposer {
  const MarketProposer({
    required this.id,
    required this.handle,
    required this.displayName,
  });
  final String id;
  final String handle;
  final String displayName;

  static MarketProposer? maybeFromJson(Object? value) {
    if (value is! Map) return null;
    final json = _map(value, 'proposer');
    return MarketProposer(
      id: _string(json, 'id'),
      handle: _string(json, 'handle'),
      displayName: _optionalString(json, 'displayName') ?? '',
    );
  }

  String get atHandle => handle.startsWith('@') ? handle : '@$handle';
}

class ProposalReview {
  const ProposalReview({required this.decidedAt, this.reason, this.note});
  final DateTime decidedAt;
  final ReviewReason? reason;
  final String? note;
}

class LiveMarket {
  const LiveMarket({
    required this.venueMarketId,
    required this.marketId,
    required this.creatorWallet,
    required this.liveAt,
  });

  /// The Panta event address.
  final String venueMarketId;

  /// Our catalog id: open MarketDetailScreen with this.
  final String marketId;
  final String creatorWallet;
  final DateTime liveAt;
}

class MarketProposal {
  const MarketProposal({
    required this.id,
    required this.question,
    required this.category,
    required this.closesAt,
    required this.resolvesAt,
    required this.rules,
    required this.sources,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.publishDeadline,
    required this.proposer,
    required this.viewerIsProposer,
    required this.review,
    required this.canWithdraw,
    required this.canPublish,
    required this.publishingWallet,
    required this.live,
  });

  final String id;
  final String question;
  final String category;
  final DateTime closesAt;
  final DateTime resolvesAt;
  final String rules;
  final List<String> sources;
  final String? description;
  final ProposalStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// After this, trading closes too soon for Panta to accept the create.
  final DateTime publishDeadline;
  final MarketProposer? proposer;
  final bool viewerIsProposer;
  final ProposalReview? review;
  final bool canWithdraw;
  final bool canPublish;

  /// The wallet a submitted create was signed with, while publishing.
  final String? publishingWallet;
  final LiveMarket? live;

  String get categoryLabel =>
      MarketCategory.fromWire(category)?.label ?? category;

  factory MarketProposal.fromJson(Object? value) {
    final json = _map(value, 'proposal');
    final reviewJson = json['review'];
    final publish = json['publish'];
    final live = json['live'];
    return MarketProposal(
      id: _string(json, 'id'),
      question: _string(json, 'question'),
      category: _string(json, 'category'),
      closesAt: _time(json, 'closesAt'),
      resolvesAt: _time(json, 'resolvesAt'),
      rules: _string(json, 'rules'),
      sources: [
        for (final source in (json['sources'] as List? ?? const []))
          if (source is String) source,
      ],
      description: _optionalString(json, 'description'),
      status: ProposalStatus.fromWire(_string(json, 'status')),
      createdAt: _time(json, 'createdAt'),
      updatedAt: _time(json, 'updatedAt'),
      publishDeadline: _time(json, 'publishDeadline'),
      proposer: MarketProposer.maybeFromJson(json['proposer']),
      viewerIsProposer: _bool(json, 'viewerIsProposer'),
      review:
          reviewJson is Map
              ? ProposalReview(
                decidedAt: _time(_map(reviewJson, 'review'), 'decidedAt'),
                reason: ReviewReason.fromWire(
                  _optionalString(_map(reviewJson, 'review'), 'reason'),
                ),
                note: _optionalString(_map(reviewJson, 'review'), 'note'),
              )
              : null,
      canWithdraw: _bool(json, 'canWithdraw'),
      canPublish: _bool(json, 'canPublish'),
      publishingWallet:
          publish is Map
              ? _optionalString(_map(publish, 'publish'), 'wallet')
              : null,
      live:
          live is Map
              ? LiveMarket(
                venueMarketId: _string(_map(live, 'live'), 'venueMarketId'),
                marketId: _string(_map(live, 'live'), 'marketId'),
                creatorWallet: _string(_map(live, 'live'), 'creatorWallet'),
                liveAt: _time(_map(live, 'live'), 'liveAt'),
              )
              : null,
    );
  }
}

/// The paid create the wallet is about to approve.
class PublishReview {
  const PublishReview({
    required this.sessionId,
    required this.proposalId,
    required this.wallet,
    required this.eventAddress,
    required this.feeBaseUnits,
    required this.liquidityBaseUnits,
    required this.platformBaseUnits,
    required this.transaction,
    required this.expiresAt,
  });

  final String sessionId;
  final String proposalId;
  final String wallet;
  final String eventAddress;
  final String feeBaseUnits;
  final String liquidityBaseUnits;
  final String platformBaseUnits;

  /// Base64 unsigned transaction. Never logged.
  final String transaction;
  final DateTime expiresAt;

  factory PublishReview.fromJson(Object? value) {
    final json = _map(value, 'review');
    if (json['currency'] != 'USDC' || json['network'] != 'solana-mainnet') {
      throw const MarketCreationFormatException('currency or network');
    }
    final units = RegExp(r'^[0-9]{1,20}$');
    final review = PublishReview(
      sessionId: _string(json, 'sessionId'),
      proposalId: _string(json, 'proposalId'),
      wallet: _string(json, 'wallet'),
      eventAddress: _string(json, 'eventAddress'),
      feeBaseUnits: _string(json, 'feeBaseUnits'),
      liquidityBaseUnits: _string(json, 'liquidityBaseUnits'),
      platformBaseUnits: _string(json, 'platformBaseUnits'),
      transaction: _string(json, 'transaction'),
      expiresAt: _time(json, 'expiresAt'),
    );
    if (!units.hasMatch(review.feeBaseUnits) ||
        !units.hasMatch(review.liquidityBaseUnits) ||
        !units.hasMatch(review.platformBaseUnits) ||
        BigInt.parse(review.liquidityBaseUnits) +
                BigInt.parse(review.platformBaseUnits) !=
            BigInt.parse(review.feeBaseUnits)) {
      throw const MarketCreationFormatException('fee');
    }
    return review;
  }
}

/// Server rules, so the form validates against the same numbers.
class MarketCreationRules {
  const MarketCreationRules({
    this.questionMin = 10,
    this.questionMax = 512,
    this.rulesMin = 20,
    this.rulesMax = 2048,
    this.descriptionMax = 1000,
    this.sourcesMax = 20,
    this.sourceUrlMax = 512,
    this.proposeMinLead = const Duration(hours: 3),
    this.publishMinLead = const Duration(hours: 2),
    this.maxHorizon = const Duration(days: 730),
    this.maxResolutionGap = const Duration(days: 90),
  });

  final int questionMin;
  final int questionMax;
  final int rulesMin;
  final int rulesMax;
  final int descriptionMax;
  final int sourcesMax;
  final int sourceUrlMax;
  final Duration proposeMinLead;
  final Duration publishMinLead;
  final Duration maxHorizon;
  final Duration maxResolutionGap;

  factory MarketCreationRules.fromJson(Object? value) {
    final json = _map(value, 'rules');
    Duration ms(String key) => Duration(milliseconds: _int(json, key));
    return MarketCreationRules(
      questionMin: _int(json, 'questionMin'),
      questionMax: _int(json, 'questionMax'),
      rulesMin: _int(json, 'rulesMin'),
      rulesMax: _int(json, 'rulesMax'),
      descriptionMax: _int(json, 'descriptionMax'),
      sourcesMax: _int(json, 'sourcesMax'),
      sourceUrlMax: _int(json, 'sourceUrlMax'),
      proposeMinLead: ms('proposeMinLeadMs'),
      publishMinLead: ms('publishMinLeadMs'),
      maxHorizon: ms('maxHorizonMs'),
      maxResolutionGap: ms('maxResolutionGapMs'),
    );
  }
}

class MarketCreationStatus {
  const MarketCreationStatus({
    required this.proposalsEnabled,
    required this.publishingEnabled,
    required this.reason,
    required this.viewerIsReviewer,
    required this.maxFeeBaseUnits,
    required this.rules,
  });

  final bool proposalsEnabled;
  final bool publishingEnabled;
  final String? reason;
  final bool viewerIsReviewer;
  final String maxFeeBaseUnits;
  final MarketCreationRules rules;

  factory MarketCreationStatus.fromJson(Object? value) {
    final json = _map(value, 'status');
    return MarketCreationStatus(
      proposalsEnabled: _bool(json, 'proposalsEnabled'),
      publishingEnabled: _bool(json, 'publishingEnabled'),
      reason: _optionalString(json, 'reason'),
      viewerIsReviewer: _bool(json, 'viewerIsReviewer'),
      maxFeeBaseUnits: _optionalString(json, 'maxFeeBaseUnits') ?? '0',
      rules: MarketCreationRules.fromJson(json['rules']),
    );
  }
}

class ReviewQueue {
  const ReviewQueue({required this.pending, required this.approved});
  final List<MarketProposal> pending;

  /// Approved or publishing: waiting for a wallet to pay for the create.
  final List<MarketProposal> approved;

  factory ReviewQueue.fromJson(Object? value) {
    final json = _map(value, 'queue');
    List<MarketProposal> list(String key) => [
      for (final row in (json[key] as List? ?? const []))
        MarketProposal.fromJson(row),
    ];
    return ReviewQueue(pending: list('pending'), approved: list('approved'));
  }
}

/// "12.50" from USDC base units, without floating point.
String formatUsdcBaseUnits(String baseUnits) {
  final value = BigInt.tryParse(baseUnits) ?? BigInt.zero;
  final whole = value ~/ BigInt.from(1000000);
  final cents = (value % BigInt.from(1000000)) ~/ BigInt.from(10000);
  return '$whole.${cents.toString().padLeft(2, '0')}';
}
