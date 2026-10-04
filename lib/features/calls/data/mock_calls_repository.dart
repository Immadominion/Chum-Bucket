/// In-memory [CallsRepository]. This is the implementation the slice ships on
/// until Packet B's BFF routes exist.
///
/// It is not a stub: it enforces the same rules the server will. A call is
/// immutable once created, Back and Fade always mint the actor's own call, a
/// challenge never mints one and never carries money, the crowd split is
/// withheld until the viewer has locked, and every result is produced by
/// [deriveCallOutcome] rather than written by hand.
///
/// The seed deliberately covers every state the UI has to render: all five
/// [MarketStatus] values, all four [CallOutcome] values, a fixture (demo)
/// venue, a stale snapshot, a market with no snapshot at all, a followers-only
/// call, and a call that came from a Fade.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';

class MockCallsRepository implements CallsRepository {
  MockCallsRepository({
    DateTime Function()? clock,
    this.latency = Duration.zero,
    String linkHost = 'https://chumbucket.fun',
  }) : _clock = clock ?? DateTime.now,
       _linkHost = linkHost {
    _seed();
  }

  final DateTime Function() _clock;
  final String _linkHost;

  /// Artificial delay so the loading state is reachable in the running app.
  /// Tests construct with [Duration.zero].
  final Duration latency;

  /// Flip to make every call throw [CallsOfflineException] — the offline state
  /// is reachable from the app's debug affordance and from tests.
  bool simulateOffline = false;

  /// Flip to make every call throw [CallsFailure].
  bool simulateFailure = false;

  final List<Person> _people = [];
  final List<VenueMarket> _markets = [];
  final Map<String, MarketSnapshot> _snapshots = {};
  final List<Call> _calls = [];
  final Map<String, CallResult> _results = {};
  final List<CallResponse> _responses = [];
  final List<ChallengeInvitation> _invitations = [];
  final Set<String> _viewerFollows = {};

  int _sequence = 0;

  /// The signed-in person the app uses when a session exists. Exposed so the
  /// shell can hand the provider a `viewerUserId` without a wallet.
  static const String demoViewerUserId = 'user_you';

  int get _nowMs => _clock().toUtc().millisecondsSinceEpoch;

  String _nextId(String prefix) => '${prefix}_${++_sequence}';

  // -------------------------------------------------------------------------
  // Seed
  // -------------------------------------------------------------------------

  void _seed() {
    final now = _clock().toUtc();
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    int ahead(Duration d) => now.add(d).millisecondsSinceEpoch;

    _people.addAll(const [
      Person(
        id: demoViewerUserId,
        handle: 'you',
        displayName: 'You',
        settledCalls: 4,
        correctCalls: 3,
      ),
      Person(
        id: 'user_ada',
        handle: 'ada',
        displayName: 'Ada Okafor',
        walletAddress: '7xKXtg2CW3Mock1AdaWa11etAddre55F0rDem0Use',
        settledCalls: 31,
        correctCalls: 19,
      ),
      Person(
        id: 'user_kemi',
        handle: 'kemi',
        displayName: 'Kemi Balogun',
        settledCalls: 12,
        correctCalls: 8,
      ),
      Person(
        id: 'user_tobi',
        handle: 'tobi',
        displayName: 'Tobi Eze',
        settledCalls: 0,
        correctCalls: 0,
      ),
      Person(
        id: 'user_zed',
        handle: 'zed',
        displayName: 'Zed',
        settledCalls: 57,
        correctCalls: 24,
      ),
    ]);

    _viewerFollows.addAll({'user_ada', 'user_kemi'});

    _markets.addAll([
      VenueMarket(
        id: 'market_btc_150k',
        venue: MarketVenue.fixture,
        venueEventId: 'evt_btc_eoy',
        venueMarketId: 'jup:btc-above-150000-2026-12-31',
        question: 'Will BTC trade above \$150,000 before 31 Dec 2026?',
        rulesText:
            'This market resolves YES if the Coinbase BTC-USD spot price prints '
            'at or above 150,000.00 USD at any point between 00:00 UTC on 1 Jan '
            '2026 and 23:59 UTC on 31 Dec 2026, as recorded by the Coinbase '
            'Exchange public trade feed. Wicks count. Index prices, perpetual '
            'marks and prices from any other venue do not count. If the feed is '
            'unavailable for more than 6 consecutive hours the market resolves '
            'using the Kraken BTC-USD spot feed for that window.',
        category: 'crypto',
        outcomes: const [
          MarketOutcome(side: Side.yes, label: 'Yes — it prints 150k'),
          MarketOutcome(side: Side.no, label: 'No — it never gets there'),
        ],
        status: MarketStatus.open,
        rawStatus: 'active',
        opensAt: ago(const Duration(days: 90)),
        closesAt: ahead(const Duration(days: 40)),
        resolvesAt: ahead(const Duration(days: 41)),
        resolutionSource: 'Coinbase Exchange BTC-USD public trade feed',
        lastSyncedAt: ago(const Duration(minutes: 2)),
        payloadVersion: 1,
      ),
      VenueMarket(
        id: 'market_sol_flip',
        venue: MarketVenue.fixture,
        venueEventId: 'evt_demo_sol',
        venueMarketId: 'fixture:sol-flips-eth-fdv',
        question: 'Will SOL fully-diluted value exceed ETH before Q2 close?',
        rulesText:
            'DEMO MARKET. Resolves YES if the fully-diluted valuation of SOL, as '
            'published by the demo catalog at 23:59 UTC on the quarter close, is '
            'strictly greater than that of ETH. This is sample data for product '
            'demonstration and carries no real resolution.',
        category: 'crypto',
        outcomes: const [
          MarketOutcome(side: Side.yes, label: 'Yes'),
          MarketOutcome(side: Side.no, label: 'No'),
        ],
        status: MarketStatus.open,
        rawStatus: 'demo-open',
        opensAt: ago(const Duration(days: 12)),
        closesAt: ahead(const Duration(days: 6)),
        resolvesAt: ahead(const Duration(days: 7)),
        resolutionSource: 'Chumbucket demo catalog',
        lastSyncedAt: ago(const Duration(hours: 5)),
        payloadVersion: 1,
      ),
      VenueMarket(
        id: 'market_etf_flows',
        venue: MarketVenue.fixture,
        venueEventId: 'evt_etf_week',
        venueMarketId: 'jup:eth-etf-net-inflow-week-37',
        question: 'Net ETH ETF inflows positive for the week of 8 Sep?',
        rulesText:
            'Resolves YES if the sum of daily net flows across all US spot ETH '
            'ETFs for the trading week beginning Monday 8 September 2026 is '
            'strictly greater than zero USD, per the issuer-reported daily flow '
            'tables aggregated by Farside Investors at the first publication '
            'after the Friday close.',
        category: 'crypto',
        outcomes: const [
          MarketOutcome(side: Side.yes, label: 'Yes — net positive'),
          MarketOutcome(side: Side.no, label: 'No — net negative or flat'),
        ],
        status: MarketStatus.closedPendingResolution,
        rawStatus: 'closed',
        opensAt: ago(const Duration(days: 20)),
        closesAt: ago(const Duration(days: 2)),
        resolvesAt: null,
        resolutionSource: 'Farside Investors daily flow tables',
        lastSyncedAt: ago(const Duration(minutes: 11)),
        payloadVersion: 1,
      ),
      VenueMarket(
        id: 'market_fed_cut',
        venue: MarketVenue.fixture,
        venueEventId: 'evt_fomc_sep',
        venueMarketId: 'jup:fomc-sep-2026-cut-25bp',
        question: 'Did the FOMC cut by 25bp at the September meeting?',
        rulesText:
            'Resolves YES if the Federal Open Market Committee statement '
            'released at the conclusion of its September 2026 meeting announces a '
            'target range reduction of exactly 25 basis points. Any other change, '
            'or no change, resolves NO.',
        category: 'crypto',
        outcomes: const [
          MarketOutcome(side: Side.yes, label: 'Yes — 25bp cut'),
          MarketOutcome(side: Side.no, label: 'No'),
        ],
        status: MarketStatus.resolved,
        rawStatus: 'resolved',
        opensAt: ago(const Duration(days: 45)),
        closesAt: ago(const Duration(days: 5)),
        resolvesAt: ago(const Duration(days: 5)),
        resolutionSource: 'FOMC statement, federalreserve.gov',
        lastSyncedAt: ago(const Duration(hours: 4)),
        payloadVersion: 1,
      ),
      VenueMarket(
        id: 'market_cancelled_listing',
        venue: MarketVenue.fixture,
        venueEventId: 'evt_listing_rumour',
        venueMarketId: 'jup:exchange-listing-rumour-q3',
        question: 'Will the rumoured Q3 listing be announced?',
        rulesText:
            'Resolves YES on a public announcement from the exchange before the '
            'close date. The venue cancelled this market because the underlying '
            'event was withdrawn and no unambiguous resolution source remained.',
        category: 'crypto',
        outcomes: const [
          MarketOutcome(side: Side.yes, label: 'Yes'),
          MarketOutcome(side: Side.no, label: 'No'),
        ],
        status: MarketStatus.cancelled,
        rawStatus: 'void',
        opensAt: ago(const Duration(days: 30)),
        closesAt: ago(const Duration(days: 8)),
        resolvesAt: ago(const Duration(days: 8)),
        resolutionSource: null,
        lastSyncedAt: ago(const Duration(hours: 9)),
        payloadVersion: 1,
      ),
      VenueMarket(
        id: 'market_paused_depeg',
        venue: MarketVenue.fixture,
        venueEventId: 'evt_depeg_watch',
        venueMarketId: 'jup:stable-depeg-below-0985',
        question: 'Will the stablecoin trade below \$0.985 this month?',
        rulesText:
            'Resolves YES if the 1-minute VWAP prints below 0.9850 USD on the '
            'reference venue at any point in the calendar month. The venue has '
            'halted trading pending a data-feed review; it may reopen.',
        category: 'crypto',
        outcomes: const [
          MarketOutcome(side: Side.yes, label: 'Yes'),
          MarketOutcome(side: Side.no, label: 'No'),
        ],
        status: MarketStatus.paused,
        rawStatus: 'halted',
        opensAt: ago(const Duration(days: 6)),
        closesAt: ahead(const Duration(days: 14)),
        resolvesAt: null,
        resolutionSource: 'Reference venue 1-minute VWAP',
        lastSyncedAt: ago(const Duration(minutes: 40)),
        payloadVersion: 1,
      ),
    ]);

    // Snapshots. `market_paused_depeg` deliberately has none — "no price yet"
    // is a state the detail screen must render without inventing a number.
    _putSnapshot(
      MarketSnapshot(
        id: 'snap_btc_1',
        marketId: 'market_btc_150k',
        yesProbability: 0.38,
        observedAt: ago(const Duration(minutes: 2)),
        source: SnapshotSource.venue,
      ),
    );
    _putSnapshot(
      MarketSnapshot(
        id: 'snap_sol_1',
        marketId: 'market_sol_flip',
        yesProbability: 0.12,
        // Deliberately old: exercises the stale-data treatment.
        observedAt: ago(const Duration(hours: 5)),
        source: SnapshotSource.fixture,
      ),
    );
    _putSnapshot(
      MarketSnapshot(
        id: 'snap_etf_1',
        marketId: 'market_etf_flows',
        yesProbability: 0.61,
        observedAt: ago(const Duration(days: 2)),
        source: SnapshotSource.venue,
      ),
    );
    _putSnapshot(
      MarketSnapshot(
        id: 'snap_fed_1',
        marketId: 'market_fed_cut',
        yesProbability: 0.72,
        observedAt: ago(const Duration(days: 5)),
        source: SnapshotSource.venue,
      ),
    );
    _putSnapshot(
      MarketSnapshot(
        id: 'snap_cancel_1',
        marketId: 'market_cancelled_listing',
        yesProbability: 0.44,
        observedAt: ago(const Duration(days: 8)),
        source: SnapshotSource.venue,
      ),
    );

    // --- Calls -------------------------------------------------------------

    // PENDING, open market, followed author, full composer payload.
    _calls.add(
      Call(
        id: 'call_ada_btc',
        userId: 'user_ada',
        marketId: 'market_btc_150k',
        side: Side.yes,
        confidence: 0.7,
        thesis:
            'Supply on exchanges keeps falling while the ETF bid is steady. '
            'I only need one squeeze week.',
        entryProbability: 0.36,
        snapshotId: 'snap_btc_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(hours: 3)),
        lockedAt: ago(const Duration(hours: 3)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );

    // PENDING, minimal call: no confidence, no thesis.
    _calls.add(
      Call(
        id: 'call_tobi_btc',
        userId: 'user_tobi',
        marketId: 'market_btc_150k',
        side: Side.no,
        confidence: null,
        thesis: null,
        entryProbability: 0.39,
        snapshotId: 'snap_btc_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(hours: 1)),
        lockedAt: ago(const Duration(hours: 1)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );

    // A Fade: Kemi took the other side of Ada's call. Records its parent.
    _calls.add(
      Call(
        id: 'call_kemi_btc_fade',
        userId: 'user_kemi',
        marketId: 'market_btc_150k',
        side: Side.no,
        confidence: 0.55,
        thesis: 'Faded. The ETF bid is already in the price.',
        entryProbability: 0.38,
        snapshotId: 'snap_btc_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(hours: 2)),
        lockedAt: ago(const Duration(hours: 2)),
        parentCallId: 'call_ada_btc',
        fundingState: FundingState.none,
      ),
    );
    _responses.add(
      CallResponse(
        id: 'response_kemi_fade',
        actorUserId: 'user_kemi',
        targetCallId: 'call_ada_btc',
        kind: CallResponseKind.fade,
        resultingCallId: 'call_kemi_btc_fade',
        createdAt: ago(const Duration(hours: 2)),
      ),
    );

    // Followers-only visibility on the demo (fixture) market.
    _calls.add(
      Call(
        id: 'call_zed_sol',
        userId: 'user_zed',
        marketId: 'market_sol_flip',
        side: Side.no,
        confidence: 0.9,
        thesis: null,
        entryProbability: 0.13,
        snapshotId: 'snap_sol_1',
        visibility: CallVisibility.followers,
        createdAt: ago(const Duration(days: 1)),
        lockedAt: ago(const Duration(days: 1)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );

    // Market CLOSED_PENDING_RESOLUTION → stays PENDING. Late resolution is
    // still PENDING; there is no "probably correct".
    _calls.add(
      Call(
        id: 'call_ada_etf',
        userId: 'user_ada',
        marketId: 'market_etf_flows',
        side: Side.yes,
        confidence: 0.6,
        thesis: 'Flows have been positive four weeks running.',
        entryProbability: 0.58,
        snapshotId: 'snap_etf_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(days: 4)),
        lockedAt: ago(const Duration(days: 4)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );

    // RESOLVED YES → viewer CORRECT, Zed INCORRECT.
    _calls.add(
      Call(
        id: 'call_you_fed',
        userId: demoViewerUserId,
        marketId: 'market_fed_cut',
        side: Side.yes,
        confidence: 0.8,
        thesis: 'Labour print gives them all the cover they need.',
        entryProbability: 0.64,
        snapshotId: 'snap_fed_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(days: 12)),
        lockedAt: ago(const Duration(days: 12)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );
    _calls.add(
      Call(
        id: 'call_zed_fed',
        userId: 'user_zed',
        marketId: 'market_fed_cut',
        side: Side.no,
        confidence: null,
        thesis: 'They hold. Inflation is not done.',
        entryProbability: 0.30,
        snapshotId: 'snap_fed_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(days: 11)),
        lockedAt: ago(const Duration(days: 11)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );

    // CANCELLED market → VOID. Never a win, never a loss.
    _calls.add(
      Call(
        id: 'call_kemi_listing',
        userId: 'user_kemi',
        marketId: 'market_cancelled_listing',
        side: Side.yes,
        confidence: 0.45,
        thesis: null,
        entryProbability: 0.44,
        snapshotId: 'snap_cancel_1',
        visibility: CallVisibility.public,
        createdAt: ago(const Duration(days: 14)),
        lockedAt: ago(const Duration(days: 14)),
        parentCallId: null,
        fundingState: FundingState.none,
      ),
    );

    // --- Results (service-derived only) ------------------------------------
    _deriveResult(
      callId: 'call_you_fed',
      resolution: Resolution.yes,
      resolvedAt: ago(const Duration(days: 5)),
      marketResolutionId: 'res_fomc_sep_2026',
    );
    _deriveResult(
      callId: 'call_zed_fed',
      resolution: Resolution.yes,
      resolvedAt: ago(const Duration(days: 5)),
      marketResolutionId: 'res_fomc_sep_2026',
    );
    _deriveResult(
      callId: 'call_kemi_listing',
      resolution: Resolution.voided,
      resolvedAt: ago(const Duration(days: 8)),
      marketResolutionId: 'res_listing_void',
    );

    // --- An invitation already waiting for the viewer ----------------------
    _responses.add(
      CallResponse(
        id: 'response_zed_challenge',
        actorUserId: 'user_zed',
        targetCallId: 'call_you_fed',
        kind: CallResponseKind.challenge,
        resultingCallId: null,
        createdAt: ago(const Duration(days: 4)),
      ),
    );
    _invitations.add(
      ChallengeInvitation(
        id: 'invite_zed_you',
        fromUserId: 'user_zed',
        toUserId: demoViewerUserId,
        // As the BFF derives it: the market of the call that was dared.
        marketId: 'market_fed_cut',
        sourceCallId: 'call_you_fed',
        responseId: 'response_zed_challenge',
        note: 'Rematch. Go on record on BTC.',
        createdAt: ago(const Duration(days: 4)),
      ),
    );
  }

  void _putSnapshot(MarketSnapshot snapshot) {
    _snapshots[snapshot.marketId] = snapshot;
  }

  void _deriveResult({
    required String callId,
    required Resolution? resolution,
    required int? resolvedAt,
    required String? marketResolutionId,
  }) {
    final call = _calls.firstWhere((c) => c.id == callId);
    _results[callId] = CallResult(
      callId: callId,
      outcome: deriveCallOutcome(side: call.side, resolution: resolution),
      resolution: resolution,
      resolvedAt: resolvedAt,
      marketResolutionId: marketResolutionId,
      derivedAt: _nowMs,
    );
  }

  // -------------------------------------------------------------------------
  // Plumbing
  // -------------------------------------------------------------------------

  Future<void> _gate() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (simulateOffline) throw const CallsOfflineException();
    if (simulateFailure) throw const CallsFailure();
  }

  Person _personById(String id) => _people.firstWhere(
    (p) => p.id == id,
    orElse: () => Person(id: id, handle: id, displayName: id),
  );

  VenueMarket _marketById(String id) => _markets.firstWhere(
    (m) => m.id == id,
    orElse: () => throw CallsRejectedException('Unknown market: $id'),
  );

  Call _callById(String id) => _calls.firstWhere(
    (c) => c.id == id,
    orElse: () => throw const CallsRejectedException('That call no longer exists.'),
  );

  bool _viewerCanSee(Call call, String? viewerUserId) {
    if (call.visibility == CallVisibility.public) return true;
    if (viewerUserId == null) return false;
    if (call.userId == viewerUserId) return true;
    // In the mock the only viewer is the demo user, whose follow set is local.
    return _viewerFollows.contains(call.userId);
  }

  bool _hasLockedCall(String marketId, String? viewerUserId) =>
      viewerUserId != null &&
      _calls.any((c) => c.marketId == marketId && c.userId == viewerUserId);

  CallFeedEntry _entryFor(Call call, String? viewerUserId) {
    final responses = _responses.where((r) => r.targetCallId == call.id);
    return CallFeedEntry(
      call: call,
      author: _personById(call.userId),
      market: _marketById(call.marketId),
      result: _results[call.id],
      backCount: responses.where((r) => r.kind == CallResponseKind.back).length,
      fadeCount: responses.where((r) => r.kind == CallResponseKind.fade).length,
      viewerHasCalled: _hasLockedCall(call.marketId, viewerUserId),
    );
  }

  String _requireViewer(String? viewerUserId) {
    if (viewerUserId == null || viewerUserId.isEmpty) {
      throw const CallsSignedOutException();
    }
    return viewerUserId;
  }

  // -------------------------------------------------------------------------
  // CallsRepository
  // -------------------------------------------------------------------------

  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    await _gate();

    final visible =
        _calls
            .where((call) => _viewerCanSee(call, viewerUserId))
            .where(
              (call) =>
                  mode == CallFeedMode.global ||
                  _viewerFollows.contains(call.userId),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final slice = visible.skip(start).take(limit).toList(growable: false);
    final nextIndex = start + slice.length;

    return CallFeedPage(
      entries:
          slice.map((call) => _entryFor(call, viewerUserId)).toList(growable: false),
      nextCursor: nextIndex < visible.length ? '$nextIndex' : null,
      servedAt: _nowMs,
    );
  }

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) async {
    await _gate();
    return _markets
        .where((m) => m.status.acceptsNewCalls)
        .where((m) => category == null || m.category == category)
        .toList(growable: false);
  }

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    await _gate();
    final market = _marketById(marketId);
    Call? ownCall;
    if (viewerUserId != null) {
      for (final call in _calls) {
        if (call.marketId == marketId && call.userId == viewerUserId) {
          ownCall = call;
          break;
        }
      }
    }
    final viewerCall =
        ownCall == null ? null : _entryFor(ownCall, viewerUserId);

    // The crowd split is withheld until the viewer has locked their own call.
    // Enforced here so no screen can render it early.
    CrowdSplit? split;
    if (viewerCall != null) {
      final onMarket = _calls.where((c) => c.marketId == marketId);
      split = CrowdSplit(
        marketId: marketId,
        yesCalls: onMarket.where((c) => c.side == Side.yes).length,
        noCalls: onMarket.where((c) => c.side == Side.no).length,
      );
    }

    return MarketDetail(
      market: market,
      snapshot: _snapshots[marketId],
      viewerCall: viewerCall,
      crowdSplit: split,
      servedAt: _nowMs,
    );
  }

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async {
    await _gate();
    final call = _callById(callId);
    if (!_viewerCanSee(call, viewerUserId)) {
      throw const CallsRejectedException(
        'This call is only visible to its author\'s followers.',
      );
    }
    final parentId = call.parentCallId;
    return CallDetail(
      entry: _entryFor(call, viewerUserId),
      parent:
          parentId == null
              ? null
              : _entryFor(_callById(parentId), viewerUserId),
      responses:
          _responses
              .where((r) => r.targetCallId == callId)
              .toList(growable: false),
    );
  }

  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) async {
    await _gate();
    final normalized =
        personRef.startsWith('@') ? personRef.substring(1) : personRef;
    final person = _people.firstWhere(
      (p) =>
          p.id == normalized ||
          p.handle.toLowerCase() == normalized.toLowerCase() ||
          p.walletAddress == normalized,
      orElse: () => throw const CallsRejectedException('No such person.'),
    );
    final calls =
        _calls
            .where((c) => c.userId == person.id)
            .where((c) => _viewerCanSee(c, viewerUserId))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return PersonDetail(
      person: person,
      calls:
          calls.map((c) => _entryFor(c, viewerUserId)).toList(growable: false),
      viewerIsFollowing: viewerUserId != null &&
          viewerUserId != person.id && _viewerFollows.contains(person.id),
      servedAt: _nowMs,
    );
  }

  @override
  Future<bool> setFollowing({
    required String personId,
    required bool following,
    required String? viewerUserId,
  }) async {
    if (viewerUserId == null) throw const CallsSignedOutException();
    if (viewerUserId == personId) {
      throw const CallsRejectedException("You can't follow yourself.");
    }
    await _gate();
    if (!_people.any((p) => p.id == personId)) {
      throw const CallsRejectedException('No such person.');
    }
    if (following) {
      _viewerFollows.add(personId);
    } else {
      _viewerFollows.remove(personId);
    }
    return following;
  }

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) async {
    await _gate();
    final userId = _requireViewer(viewerUserId);

    final invalid = input.validate();
    if (invalid != null) throw CallsRejectedException(invalid);

    final market = _marketById(input.marketId);
    if (!market.status.acceptsNewCalls) {
      throw CallsRejectedException(
        'This market is ${market.status.label.toLowerCase()} — no new calls.',
      );
    }

    final snapshot = _snapshots[market.id];
    final now = _nowMs;
    final call = Call(
      id: _nextId('call'),
      userId: userId,
      marketId: market.id,
      side: input.side,
      confidence: input.confidence,
      thesis: input.thesis,
      // Pinned from the snapshot the user actually saw. Immutable from here.
      entryProbability: snapshot?.probabilityFor(input.side),
      snapshotId: input.snapshotId ?? snapshot?.id,
      visibility: input.visibility,
      createdAt: now,
      lockedAt: now,
      parentCallId: input.parentCallId,
      fundingState: FundingState.none,
    );
    _calls.add(call);
    return _entryFor(call, userId);
  }

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async {
    await _gate();
    final actorId = _requireViewer(viewerUserId);
    final target = _callById(input.targetCallId);

    if (target.userId == actorId) {
      throw const CallsRejectedException('You can\'t respond to your own call.');
    }

    final now = _nowMs;

    if (input.kind == CallResponseKind.challenge) {
      // A challenge is an invitation to go on record. No call is minted for
      // the actor, and there is no escrow, no amount and no transaction.
      final response = CallResponse(
        id: _nextId('response'),
        actorUserId: actorId,
        targetCallId: target.id,
        kind: CallResponseKind.challenge,
        resultingCallId: null,
        createdAt: now,
      );
      _responses.add(response);
      final invitation = ChallengeInvitation(
        id: _nextId('invite'),
        fromUserId: actorId,
        toUserId: target.userId,
        marketId: target.marketId,
        sourceCallId: target.id,
        responseId: response.id,
        // As the server does: a challenge's words are its note.
        note: input.dareNote,
        createdAt: now,
      );
      _invitations.add(invitation);
      return CallResponseResult(response: response, invitation: invitation);
    }

    // Back and Fade both mint the responder's OWN immutable call.
    final side =
        input.kind == CallResponseKind.back ? target.side : target.side.opposite;

    final own = await createCall(
      input: CreateCallInput(
        marketId: target.marketId,
        side: side,
        confidence: input.confidence,
        thesis: input.thesis,
        visibility: input.visibility,
        parentCallId: target.id,
      ),
      viewerUserId: actorId,
    );

    final response = CallResponse(
      id: _nextId('response'),
      actorUserId: actorId,
      targetCallId: target.id,
      kind: input.kind,
      resultingCallId: own.call.id,
      createdAt: now,
    );
    _responses.add(response);

    return CallResponseResult(response: response, resultingCall: own);
  }

  @override
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  }) async {
    await _gate();
    if (viewerUserId == null) return const [];
    return _invitations
        .where((i) => i.toUserId == viewerUserId)
        .toList(growable: false);
  }

  @override
  String shareLinkForCall(String callId) => '$_linkHost/c/$callId';

  @override
  String shareLinkForPerson(String handleOrId) => '$_linkHost/u/$handleOrId';

  // -------------------------------------------------------------------------
  // Test / demo helpers
  // -------------------------------------------------------------------------

  /// Resolve a market from "venue evidence" and derive every affected result.
  /// Only ever called by tests and the demo affordance — a client never writes
  /// a resolution in production (invariant 2).
  void debugResolveMarket({
    required String marketId,
    required Resolution resolution,
  }) {
    final index = _markets.indexWhere((m) => m.id == marketId);
    if (index < 0) return;
    _markets[index] = _markets[index].copyWith(
      status:
          resolution == Resolution.voided
              ? MarketStatus.cancelled
              : MarketStatus.resolved,
      lastSyncedAt: _nowMs,
    );
    for (final call in _calls.where((c) => c.marketId == marketId)) {
      _deriveResult(
        callId: call.id,
        resolution: resolution,
        resolvedAt: _nowMs,
        marketResolutionId: 'res_$marketId',
      );
    }
  }

  /// Empty-state helper: drop every seeded call.
  void debugClearCalls() {
    _calls.clear();
    _results.clear();
    _responses.clear();
    _invitations.clear();
  }

  List<Person> get debugPeople => List.unmodifiable(_people);
  List<VenueMarket> get debugMarkets => List.unmodifiable(_markets);
  List<Call> get debugCalls => List.unmodifiable(_calls);
  List<CallResponse> get debugResponses => List.unmodifiable(_responses);
}
