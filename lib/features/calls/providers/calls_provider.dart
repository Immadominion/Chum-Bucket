/// State + orchestration for the call slice.
///
/// Registered nowhere yet — the integration owner wires it into `main.dart`
/// (see `docs/contracts/integration-requests/packet-c.md`). It depends on a
/// [CallsRepository], not on a transport, so swapping [MockCallsRepository] for
/// Packet B's BFF implementation changes one constructor argument.
///
/// Caching follows the arena patterns verbatim:
/// * per-key guard on `containsKey || inFlight` unless `force`
///   (`arena_provider.dart:640-666`)
/// * batch fetch that skips anything cached or already in flight
///   (`arena_provider.dart:704-730`)
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';

/// The states every list surface in this slice must be able to reach.
enum CallsLoadState {
  /// Nothing requested yet.
  idle,

  /// First load in flight, nothing to show underneath.
  loading,

  /// Loaded and non-empty.
  ready,

  /// Loaded and genuinely empty — not an error.
  empty,

  /// The last attempt failed and there is nothing cached to fall back to.
  error,

  /// No connection. Any content shown alongside this is cached, not live.
  offline,
}

class CallsProvider extends ChangeNotifier {
  CallsProvider({
    required CallsRepository repository,
    DateTime Function()? clock,
    this.staleAfter = const Duration(minutes: 2),
    AnalyticsRecorder? analytics,
  }) : _repository = repository,
       _clock = clock ?? DateTime.now,
       _analytics = analytics ?? AnalyticsRecorder.instance;

  final CallsRepository _repository;
  final DateTime Function() _clock;

  /// Instrumentation for the §9 people-first vs market-first experiment.
  ///
  /// Defaults to the ambient recorder, which writes to a bounded in-memory
  /// sink and **sends nothing anywhere**. Injected in tests. Every emission
  /// below is fire-and-forget: `AnalyticsRecorder.record` cannot throw, so no
  /// read, call or response can fail because of analytics.
  final AnalyticsRecorder _analytics;

  /// Exposed so a screen reports impressions against the same recorder — and
  /// therefore the same session dedupe store and the same treatment — rather
  /// than reaching for the ambient one and diverging from this provider's
  /// viewer.
  AnalyticsRecorder get analytics => _analytics;

  /// Analytics timestamps come from the same injected clock as everything else
  /// in this provider, so a test that controls time controls them too.
  int get _analyticsNowMs => _clock().toUtc().millisecondsSinceEpoch;

  /// How old served data may be before the UI must say so.
  final Duration staleAfter;

  bool _disposed = false;
  final Map<String, Object> _requests = {};
  final Set<String> _followsInFlight = {};

  Object _beginRequest(String key) => _requests[key] = Object();

  bool _isCurrent(String key, Object request) =>
      !_disposed && identical(_requests[key], request);

  static const _accountChanged = CallsRejectedException(
    'Your account changed while this request was in progress. '
    'It may have completed for the previous account; check that account before retrying.',
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  String? _viewerUserId;

  /// The canonical `public.users.id` of the signed-in person, or null.
  /// **Never a wallet.** The whole slice reads fine while this is null; only
  /// writing requires it.
  String? get viewerUserId => _viewerUserId;

  bool get isSignedIn => _viewerUserId != null && _viewerUserId!.isNotEmpty;

  /// Called by the shell when the session changes. Clears every viewer-scoped
  /// cache so a second account never sees the first one's rows.
  void setViewer(String? userId) {
    if (_viewerUserId == userId) return;
    _viewerUserId = userId;
    // Invalidates successes AND errors already in flight. Clearing a cache
    // alone lets a response authorized for the previous viewer refill it.
    _requests.clear();
    _isLoadingFeed = false;
    _isLoadingMore = false;
    _isLoadingOpenMarkets = false;
    _isLoadingInvitations = false;
    _isSubmitting = false;
    _marketsInFlight.clear();
    _callsInFlight.clear();
    _peopleInFlight.clear();
    _followsInFlight.clear();
    _marketErrors.clear();
    _callErrors.clear();
    _personErrors.clear();
    _openMarketsError = null;
    _feedFromCache = false;
    // Binds the experiment unit to the canonical `public.users.id` — never a
    // wallet (contract §0.3). The id is hashed to an arm and is never itself
    // recorded. Also clears the impression dedupe so the next account's first
    // impressions are not swallowed as the previous account's duplicates.
    _analytics.setUnit(userId);
    _feedEntries = const [];
    _feedServedAt = null;
    _feedNextCursor = null;
    _marketDetails.clear();
    _callDetails.clear();
    _personDetails.clear();
    _invitations = const [];
    _feedError = null;
    _isOffline = false;
    _notify();
  }

  // -------------------------------------------------------------------------
  // Feed
  // -------------------------------------------------------------------------

  CallFeedMode _feedMode = CallFeedMode.global;
  List<CallFeedEntry> _feedEntries = const [];
  bool _isLoadingFeed = false;
  bool _isLoadingMore = false;
  String? _feedError;
  int? _feedServedAt;
  String? _feedNextCursor;
  bool _isOffline = false;
  bool _feedFromCache = false;

  CallFeedMode get feedMode => _feedMode;
  List<CallFeedEntry> get feed => List.unmodifiable(_feedEntries);
  bool get isLoadingFeed => _isLoadingFeed;
  bool get isLoadingMore => _isLoadingMore;
  String? get feedError => _feedError;
  bool get hasMore => _feedNextCursor != null;

  /// True when the last read failed because the device or BFF was unreachable.
  /// Anything rendered while this is true is cached, and must say so.
  bool get isOffline => _isOffline;

  bool get isFeedFromCache => _feedFromCache;

  DateTime? get feedServedAtUtc =>
      _feedServedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_feedServedAt!, isUtc: true);

  /// How old the currently-rendered feed is. Null before the first success.
  Duration? get feedAge {
    final servedAt = feedServedAtUtc;
    if (servedAt == null) return null;
    final age = _clock().toUtc().difference(servedAt);
    return age.isNegative ? Duration.zero : age;
  }

  /// Data is on screen but older than [staleAfter]. Not an error — the UI says
  /// "last updated N ago" and offers a refresh.
  bool get isFeedStale {
    final age = feedAge;
    return age != null && age > staleAfter;
  }

  CallsLoadState get feedState {
    if (_isLoadingFeed && _feedEntries.isEmpty) return CallsLoadState.loading;
    if (_isOffline && _feedEntries.isEmpty) return CallsLoadState.offline;
    if (_feedError != null && _feedEntries.isEmpty) return CallsLoadState.error;
    if (_feedServedAt == null && _feedEntries.isEmpty) {
      return CallsLoadState.idle;
    }
    if (_feedEntries.isEmpty) return CallsLoadState.empty;
    return CallsLoadState.ready;
  }

  /// Switching the tab is one branch, exactly as `ArenaFeedMode` is.
  Future<void> setFeedMode(CallFeedMode mode) async {
    if (_feedMode == mode) return;
    _feedMode = mode;
    _requests.remove('feed');
    _requests.remove('more');
    _isLoadingFeed = false;
    _isLoadingMore = false;
    _feedEntries = const [];
    _feedServedAt = null;
    _feedNextCursor = null;
    _notify();
    await loadFeed(force: true);
  }

  Future<void> loadFeed({bool force = false}) async {
    if (_isLoadingFeed) return;
    if (!force && _feedServedAt != null && !isFeedStale) return;

    final request = _beginRequest('feed');
    _isLoadingFeed = true;
    _feedError = null;
    _notify();
    try {
      final page = await _repository.fetchFeed(
        mode: _feedMode,
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent('feed', request)) return;
      _feedEntries = page.entries;
      _feedServedAt = page.servedAt;
      _feedNextCursor = page.nextCursor;
      _feedFromCache = page.fromCache;
      _isOffline = false;
    } on CallsOfflineException catch (e) {
      if (!_isCurrent('feed', request)) return;
      // Keep whatever is already on screen; it is now explicitly cached.
      developer.log('CallsProvider.loadFeed offline: $e');
      _isOffline = true;
      _feedFromCache = _feedEntries.isNotEmpty;
      _feedError = e.message;
    } on CallsException catch (e) {
      if (!_isCurrent('feed', request)) return;
      developer.log('CallsProvider.loadFeed failed: $e');
      _feedError = e.message;
    } catch (e) {
      if (!_isCurrent('feed', request)) return;
      developer.log('CallsProvider.loadFeed failed: $e');
      _feedError = const CallsFailure().message;
    } finally {
      if (_isCurrent('feed', request)) {
        _requests.remove('feed');
        _isLoadingFeed = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _feedNextCursor;
    if (cursor == null || _isLoadingMore || _isLoadingFeed) return;
    final request = _beginRequest('more');
    _isLoadingMore = true;
    _notify();
    try {
      final page = await _repository.fetchFeed(
        mode: _feedMode,
        viewerUserId: _viewerUserId,
        cursor: cursor,
      );
      if (!_isCurrent('more', request)) return;
      _feedEntries = [..._feedEntries, ...page.entries];
      _feedNextCursor = page.nextCursor;
      _isOffline = false;
    } on CallsOfflineException {
      if (!_isCurrent('more', request)) return;
      _isOffline = true;
    } on CallsException catch (e) {
      if (!_isCurrent('more', request)) return;
      developer.log('CallsProvider.loadMore failed: $e');
    } finally {
      if (_isCurrent('more', request)) {
        _requests.remove('more');
        _isLoadingMore = false;
        _notify();
      }
    }
  }

  // -------------------------------------------------------------------------
  // Markets — per-key cache (arena_provider.dart:640-666)
  // -------------------------------------------------------------------------

  final Map<String, MarketDetail> _marketDetails = {};
  final Set<String> _marketsInFlight = {};
  final Map<String, String> _marketErrors = {};

  List<VenueMarket> _openMarkets = const [];
  bool _isLoadingOpenMarkets = false;
  String? _openMarketsError;

  List<VenueMarket> get openMarkets {
    final now = _clock().millisecondsSinceEpoch;
    // An upstream OPEN label can outlive its deadline between polling passes.
    // Recheck on each read, including a catalog cached before the close.
    return List.unmodifiable(
      _openMarkets.where(
        (market) =>
            market.status.acceptsNewCalls &&
            (market.opensAt == null || market.opensAt! <= now) &&
            (market.closesAt == null || market.closesAt! > now),
      ),
    );
  }

  bool get isLoadingOpenMarkets => _isLoadingOpenMarkets;
  String? get openMarketsError => _openMarketsError;

  MarketDetail? marketDetail(String marketId) => _marketDetails[marketId];
  bool isLoadingMarket(String marketId) => _marketsInFlight.contains(marketId);
  String? marketError(String marketId) => _marketErrors[marketId];

  Future<void> loadOpenMarkets({bool force = false}) async {
    if (_isLoadingOpenMarkets) return;
    if (!force && _openMarkets.isNotEmpty) return;
    final request = _beginRequest('catalog');
    _isLoadingOpenMarkets = true;
    _openMarketsError = null;
    _notify();
    try {
      final repository = _repository;
      final markets =
          repository is CallsCatalogRepository
              ? await (repository as CallsCatalogRepository)
                  .fetchMarketCatalog()
              : await repository.fetchOpenMarkets();
      if (!_isCurrent('catalog', request)) return;
      _openMarkets = markets;
      _isOffline = false;
    } on CallVocabularyException {
      if (!_isCurrent('catalog', request)) return;
      _openMarketsError =
          'The market data format changed. Please update the app or try again later.';
    } on CallsOfflineException catch (e) {
      if (!_isCurrent('catalog', request)) return;
      _isOffline = true;
      _openMarketsError = e.message;
    } on CallsException catch (e) {
      if (!_isCurrent('catalog', request)) return;
      _openMarketsError = e.message;
    } finally {
      if (_isCurrent('catalog', request)) {
        _requests.remove('catalog');
        _isLoadingOpenMarkets = false;
        _notify();
      }
    }
  }

  Future<MarketDetail?> loadMarketDetail(
    String marketId, {
    bool force = false,
  }) async {
    if (!force &&
        (_marketDetails.containsKey(marketId) ||
            _marketsInFlight.contains(marketId))) {
      return _marketDetails[marketId];
    }

    final key = 'market:$marketId';
    final request = _beginRequest(key);
    _marketsInFlight.add(marketId);
    _marketErrors.remove(marketId);
    _notify();
    try {
      final detail = await _repository.fetchMarketDetail(
        marketId: marketId,
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent(key, request)) return null;
      _marketDetails[marketId] = detail;
      _isOffline = false;
      return detail;
    } on CallsOfflineException catch (e) {
      if (!_isCurrent(key, request)) return null;
      _isOffline = true;
      _marketErrors[marketId] = e.message;
      return _marketDetails[marketId];
    } on CallsException catch (e) {
      if (!_isCurrent(key, request)) return null;
      developer.log('CallsProvider.loadMarketDetail failed: $e');
      _marketErrors[marketId] = e.message;
      return null;
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _marketsInFlight.remove(marketId);
        _notify();
      }
    }
  }

  /// How old a market's price is, for the "data age" line. Null when the
  /// market has never been synced with a price.
  Duration? snapshotAge(String marketId) {
    final snapshot = _marketDetails[marketId]?.snapshot;
    if (snapshot == null) return null;
    return snapshot.ageAt(_clock());
  }

  bool isSnapshotStale(String marketId) {
    final age = snapshotAge(marketId);
    return age != null && age > staleAfter;
  }

  // -------------------------------------------------------------------------
  // Calls and people — same per-key cache
  // -------------------------------------------------------------------------

  final Map<String, CallDetail> _callDetails = {};
  final Set<String> _callsInFlight = {};
  final Map<String, String> _callErrors = {};

  final Map<String, PersonDetail> _personDetails = {};
  final Set<String> _peopleInFlight = {};
  final Map<String, String> _personErrors = {};

  CallDetail? callDetail(String callId) => _callDetails[callId];
  bool isLoadingCall(String callId) => _callsInFlight.contains(callId);
  String? callError(String callId) => _callErrors[callId];

  PersonDetail? personDetail(String ref) => _personDetails[ref];
  bool isLoadingPerson(String ref) => _peopleInFlight.contains(ref);
  String? personError(String ref) => _personErrors[ref];

  /// Loads one call.
  ///
  /// [surface] says where the open came from — a deep link landing and a tap
  /// in the feed are different facts, and §9 needs to tell them apart.
  /// [reportOpen] exists for the one caller that is not an open: pre-warming a
  /// cache is not somebody looking at a call.
  Future<CallDetail?> loadCall(
    String callId, {
    bool force = false,
    AnalyticsSurface surface = AnalyticsSurface.callDetail,
    bool reportOpen = true,
  }) async {
    // Emitted before the cache check on purpose: re-opening a call already in
    // the cache is still an open, and it is exactly the return behaviour the
    // experiment is looking for.
    if (reportOpen) {
      final cached = _callDetails[callId];
      _analytics.record(
        AnalyticsEvents.callOpened(
          callId: callId,
          surface: surface,
          marketId: cached?.entry.market.id,
          authorId: cached?.entry.author.id,
          side: cached?.entry.call.side.wire,
          outcome: cached?.entry.outcome.wire,
          viewerIsSignedIn: isSignedIn,
          occurredAtMs: _analyticsNowMs,
        ),
      );
    }

    if (!force &&
        (_callDetails.containsKey(callId) || _callsInFlight.contains(callId))) {
      return _callDetails[callId];
    }
    final key = 'call:$callId';
    final request = _beginRequest(key);
    _callsInFlight.add(callId);
    _callErrors.remove(callId);
    _notify();
    try {
      final detail = await _repository.fetchCall(
        callId: callId,
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent(key, request)) return null;
      _callDetails[callId] = detail;
      _isOffline = false;
      return detail;
    } on CallsOfflineException catch (e) {
      if (!_isCurrent(key, request)) return null;
      _isOffline = true;
      _callErrors[callId] = e.message;
      return _callDetails[callId];
    } on CallsException catch (e) {
      if (!_isCurrent(key, request)) return null;
      developer.log('CallsProvider.loadCall failed: $e');
      _callErrors[callId] = e.message;
      return null;
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _callsInFlight.remove(callId);
        _notify();
      }
    }
  }

  Future<PersonDetail?> loadPerson(String ref, {bool force = false}) async {
    if (!force &&
        (_personDetails.containsKey(ref) || _peopleInFlight.contains(ref))) {
      return _personDetails[ref];
    }
    final key = 'person:$ref';
    final request = _beginRequest(key);
    _peopleInFlight.add(ref);
    _personErrors.remove(ref);
    _notify();
    try {
      final detail = await _repository.fetchPerson(
        personRef: ref,
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent(key, request)) return null;
      _personDetails[ref] = detail;
      _isOffline = false;
      return detail;
    } on CallsOfflineException catch (e) {
      if (!_isCurrent(key, request)) return null;
      _isOffline = true;
      _personErrors[ref] = e.message;
      return _personDetails[ref];
    } on CallsException catch (e) {
      if (!_isCurrent(key, request)) return null;
      developer.log('CallsProvider.loadPerson failed: $e');
      _personErrors[ref] = e.message;
      return null;
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _peopleInFlight.remove(ref);
        _notify();
      }
    }
  }

  bool isFollowBusy(String personId) => _followsInFlight.contains(personId);

  /// Change one canonical person edge. Never optimistically claim a follow:
  /// the BFF must acknowledge its durable write before the UI changes state.
  Future<bool> setFollowing(PersonDetail detail, bool following) async {
    final viewer = _viewerUserId;
    if (viewer == null || viewer.isEmpty) throw const CallsSignedOutException();
    final personId = detail.person.id;
    if (personId == viewer) {
      throw const CallsRejectedException("You can't follow yourself.");
    }
    if (_followsInFlight.contains(personId)) {
      throw const CallsRejectedException(
        'That follow is already being updated.',
      );
    }
    final key = 'follow:$personId';
    final request = _beginRequest(key);
    _followsInFlight.add(personId);
    _notify();
    try {
      final confirmed = await _repository.setFollowing(
        personId: personId,
        following: following,
        viewerUserId: viewer,
      );
      if (!_isCurrent(key, request)) throw _accountChanged;
      for (final ref in _personDetails.keys.toList()) {
        final cached = _personDetails[ref];
        if (cached?.person.id != personId) continue;
        _personDetails[ref] = PersonDetail(
          person: cached!.person,
          calls:
              confirmed
                  ? cached.calls
                  : cached.calls
                      .where(
                        (entry) =>
                            entry.call.visibility == CallVisibility.public,
                      )
                      .toList(),
          viewerIsFollowing: confirmed,
          servedAt: cached.servedAt,
        );
      }
      if (!confirmed) {
        _callDetails.removeWhere(
          (_, cached) =>
              cached.entry.author.id == personId &&
              cached.entry.call.visibility == CallVisibility.followers,
        );
      }
      // A follow changes BOTH Following membership and Global visibility of
      // followers-only calls. Invalidate old pages and in-flight pagination so
      // an unfollow never leaves a private row visible from a stale cache.
      _requests.remove('feed');
      _requests.remove('more');
      _isLoadingFeed = false;
      _isLoadingMore = false;
      _feedEntries = const [];
      _feedServedAt = null;
      _feedNextCursor = null;
      _notify();
      await loadPerson(personId, force: true);
      await loadFeed(force: true);
      return confirmed;
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _followsInFlight.remove(personId);
        _notify();
      }
    }
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  /// Locks a new free call. Rethrows so the composer can show the reason
  /// inline; [CallsSignedOutException] is the signed-out path.
  Future<CallFeedEntry> createCall(
    CreateCallInput input, {
    AnalyticsSurface? surface,
  }) async {
    if (_isSubmitting) {
      throw const CallsRejectedException('Already locking a call.');
    }
    final request = _beginRequest('submit');
    _isSubmitting = true;
    _notify();
    try {
      final entry = await _repository.createCall(
        input: input,
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent('submit', request)) throw _accountChanged;
      _onCallCreated(entry, surface: surface);
      return entry;
    } catch (_) {
      if (!_isCurrent('submit', request)) throw _accountChanged;
      rethrow;
    } finally {
      if (_isCurrent('submit', request)) {
        _requests.remove('submit');
        _isSubmitting = false;
        _notify();
      }
    }
  }

  /// Back, Fade or Challenge. Back and Fade return the actor's own new call.
  Future<CallResponseResult> respondToCall(
    RespondToCallInput input, {
    AnalyticsSurface? surface,
  }) async {
    if (_isSubmitting) {
      throw const CallsRejectedException('Already sending that.');
    }
    final request = _beginRequest('submit');
    _isSubmitting = true;
    _notify();
    try {
      final result = await _repository.respondToCall(
        input: input,
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent('submit', request)) throw _accountChanged;
      final own = result.resultingCall;
      // Order matters: the response event names the relationship, the call
      // event counts the call. §9 needs both — "30% of new calls originate
      // from another person's Back/Fade card" is the ratio between them.
      _recordResponse(input: input, result: result, surface: surface);
      if (own != null) {
        _onCallCreated(
          own,
          viaResponse: result.response.kind,
          surface: surface,
        );
      }
      // The target's back/fade counter moved; drop its cached detail.
      _callDetails.remove(input.targetCallId);
      return result;
    } catch (_) {
      if (!_isCurrent('submit', request)) throw _accountChanged;
      rethrow;
    } finally {
      if (_isCurrent('submit', request)) {
        _requests.remove('submit');
        _isSubmitting = false;
        _notify();
      }
    }
  }

  void _onCallCreated(
    CallFeedEntry entry, {
    CallResponseKind? viaResponse,
    AnalyticsSurface? surface,
  }) {
    _feedEntries = [entry, ..._feedEntries];
    // The viewer now has a locked call on this market, so the crowd split
    // becomes available — force a refetch rather than synthesising it here.
    _marketDetails.remove(entry.market.id);

    final call = entry.call;
    _analytics.record(
      AnalyticsEvents.callCreated(
        callId: call.id,
        marketId: entry.market.id,
        side: call.side.wire,
        visibility: call.visibility.wire,
        fromResponse: viaResponse != null || call.parentCallId != null,
        responseKind: viaResponse?.wire,
        parentCallId: call.parentCallId,
        confidencePresent: call.confidence != null,
        // The thesis text itself never leaves the composer. Only whether one
        // exists and roughly how long it was.
        thesisPresent: call.thesis != null && call.thesis!.trim().isNotEmpty,
        thesisLengthBucket: ThesisLengthBucket.of(call.thesis),
        entryProbability: call.entryProbability,
        surface: surface,
        occurredAtMs: _analyticsNowMs,
      ),
    );
  }

  void _recordResponse({
    required RespondToCallInput input,
    required CallResponseResult result,
    AnalyticsSurface? surface,
  }) {
    final response = result.response;
    final own = result.resultingCall;
    switch (response.kind) {
      case CallResponseKind.back:
        _analytics.record(
          AnalyticsEvents.callBacked(
            responseId: response.id,
            targetCallId: input.targetCallId,
            resultingCallId: own?.call.id,
            marketId: own?.market.id,
            side: own?.call.side.wire,
            surface: surface,
            occurredAtMs: _analyticsNowMs,
          ),
        );
      case CallResponseKind.fade:
        _analytics.record(
          AnalyticsEvents.callFaded(
            responseId: response.id,
            targetCallId: input.targetCallId,
            resultingCallId: own?.call.id,
            marketId: own?.market.id,
            side: own?.call.side.wire,
            surface: surface,
            occurredAtMs: _analyticsNowMs,
          ),
        );
      case CallResponseKind.challenge:
        // A challenge creates no call for the actor and carries no escrow, so
        // there is nothing money-shaped to record and no resulting call id.
        _analytics.record(
          AnalyticsEvents.challengeSent(
            responseId: response.id,
            targetCallId: input.targetCallId,
            marketId: result.invitation?.marketId,
            personId: result.invitation?.toUserId,
            surface: surface,
            occurredAtMs: _analyticsNowMs,
          ),
        );
    }
  }

  // -------------------------------------------------------------------------
  // Invitations
  // -------------------------------------------------------------------------

  List<ChallengeInvitation> _invitations = const [];
  bool _isLoadingInvitations = false;

  List<ChallengeInvitation> get invitations => List.unmodifiable(_invitations);
  bool get isLoadingInvitations => _isLoadingInvitations;

  Future<void> loadInvitations({bool force = false}) async {
    if (_isLoadingInvitations) return;
    if (!force && _invitations.isNotEmpty) return;
    final request = _beginRequest('invitations');
    _isLoadingInvitations = true;
    _notify();
    try {
      final invitations = await _repository.fetchInvitations(
        viewerUserId: _viewerUserId,
      );
      if (!_isCurrent('invitations', request)) return;
      _invitations = invitations;
    } on CallsException catch (e) {
      if (!_isCurrent('invitations', request)) return;
      developer.log('CallsProvider.loadInvitations failed: $e');
    } finally {
      if (_isCurrent('invitations', request)) {
        _requests.remove('invitations');
        _isLoadingInvitations = false;
        _notify();
      }
    }
  }

  // -------------------------------------------------------------------------
  // Sharing
  // -------------------------------------------------------------------------

  String shareLinkForCall(String callId) =>
      _repository.shareLinkForCall(callId);

  String shareLinkForPerson(String handleOrId) =>
      _repository.shareLinkForPerson(handleOrId);

  /// Exposed so the deep-link resolver can reach the same repository without a
  /// second source of truth.
  CallsRepository get repository => _repository;
}
