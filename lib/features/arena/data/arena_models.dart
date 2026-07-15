/// Data models for the Arena feature.
///
/// These mirror the shape returned by the gaffer-backend tRPC read API
/// (`/matchday`, `/match`) - a read-only service that lists fixtures and the
/// live/settled state of their on-chain parimutuel Pots. No money moves
/// through this API; it only tells the client which `matchId` (and therefore
/// which on-chain PDAs) to use.
library;

/// The three outcome buckets a "call" can be staked on.
///
/// The numeric index is load-bearing: it is passed as the `bucket: u8`
/// argument to the chumbucket_arena program's `place_call` instruction, and
/// must match `bucket_totals[3]`'s array order on-chain exactly.
class ArenaBucketIndex {
  static const int home = 0;
  static const int draw = 1;
  static const int away = 2;

  /// Convert the backend's bucket label ("HOME"/"DRAW"/"AWAY") to the
  /// on-chain u8 index.
  static int fromLabel(String label) {
    switch (label.toUpperCase()) {
      case 'HOME':
        return home;
      case 'DRAW':
        return draw;
      case 'AWAY':
        return away;
      default:
        throw ArgumentError('Unknown bucket label: $label');
    }
  }

  static String toLabel(int index) {
    switch (index) {
      case home:
        return 'HOME';
      case draw:
        return 'DRAW';
      case away:
        return 'AWAY';
      default:
        throw ArgumentError('Unknown bucket index: $index');
    }
  }
}

class ArenaTxlineRef {
  final int fixtureId;
  final bool participant1IsHome;

  const ArenaTxlineRef({
    required this.fixtureId,
    required this.participant1IsHome,
  });

  factory ArenaTxlineRef.fromJson(Map<String, dynamic> json) => ArenaTxlineRef(
    fixtureId: (json['fixtureId'] as num).toInt(),
    participant1IsHome: json['participant1IsHome'] as bool? ?? true,
  );
}

class ArenaFixture {
  /// The backend's stable identifier for this market. This is the exact
  /// string that gets ASCII-encoded + left-padded to 32 bytes for the
  /// on-chain Pot PDA seed - it is NOT re-derived or guessed client-side.
  final String matchId;
  final String home;
  final String away;
  final String competition;
  final String? group;
  final String stage;
  final DateTime kickoff;
  final ArenaTxlineRef? txline;

  const ArenaFixture({
    required this.matchId,
    required this.home,
    required this.away,
    required this.competition,
    this.group,
    required this.stage,
    required this.kickoff,
    this.txline,
  });

  String get title => '$home vs $away';

  factory ArenaFixture.fromJson(Map<String, dynamic> json) => ArenaFixture(
    matchId: json['matchId'].toString(),
    home: json['home'] as String? ?? 'Home',
    away: json['away'] as String? ?? 'Away',
    competition: json['competition'] as String? ?? '',
    group: json['group'] as String?,
    stage: json['stage'] as String? ?? '',
    kickoff: DateTime.fromMillisecondsSinceEpoch(
      (json['kickoff'] as num).toInt(),
      isUtc: true,
    ),
    txline:
        json['txline'] != null
            ? ArenaTxlineRef.fromJson(json['txline'] as Map<String, dynamic>)
            : null,
  );
}

class ArenaBucketTotal {
  final String bucket; // "HOME" | "DRAW" | "AWAY"
  final String label;

  /// Total staked in this bucket, in the USDC mint's base units (6 decimals).
  final BigInt stake;
  final double impliedProb;
  final int callerCount;

  const ArenaBucketTotal({
    required this.bucket,
    required this.label,
    required this.stake,
    required this.impliedProb,
    required this.callerCount,
  });

  int get bucketIndex => ArenaBucketIndex.fromLabel(bucket);

  factory ArenaBucketTotal.fromJson(Map<String, dynamic> json) =>
      ArenaBucketTotal(
        bucket: json['bucket'] as String,
        label: json['label'] as String? ?? json['bucket'] as String,
        stake: BigInt.parse(json['stake'].toString()),
        impliedProb: (json['impliedProb'] as num?)?.toDouble() ?? 0,
        callerCount: (json['callerCount'] as num?)?.toInt() ?? 0,
      );
}

class ArenaMarket {
  final String matchId;
  final String marketId;
  final String kind;
  final String label;
  final String status;
  final List<ArenaBucketTotal> buckets;
  final BigInt grossPot;
  final int participantCount;

  /// Set once the match has settled - which bucket the on-chain proof
  /// confirmed won. Null while the market is still OPEN/LOCKED.
  final String? winningBucket;
  final bool settled;

  const ArenaMarket({
    required this.matchId,
    required this.marketId,
    required this.kind,
    required this.label,
    required this.status,
    required this.buckets,
    required this.grossPot,
    required this.participantCount,
    required this.winningBucket,
    required this.settled,
  });

  ArenaBucketTotal? bucketByIndex(int index) {
    for (final b in buckets) {
      if (b.bucketIndex == index) return b;
    }
    return null;
  }

  factory ArenaMarket.fromJson(Map<String, dynamic> json) => ArenaMarket(
    matchId: json['matchId'].toString(),
    marketId: json['marketId'] as String? ?? 'RESULT',
    kind: json['kind'] as String? ?? 'RESULT',
    label: json['label'] as String? ?? 'Full-time result',
    status: json['status'] as String? ?? 'OPEN',
    buckets:
        ((json['buckets'] as List?) ?? const [])
            .map((b) => ArenaBucketTotal.fromJson(b as Map<String, dynamic>))
            .toList(),
    grossPot: BigInt.parse((json['grossPot'] ?? '0').toString()),
    participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
    winningBucket: json['winningBucket'] as String?,
    settled: json['settled'] as bool? ?? false,
  );
}

class ArenaScore {
  final int home;
  final int away;

  const ArenaScore({required this.home, required this.away});

  factory ArenaScore.fromJson(Map<String, dynamic> json) => ArenaScore(
    home: (json['home'] as num?)?.toInt() ?? 0,
    away: (json['away'] as num?)?.toInt() ?? 0,
  );
}

/// One matchday list entry: a fixture plus its RESULT market's live/settled
/// pot state.
class ArenaMatchEntry {
  final ArenaFixture fixture;

  /// "OPEN" | "LOCKED" | "RESOLVED" (backend-level status - distinct from
  /// the raw on-chain Pot.status byte, which this app never decodes
  /// directly; settlement truth for display purposes comes from here).
  final String status;
  final List<ArenaMarket> markets;
  final ArenaScore? score;

  const ArenaMatchEntry({
    required this.fixture,
    required this.status,
    required this.markets,
    this.score,
  });

  /// The single RESULT (HOME/DRAW/AWAY) market this feature stakes into.
  ArenaMarket? get resultMarket {
    for (final m in markets) {
      if (m.kind == 'RESULT') return m;
    }
    return markets.isNotEmpty ? markets.first : null;
  }

  bool get isOpenForCalls => status == 'OPEN';

  factory ArenaMatchEntry.fromJson(Map<String, dynamic> json) =>
      ArenaMatchEntry(
        fixture: ArenaFixture.fromJson(json['fixture'] as Map<String, dynamic>),
        status: json['status'] as String? ?? 'OPEN',
        markets:
            ((json['markets'] as List?) ?? const [])
                .map((m) => ArenaMarket.fromJson(m as Map<String, dynamic>))
                .toList(),
        score:
            json['score'] != null
                ? ArenaScore.fromJson(json['score'] as Map<String, dynamic>)
                : null,
      );
}

/// A locally-persisted record of one Arena stake, used to power
/// the My Pots history/claim list. The `matchId`/`bucket`/`stake` shown here
/// are what the app itself submitted; on-chain `claimed` truth is
/// cross-checked live against the Position account before enabling Claim.
class MyPotRecord {
  final String matchId;
  final String home;
  final String away;
  final int bucket;
  final double amountUsdc;
  final String txSignature;
  final DateTime placedAt;

  /// Optimistic local flag, set immediately after a successful claim() call.
  /// The My Pots screen still re-verifies against the on-chain Position
  /// account (`claimed: bool`) whenever it can reach the chain.
  final bool claimedLocally;

  const MyPotRecord({
    required this.matchId,
    required this.home,
    required this.away,
    required this.bucket,
    required this.amountUsdc,
    required this.txSignature,
    required this.placedAt,
    this.claimedLocally = false,
  });

  MyPotRecord copyWith({bool? claimedLocally}) => MyPotRecord(
    matchId: matchId,
    home: home,
    away: away,
    bucket: bucket,
    amountUsdc: amountUsdc,
    txSignature: txSignature,
    placedAt: placedAt,
    claimedLocally: claimedLocally ?? this.claimedLocally,
  );

  Map<String, dynamic> toJson() => {
    'matchId': matchId,
    'home': home,
    'away': away,
    'bucket': bucket,
    'amountUsdc': amountUsdc,
    'txSignature': txSignature,
    'placedAt': placedAt.toIso8601String(),
    'claimedLocally': claimedLocally,
  };

  factory MyPotRecord.fromJson(Map<String, dynamic> json) => MyPotRecord(
    matchId: json['matchId'] as String,
    home: json['home'] as String,
    away: json['away'] as String,
    bucket: json['bucket'] as int,
    amountUsdc: (json['amountUsdc'] as num).toDouble(),
    txSignature: json['txSignature'] as String,
    placedAt: DateTime.parse(json['placedAt'] as String),
    claimedLocally: json['claimedLocally'] as bool? ?? false,
  );
}

class ArenaServerPosition {
  final String id;
  final String matchId;
  final String bucket;
  final BigInt stakeBaseUnits;
  final String txSignature;
  final DateTime placedAt;
  final String status;
  final Map<String, dynamic> metadata;

  const ArenaServerPosition({
    required this.id,
    required this.matchId,
    required this.bucket,
    required this.stakeBaseUnits,
    required this.txSignature,
    required this.placedAt,
    required this.status,
    required this.metadata,
  });

  factory ArenaServerPosition.fromJson(
    Map<String, dynamic> json,
  ) => ArenaServerPosition(
    id: json['id'].toString(),
    matchId: json['match_id'].toString(),
    bucket: json['bucket'] as String? ?? 'HOME',
    stakeBaseUnits: BigInt.parse(json['stake_base_units'].toString()),
    txSignature: json['open_tx_signature'] as String? ?? '',
    placedAt:
        DateTime.tryParse(json['placed_at'] as String? ?? '') ?? DateTime.now(),
    status: json['status'] as String? ?? 'PENDING',
    metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
  );

  MyPotRecord toMyPotRecord({bool claimedLocally = false}) {
    final amountUsdc = stakeBaseUnits.toDouble() / 1000000;
    return MyPotRecord(
      matchId: matchId,
      home: metadata['home'] as String? ?? 'Home',
      away: metadata['away'] as String? ?? 'Away',
      bucket: ArenaBucketIndex.fromLabel(bucket),
      amountUsdc: amountUsdc,
      txSignature: txSignature,
      placedAt: placedAt,
      claimedLocally: claimedLocally || status == 'CLAIMED',
    );
  }
}

class ArenaActivityEvent {
  final String id;
  final String walletAddress;
  final String type;
  final String status;
  final String? matchId;
  final String? bucket;
  final BigInt? stakeBaseUnits;
  final String? txSignature;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  const ArenaActivityEvent({
    required this.id,
    required this.walletAddress,
    required this.type,
    required this.status,
    required this.matchId,
    required this.bucket,
    required this.stakeBaseUnits,
    required this.txSignature,
    required this.createdAt,
    required this.metadata,
  });

  factory ArenaActivityEvent.fromJson(Map<String, dynamic> json) =>
      ArenaActivityEvent(
        id: json['id'].toString(),
        walletAddress: json['actor_wallet_address'] as String? ?? '',
        type: json['type'] as String? ?? 'CALL_PLACED',
        status: json['status'] as String? ?? 'PENDING',
        matchId: json['match_id'] as String?,
        bucket: json['bucket'] as String?,
        stakeBaseUnits:
            json['stake_base_units'] == null
                ? null
                : BigInt.parse(json['stake_base_units'].toString()),
        txSignature: json['tx_signature'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        metadata: Map<String, dynamic>.from(
          json['metadata'] as Map? ?? const {},
        ),
      );

  String get home => metadata['home'] as String? ?? 'Home';
  String get away => metadata['away'] as String? ?? 'Away';
  String get fixtureTitle => '$home vs $away';
  bool get isVerified => status == 'VERIFIED' || status == 'OPEN';
}
