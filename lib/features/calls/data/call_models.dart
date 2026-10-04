/// Dart mirror of the FROZEN pivot vocabulary — `docs/contracts/pivot-contracts-v1.md` §3.
///
/// Rules this file exists to enforce, mechanically:
///
/// * Field names are **identical** to the TypeScript in the contract. If a name
///   here drifts from the contract, the wire breaks silently — so every model
///   round-trips through [toJson]/`fromJson` and the tests assert the keys.
/// * Every timestamp is **unix milliseconds, integer, UTC**. Never a
///   `DateTime` on the wire; `DateTime` accessors are provided for display only.
/// * Every probability is a `double` in `[0,1]`. Out-of-range input is a
///   [FormatException], not a clamp — a schema change must fail loudly rather
///   than silently corrupt a call or a receipt (contract §4).
/// * Money is an **integer base-unit string**, never a double. The MVP's free
///   call carries no amount at all, so no money field exists below; if one is
///   ever added it is a `String` and it is never shown on a receipt.
library;

/// Thrown when a wire value is not a member of a FROZEN enum.
///
/// Deliberately loud: contract §4 forbids silently coercing an unknown venue
/// value into a known one.
class CallVocabularyException implements Exception {
  final String message;
  const CallVocabularyException(this.message);
  @override
  String toString() => 'CallVocabularyException: $message';
}

Never _unknown(String type, Object? value) =>
    throw CallVocabularyException('Unknown $type: "$value"');

/// `type Side = 'YES' | 'NO'`
enum Side {
  yes('YES', 'Yes'),
  no('NO', 'No');

  const Side(this.wire, this.label);

  /// The exact JSON value. Never lower-cased on the wire.
  final String wire;

  /// Human label. Newcomers never see the raw code.
  final String label;

  Side get opposite => this == Side.yes ? Side.no : Side.yes;

  static Side fromWire(Object? value) => switch (value) {
    'YES' => Side.yes,
    'NO' => Side.no,
    _ => _unknown('Side', value),
  };
}

/// `type Resolution = 'YES' | 'NO' | 'VOID'`
///
/// `VOID` is cancelled/abandoned. It is **never** a win and **never** a loss.
enum Resolution {
  yes('YES'),
  no('NO'),
  // `void` is a Dart keyword; the wire value is still exactly 'VOID'.
  voided('VOID');

  const Resolution(this.wire);
  final String wire;

  /// The [Side] this resolution settles in favour of, or null for `VOID`.
  Side? get side => switch (this) {
    Resolution.yes => Side.yes,
    Resolution.no => Side.no,
    Resolution.voided => null,
  };

  static Resolution fromWire(Object? value) => switch (value) {
    'YES' => Resolution.yes,
    'NO' => Resolution.no,
    'VOID' => Resolution.voided,
    _ => _unknown('Resolution', value),
  };
}

/// `type MarketStatus`.
///
/// **Never collapse these.** `CLOSED_PENDING_RESOLUTION`, `CANCELLED` and
/// `RESOLVED` are three different things and the UI renders each differently.
enum MarketStatus {
  open('OPEN', 'Open'),
  closedPendingResolution(
    'CLOSED_PENDING_RESOLUTION',
    'Closed · awaiting result',
  ),
  resolved('RESOLVED', 'Resolved'),
  cancelled('CANCELLED', 'Void · cancelled by venue'),
  paused('PAUSED', 'Paused by venue');

  const MarketStatus(this.wire, this.label);
  final String wire;

  /// Distinct, non-confusable copy for each state.
  final String label;

  bool get acceptsNewCalls => this == MarketStatus.open;

  /// A cancelled market is VOID — never a win or a loss.
  bool get isVoid => this == MarketStatus.cancelled;

  static MarketStatus fromWire(Object? value) => switch (value) {
    'OPEN' => MarketStatus.open,
    'CLOSED_PENDING_RESOLUTION' => MarketStatus.closedPendingResolution,
    'RESOLVED' => MarketStatus.resolved,
    'CANCELLED' => MarketStatus.cancelled,
    'PAUSED' => MarketStatus.paused,
    _ => _unknown('MarketStatus', value),
  };
}

/// `type CallOutcome = 'PENDING' | 'CORRECT' | 'INCORRECT' | 'VOID'`
enum CallOutcome {
  pending('PENDING', 'Pending'),
  correct('CORRECT', 'Correct'),
  incorrect('INCORRECT', 'Incorrect'),
  voided('VOID', 'Void');

  const CallOutcome(this.wire, this.label);
  final String wire;
  final String label;

  bool get isSettled => this != CallOutcome.pending;

  static CallOutcome fromWire(Object? value) => switch (value) {
    'PENDING' => CallOutcome.pending,
    'CORRECT' => CallOutcome.correct,
    'INCORRECT' => CallOutcome.incorrect,
    'VOID' => CallOutcome.voided,
    _ => _unknown('CallOutcome', value),
  };
}

/// `type FundingState`.
///
/// **`FILLED` is the only state whose label may read "Funded".** A tap, a
/// signature and a submitted transaction are all `SUBMITTED`. [label] is the
/// single source of that copy so it cannot drift per-screen.
enum FundingState {
  none('NONE', 'Free call'),
  quoted('QUOTED', 'Quote shown · nothing signed'),
  submitted('SUBMITTED', 'Submitted · not funded yet'),
  filled('FILLED', 'Funded'),
  partial('PARTIAL', 'Partially filled'),
  failed('FAILED', 'Failed'),
  closed('CLOSED', 'Position closed'),
  claimable('CLAIMABLE', 'Claimable'),
  claimed('CLAIMED', 'Claimed');

  const FundingState(this.wire, this.label);
  final String wire;
  final String label;

  /// The one and only place the app may conclude that money is actually in.
  bool get isFunded => this == FundingState.filled;

  /// A free call — the default, and the only state the MVP ships.
  bool get isFree => this == FundingState.none;

  static FundingState fromWire(Object? value) => switch (value) {
    'NONE' => FundingState.none,
    'QUOTED' => FundingState.quoted,
    'SUBMITTED' => FundingState.submitted,
    'FILLED' => FundingState.filled,
    'PARTIAL' => FundingState.partial,
    'FAILED' => FundingState.failed,
    'CLOSED' => FundingState.closed,
    'CLAIMABLE' => FundingState.claimable,
    'CLAIMED' => FundingState.claimed,
    _ => _unknown('FundingState', value),
  };
}

/// Must match the backend's VenueId. Unknown providers still fail closed.
enum MarketVenue {
  panta('panta', 'Panta'),
  jupiter('jupiter', 'Jupiter'),
  polymarket('polymarket', 'Polymarket'),
  fixture('fixture', 'Demo catalog');

  const MarketVenue(this.wire, this.label);
  final String wire;
  final String label;

  /// `fixture` data must be visibly labelled as demo and can never present as
  /// a live result (contract §4).
  bool get isDemo => this == MarketVenue.fixture;

  static MarketVenue fromWire(Object? value) => switch (value) {
    'panta' => MarketVenue.panta,
    'jupiter' => MarketVenue.jupiter,
    'polymarket' => MarketVenue.polymarket,
    'fixture' => MarketVenue.fixture,
    _ => _unknown('MarketVenue', value),
  };
}

/// The asset a Panta market is quoted in. Panta's partner API serves USDC
/// markets; SOL-quoted ones are read from Panta's program by the server.
/// Either way a share's price is on Panta's 0..1 scale, so it is shown as
/// odds ([CallsFormat.odds]: "62%") with no unit, and never converted.
enum ShareCurrency {
  usdc('USDC'),
  sol('SOL');

  const ShareCurrency(this.wire);
  final String wire;

  static ShareCurrency? tryWire(Object? value) => switch (value) {
    'USDC' => ShareCurrency.usdc,
    'SOL' => ShareCurrency.sol,
    _ => null,
  };
}

/// `MarketSnapshot.source: 'venue' | 'fixture'`.
enum SnapshotSource {
  venue('venue'),
  fixture('fixture');

  const SnapshotSource(this.wire);
  final String wire;

  bool get isDemo => this == SnapshotSource.fixture;

  static SnapshotSource fromWire(Object? value) => switch (value) {
    'venue' => SnapshotSource.venue,
    'fixture' => SnapshotSource.fixture,
    _ => _unknown('SnapshotSource', value),
  };
}

/// `Call.visibility: 'public' | 'followers'`.
enum CallVisibility {
  public('public', 'Everyone'),
  followers('followers', 'Followers only');

  const CallVisibility(this.wire, this.label);
  final String wire;
  final String label;

  static CallVisibility fromWire(Object? value) => switch (value) {
    'public' => CallVisibility.public,
    'followers' => CallVisibility.followers,
    _ => _unknown('CallVisibility', value),
  };
}

/// `CallResponse.kind: 'back' | 'fade' | 'challenge'`.
enum CallResponseKind {
  back('back', 'Back'),
  fade('fade', 'Fade'),
  // Shown as "Dare": "challenge" also named the retired SOL escrow
  // feature. The wire value is frozen and stays 'challenge'.
  challenge('challenge', 'Dare');

  const CallResponseKind(this.wire, this.label);
  final String wire;
  final String label;

  /// Back and Fade ALWAYS create the actor's own call. Challenge does not —
  /// it is an invitation to the target, with no escrow and no money.
  bool get createsOwnCall => this != CallResponseKind.challenge;

  static CallResponseKind fromWire(Object? value) => switch (value) {
    'back' => CallResponseKind.back,
    'fade' => CallResponseKind.fade,
    'challenge' => CallResponseKind.challenge,
    _ => _unknown('CallResponseKind', value),
  };
}

// ---------------------------------------------------------------------------
// Scalar coercion
// ---------------------------------------------------------------------------

int _requireTimestampMs(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw CallVocabularyException(
    '$field must be unix milliseconds (integer), got "$value"',
  );
}

int? _optionalTimestampMs(Object? value, String field) =>
    value == null ? null : _requireTimestampMs(value, field);

double _requireProbability(Object? value, String field) {
  if (value is! num || value.isNaN || !value.isFinite) {
    throw CallVocabularyException(
      '$field must be a number in [0,1], got "$value"',
    );
  }
  final probability = value.toDouble();
  if (probability < 0 || probability > 1) {
    throw CallVocabularyException('$field must be in [0,1], got $probability');
  }
  return probability;
}

double? _optionalProbability(Object? value, String field) =>
    value == null ? null : _requireProbability(value, field);

String _requireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw CallVocabularyException(
    '$field must be a non-empty string, got "$value"',
  );
}

final _decimal = RegExp(r'^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$');

/// An optional, display-only venue figure: anything but a plain decimal
/// string reads as unavailable rather than failing the whole catalog.
String? _optionalDecimal(Object? value) =>
    value is String && _decimal.hasMatch(value) ? value : null;

/// Maximum length of [Call.thesis], per the contract.
const int kThesisMaxLength = 280;

// ---------------------------------------------------------------------------
// Normalized market
// ---------------------------------------------------------------------------

class MarketOutcome {
  final Side side;
  final String label;

  const MarketOutcome({required this.side, required this.label});

  factory MarketOutcome.fromJson(Map<String, dynamic> json) => MarketOutcome(
    side: Side.fromWire(json['side']),
    label: _requireString(json['label'], 'MarketOutcome.label'),
  );

  Map<String, dynamic> toJson() => {'side': side.wire, 'label': label};
}

/// `interface VenueMarket` — contract §3.
class VenueMarket {
  /// Chumbucket UUID — the stable id everything references.
  final String id;
  final MarketVenue venue;
  final String venueEventId;

  /// Preserved verbatim, never re-encoded.
  final String venueMarketId;

  /// The exact question shown to the user.
  final String question;

  /// The venue's exact resolution criteria — **never paraphrased**.
  final String rulesText;
  final String category;
  final List<MarketOutcome> outcomes;
  final MarketStatus status;

  /// The venue's own status string, unmapped.
  final String rawStatus;
  final int? opensAt;
  final int? closesAt;
  final int? resolvesAt;
  final String? resolutionSource;
  final int lastSyncedAt;

  /// Bumped when the adapter's normalisation changes.
  final int payloadVersion;

  /// The venue's own reported trading volume (Panta `volumeUsdc`), verbatim.
  /// Catalog-only and display/sort-only: null when the venue did not report
  /// it or an older server omits it — never estimated, never zero-filled.
  final String? volumeUsdc;

  /// The market's quote asset, as the server reports it. Null from an older
  /// server (which only served USDC markets) and for non-Panta rows.
  final ShareCurrency? quoteCurrency;

  /// The server's `tradable`: whether Chumbucket can place a trade here.
  /// Null from an older server. Read [tradable], never this directly.
  final bool? tradableFlag;

  const VenueMarket({
    required this.id,
    required this.venue,
    required this.venueEventId,
    required this.venueMarketId,
    required this.question,
    required this.rulesText,
    required this.category,
    required this.outcomes,
    required this.status,
    required this.rawStatus,
    required this.opensAt,
    required this.closesAt,
    required this.resolvesAt,
    required this.resolutionSource,
    required this.lastSyncedAt,
    required this.payloadVersion,
    this.volumeUsdc,
    this.quoteCurrency,
    this.tradableFlag,
  });

  /// A trade can be offered only on a Panta market the server says it can
  /// trade. Calls never depend on this. An older server that sends no flag
  /// only ever served tradable USDC markets.
  bool get tradable =>
      venue == MarketVenue.panta &&
      (tradableFlag ?? quoteCurrency != ShareCurrency.sol);

  DateTime? get closesAtUtc =>
      closesAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(closesAt!, isUtc: true);

  DateTime get lastSyncedAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(lastSyncedAt, isUtc: true);

  String labelFor(Side side) =>
      outcomes
          .firstWhere(
            (outcome) => outcome.side == side,
            orElse: () => MarketOutcome(side: side, label: side.label),
          )
          .label;

  factory VenueMarket.fromJson(Map<String, dynamic> json) => VenueMarket(
    id: _requireString(json['id'], 'VenueMarket.id'),
    venue: MarketVenue.fromWire(json['venue']),
    venueEventId: _requireString(
      json['venueEventId'],
      'VenueMarket.venueEventId',
    ),
    venueMarketId: _requireString(
      json['venueMarketId'],
      'VenueMarket.venueMarketId',
    ),
    question: _requireString(json['question'], 'VenueMarket.question'),
    rulesText: _requireString(json['rulesText'], 'VenueMarket.rulesText'),
    category: _requireString(json['category'], 'VenueMarket.category'),
    outcomes: (json['outcomes'] as List<dynamic>? ?? const [])
        .map((e) => MarketOutcome.fromJson(e as Map<String, dynamic>))
        .toList(growable: false),
    status: MarketStatus.fromWire(json['status']),
    rawStatus: _requireString(json['rawStatus'], 'VenueMarket.rawStatus'),
    opensAt: _optionalTimestampMs(json['opensAt'], 'VenueMarket.opensAt'),
    closesAt: _optionalTimestampMs(json['closesAt'], 'VenueMarket.closesAt'),
    resolvesAt: _optionalTimestampMs(
      json['resolvesAt'],
      'VenueMarket.resolvesAt',
    ),
    resolutionSource: json['resolutionSource'] as String?,
    lastSyncedAt: _requireTimestampMs(
      json['lastSyncedAt'],
      'VenueMarket.lastSyncedAt',
    ),
    payloadVersion: (json['payloadVersion'] as num?)?.toInt() ?? 1,
    volumeUsdc: _optionalDecimal(json['volumeUsdc']),
    quoteCurrency: ShareCurrency.tryWire(json['quoteCurrency']),
    tradableFlag: json['tradable'] is bool ? json['tradable'] as bool : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'venue': venue.wire,
    'venueEventId': venueEventId,
    'venueMarketId': venueMarketId,
    'question': question,
    'rulesText': rulesText,
    'category': category,
    'outcomes': outcomes.map((o) => o.toJson()).toList(growable: false),
    'status': status.wire,
    'rawStatus': rawStatus,
    'opensAt': opensAt,
    'closesAt': closesAt,
    'resolvesAt': resolvesAt,
    'resolutionSource': resolutionSource,
    'lastSyncedAt': lastSyncedAt,
    'payloadVersion': payloadVersion,
    if (volumeUsdc != null) 'volumeUsdc': volumeUsdc,
    if (quoteCurrency != null) 'quoteCurrency': quoteCurrency!.wire,
    if (tradableFlag != null) 'tradable': tradableFlag,
  };

  VenueMarket copyWith({
    MarketStatus? status,
    int? lastSyncedAt,
    MarketVenue? venue,
  }) => VenueMarket(
    id: id,
    venue: venue ?? this.venue,
    venueEventId: venueEventId,
    venueMarketId: venueMarketId,
    question: question,
    rulesText: rulesText,
    category: category,
    outcomes: outcomes,
    status: status ?? this.status,
    rawStatus: rawStatus,
    opensAt: opensAt,
    closesAt: closesAt,
    resolvesAt: resolvesAt,
    resolutionSource: resolutionSource,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    payloadVersion: payloadVersion,
    volumeUsdc: volumeUsdc,
    quoteCurrency: quoteCurrency,
    tradableFlag: tradableFlag,
  );
}

/// `interface MarketSnapshot` — contract §3.
class MarketSnapshot {
  final String marketId;

  /// `[0,1]`.
  final double yesProbability;
  final int observedAt;
  final SnapshotSource source;

  /// Not on the contract wire for `MarketSnapshot`, but the BFF returns the
  /// snapshot row's id so a [Call] can reference it via `snapshotId`.
  final String? id;

  const MarketSnapshot({
    required this.marketId,
    required this.yesProbability,
    required this.observedAt,
    required this.source,
    this.id,
  });

  double get noProbability => 1 - yesProbability;

  double probabilityFor(Side side) =>
      side == Side.yes ? yesProbability : noProbability;

  DateTime get observedAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(observedAt, isUtc: true);

  /// How old this price is relative to [now].
  Duration ageAt(DateTime now) =>
      now.toUtc().difference(observedAtUtc).isNegative
          ? Duration.zero
          : now.toUtc().difference(observedAtUtc);

  factory MarketSnapshot.fromJson(Map<String, dynamic> json) => MarketSnapshot(
    marketId: _requireString(json['marketId'], 'MarketSnapshot.marketId'),
    yesProbability: _requireProbability(
      json['yesProbability'],
      'MarketSnapshot.yesProbability',
    ),
    observedAt: _requireTimestampMs(
      json['observedAt'],
      'MarketSnapshot.observedAt',
    ),
    source: SnapshotSource.fromWire(json['source']),
    id: json['id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'marketId': marketId,
    'yesProbability': yesProbability,
    'observedAt': observedAt,
    'source': source.wire,
    if (id != null) 'id': id,
  };
}

// ---------------------------------------------------------------------------
// Call, response, result
// ---------------------------------------------------------------------------

/// Independent, non-executable unit prices. Never convert to percent or infer
/// one side from the other; strings preserve provider precision exactly.
/// [currency] is the market's own quote asset (USDC, or SOL for a SOL-quoted
/// Panta market), never converted to USD.
class SharePriceSnapshot {
  final String id;
  final String marketId;
  final String? yesPrice;
  final String? noPrice;
  final int observedAt;
  final ShareCurrency currency;
  const SharePriceSnapshot({
    required this.id,
    required this.marketId,
    required this.yesPrice,
    required this.noPrice,
    required this.observedAt,
    this.currency = ShareCurrency.usdc,
  });

  static const attribution = 'Powered by Panta';
  static final _decimal = RegExp(r'^(0|[1-9]\d{0,30})(\.\d{1,18})?$');
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  String? priceFor(Side side) => side == Side.yes ? yesPrice : noPrice;
  DateTime get observedAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(observedAt, isUtc: true);
  bool isUsableAt(DateTime now) =>
      yesPrice != null &&
      noPrice != null &&
      !observedAtUtc.isAfter(now.toUtc()) &&
      now.toUtc().difference(observedAtUtc) <= const Duration(minutes: 10);

  factory SharePriceSnapshot.fromJson(Map<String, dynamic> json) {
    const keys = {
      'id',
      'marketId',
      'venue',
      'currency',
      'unit',
      'yesPrice',
      'noPrice',
      'observedAt',
      'source',
      'attribution',
      'executable',
    };
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        json['venue'] != 'panta' ||
        ShareCurrency.tryWire(json['currency']) == null ||
        json['unit'] != 'per_share' ||
        json['source'] != 'venue' ||
        json['attribution'] != attribution ||
        json['executable'] != false) {
      throw const CallVocabularyException('Invalid Panta share-price contract');
    }
    String? price(Object? v) {
      if (v == null) return null;
      if (v is! String || !_decimal.hasMatch(v)) {
        throw const CallVocabularyException(
          'Invalid share-price decimal string',
        );
      }
      return v;
    }

    final id = _requireString(json['id'], 'SharePriceSnapshot.id');
    final market = _requireString(
      json['marketId'],
      'SharePriceSnapshot.marketId',
    );
    final time = _requireTimestampMs(
      json['observedAt'],
      'SharePriceSnapshot.observedAt',
    );
    if (!_uuid.hasMatch(id) ||
        !_uuid.hasMatch(market) ||
        time <= 0 ||
        time > 9007199254740991) {
      throw const CallVocabularyException(
        'Invalid share-price identity or timestamp',
      );
    }
    return SharePriceSnapshot(
      id: id,
      marketId: market,
      yesPrice: price(json['yesPrice']),
      noPrice: price(json['noPrice']),
      observedAt: time,
      currency: ShareCurrency.tryWire(json['currency'])!,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'marketId': marketId,
    'venue': 'panta',
    'currency': currency.wire,
    'unit': 'per_share',
    'yesPrice': yesPrice,
    'noPrice': noPrice,
    'observedAt': observedAt,
    'source': 'venue',
    'attribution': attribution,
    'executable': false,
  };
}

/// A free, immutable statement, not a trade. Native price evidence is additive;
/// historical probability evidence retains its original meaning.
class Call {
  final String id;

  /// Canonical `public.users.id` — **NEVER** a wallet.
  final String userId;
  final String marketId;
  final Side side;

  /// `[0,1]`, self-reported, optional.
  final double? confidence;

  /// `<= 280` chars.
  final String? thesis;
  final double? entryProbability;
  final String? snapshotId;
  final SharePriceSnapshot? entryPrice;
  final CallVisibility visibility;
  final int createdAt;

  /// Immutable from this instant.
  final int lockedAt;

  /// Set when this call came from a Back or a Fade.
  final String? parentCallId;

  /// `NONE` for a free call.
  final FundingState fundingState;

  const Call({
    required this.id,
    required this.userId,
    required this.marketId,
    required this.side,
    required this.confidence,
    required this.thesis,
    required this.entryProbability,
    required this.snapshotId,
    this.entryPrice,
    required this.visibility,
    required this.createdAt,
    required this.lockedAt,
    required this.parentCallId,
    required this.fundingState,
  });

  DateTime get createdAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);

  DateTime get lockedAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(lockedAt, isUtc: true);

  bool get isLocked => true;

  factory Call.fromJson(Map<String, dynamic> json) {
    final native = json['entryPrice'];
    if (native != null && native is! Map<String, dynamic>) {
      throw const CallVocabularyException('Call.entryPrice must be an object');
    }
    final entryPrice =
        native == null
            ? null
            : SharePriceSnapshot.fromJson(native as Map<String, dynamic>);
    if (entryPrice != null &&
        (entryPrice.marketId != json['marketId'] ||
            json['entryProbability'] != null ||
            json['snapshotId'] != null ||
            !entryPrice.isUsableAt(
              DateTime.fromMillisecondsSinceEpoch(
                _requireTimestampMs(json['lockedAt'], 'Call.lockedAt'),
                isUtc: true,
              ),
            ))) {
      throw const CallVocabularyException(
        'Call share-price provenance mismatch',
      );
    }
    final thesis = json['thesis'] as String?;
    if (thesis != null && thesis.length > kThesisMaxLength) {
      throw CallVocabularyException(
        'Call.thesis must be <= $kThesisMaxLength chars, got ${thesis.length}',
      );
    }
    return Call(
      id: _requireString(json['id'], 'Call.id'),
      userId: _requireString(json['userId'], 'Call.userId'),
      marketId: _requireString(json['marketId'], 'Call.marketId'),
      side: Side.fromWire(json['side']),
      confidence: _optionalProbability(json['confidence'], 'Call.confidence'),
      thesis: thesis,
      entryProbability: _optionalProbability(
        json['entryProbability'],
        'Call.entryProbability',
      ),
      snapshotId: json['snapshotId'] as String?,
      entryPrice: entryPrice,
      visibility: CallVisibility.fromWire(json['visibility']),
      createdAt: _requireTimestampMs(json['createdAt'], 'Call.createdAt'),
      lockedAt: _requireTimestampMs(json['lockedAt'], 'Call.lockedAt'),
      parentCallId: json['parentCallId'] as String?,
      fundingState: FundingState.fromWire(json['fundingState']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'marketId': marketId,
    'side': side.wire,
    'confidence': confidence,
    'thesis': thesis,
    'entryProbability': entryProbability,
    'snapshotId': snapshotId,
    if (entryPrice != null) 'entryPrice': entryPrice!.toJson(),
    'visibility': visibility.wire,
    'createdAt': createdAt,
    'lockedAt': lockedAt,
    'parentCallId': parentCallId,
    'fundingState': fundingState.wire,
  };
}

/// `interface CallResponse` — contract §3.
class CallResponse {
  final String id;
  final String actorUserId;
  final String targetCallId;
  final CallResponseKind kind;

  /// back/fade ALWAYS create the actor's own call; challenge leaves this null.
  final String? resultingCallId;
  final int createdAt;

  const CallResponse({
    required this.id,
    required this.actorUserId,
    required this.targetCallId,
    required this.kind,
    required this.resultingCallId,
    required this.createdAt,
  });

  DateTime get createdAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);

  factory CallResponse.fromJson(Map<String, dynamic> json) => CallResponse(
    id: _requireString(json['id'], 'CallResponse.id'),
    actorUserId: _requireString(
      json['actorUserId'],
      'CallResponse.actorUserId',
    ),
    targetCallId: _requireString(
      json['targetCallId'],
      'CallResponse.targetCallId',
    ),
    kind: CallResponseKind.fromWire(json['kind']),
    resultingCallId: json['resultingCallId'] as String?,
    createdAt: _requireTimestampMs(json['createdAt'], 'CallResponse.createdAt'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'actorUserId': actorUserId,
    'targetCallId': targetCallId,
    'kind': kind.wire,
    'resultingCallId': resultingCallId,
    'createdAt': createdAt,
  };
}

/// `interface CallResult` — contract §3. Service-derived only; a client never
/// writes one.
class CallResult {
  final String callId;
  final CallOutcome outcome;
  final Resolution? resolution;
  final int? resolvedAt;

  /// The venue evidence this was derived from.
  final String? marketResolutionId;
  final int derivedAt;

  const CallResult({
    required this.callId,
    required this.outcome,
    required this.resolution,
    required this.resolvedAt,
    required this.marketResolutionId,
    required this.derivedAt,
  });

  DateTime? get resolvedAtUtc =>
      resolvedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(resolvedAt!, isUtc: true);

  factory CallResult.fromJson(Map<String, dynamic> json) => CallResult(
    callId: _requireString(json['callId'], 'CallResult.callId'),
    outcome: CallOutcome.fromWire(json['outcome']),
    resolution:
        json['resolution'] == null
            ? null
            : Resolution.fromWire(json['resolution']),
    resolvedAt: _optionalTimestampMs(
      json['resolvedAt'],
      'CallResult.resolvedAt',
    ),
    marketResolutionId: json['marketResolutionId'] as String?,
    derivedAt: _requireTimestampMs(json['derivedAt'], 'CallResult.derivedAt'),
  );

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'outcome': outcome.wire,
    'resolution': resolution?.wire,
    'resolvedAt': resolvedAt,
    'marketResolutionId': marketResolutionId,
    'derivedAt': derivedAt,
  };
}

/// The **only** permitted result derivation — contract §3.
///
/// ```
/// resolution === 'VOID'            -> VOID
/// resolution === call.side         -> CORRECT
/// resolution is the other side     -> INCORRECT
/// no resolution yet                -> PENDING
/// ```
///
/// Late resolution stays `PENDING`. There is no other branch, no admin
/// override and no client input.
CallOutcome deriveCallOutcome({
  required Side side,
  required Resolution? resolution,
}) {
  if (resolution == null) return CallOutcome.pending;
  if (resolution == Resolution.voided) return CallOutcome.voided;
  return resolution.side == side ? CallOutcome.correct : CallOutcome.incorrect;
}
