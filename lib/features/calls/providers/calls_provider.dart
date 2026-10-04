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
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_repository.dart';
import 'package:chumbucket/features/people/data/person_finder.dart';

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

  /// How old served data may be before a plain [loadFeed] reads it again.
  /// The UI never shows the age; it refreshes silently.
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
    _snapshots?.bindSnapshotViewer(userId);
    _feedByMode.clear();
    // Invalidates successes AND errors already in flight. Clearing a cache
    // alone lets a response authorized for the previous viewer refill it.
    // The open catalog is the exception: it is the same for every viewer, and
    // Markets starts loading it at launch, before the restored session lands
    // here. Cancelling that load left Markets empty until a manual refresh.
    final catalogLoad = _requests['catalog'];
    _requests.clear();
    if (catalogLoad != null) _requests['catalog'] = catalogLoad;
    _isLoadingFeed = false;
    _isLoadingMore = false;
    _isLoadingInvitations = false;
    _isSubmitting = false;
    _marketsInFlight.clear();
    _callsInFlight.clear();
    _peopleInFlight.clear();
    _followsInFlight.clear();
    _marketErrors.clear();
    _callErrors.clear();
    _personErrors.clear();
    _feedFromCache = false;
    _clearPeople();
    // Binds the experiment unit to the canonical `public.users.id` — never a
    // wallet (contract §0.3). The id is hashed to an arm and is never itself
    // recorded. Also clears the impression dedupe so the next account's first
    // impressions are not swallowed as the previous account's duplicates.
    _analytics.setUnit(userId);
    _feedEntries = const [];
    _feedServedAt = null;
    _feedNextCursor = null;
    _marketDetails.clear();
    _priceAttempts.clear();
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

  /// The other tab's feed, kept while you look at this one, so switching
  /// Global / Following shows what was there at once and refreshes it
  /// silently instead of dropping to a skeleton.
  final Map<CallFeedMode, _FeedMemory> _feedByMode = {};

  /// Saved reads on this phone, when the repository keeps them.
  CallsSnapshotSource? get _snapshots =>
      _repository is CallsSnapshotSource
          ? _repository as CallsSnapshotSource
          : null;

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

  /// Data is on screen but older than [staleAfter]. Not an error, and never
  /// narrated to the person: the next [loadFeed] refreshes it silently.
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
    if (_feedServedAt != null) {
      _feedByMode[_feedMode] = _FeedMemory(
        entries: _feedEntries,
        servedAt: _feedServedAt!,
        nextCursor: _feedNextCursor,
        fromCache: _feedFromCache,
      );
    }
    _feedMode = mode;
    _requests.remove('feed');
    _requests.remove('more');
    _isLoadingFeed = false;
    _isLoadingMore = false;
    final kept = _feedByMode.remove(mode);
    _feedEntries = kept?.entries ?? const [];
    _feedServedAt = kept?.servedAt;
    _feedNextCursor = kept?.nextCursor;
    _feedFromCache = kept?.fromCache ?? false;
    _feedError = null;
    _notify();
    await loadFeed(force: true);
  }

  /// Draws the saved first page while the live one loads, on a cold start.
  /// Skipped once the live read has answered or anything is on screen.
  Future<void> _paintSavedFeed(Object request, CallFeedMode mode) async {
    final snapshots = _snapshots;
    if (snapshots == null) return;
    final saved = await snapshots.savedFeed(mode: mode);
    if (saved == null || saved.entries.isEmpty) return;
    if (!_isCurrent('feed', request) ||
        _feedMode != mode ||
        _feedServedAt != null ||
        _feedEntries.isNotEmpty) {
      return;
    }
    _feedEntries = saved.entries;
    _feedServedAt = saved.servedAt;
    _feedNextCursor = saved.nextCursor;
    _feedFromCache = true;
    _notify();
  }

  /// A failed live read waits for the saved one still coming off the disk,
  /// so a dead network (which fails in milliseconds) never beats the saved
  /// rows to the screen and leaves a full-screen "offline" in their place.
  Future<void> _settlePaint(Future<void>? paint) async {
    if (paint == null) return;
    try {
      await paint;
    } catch (e) {
      developer.log('CallsProvider: saved read failed: $e');
    }
  }

  Future<void> loadFeed({bool force = false}) async {
    if (_isLoadingFeed) return;
    if (!force && _feedServedAt != null && !isFeedStale) return;

    final request = _beginRequest('feed');
    _isLoadingFeed = true;
    _feedError = null;
    _notify();
    final paint =
        _feedEntries.isEmpty && _feedServedAt == null
            ? _paintSavedFeed(request, _feedMode)
            : null;
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
      await _settlePaint(paint);
      if (!_isCurrent('feed', request)) return;
      // Keep whatever is already on screen; it is now explicitly cached.
      developer.log('CallsProvider.loadFeed offline: $e');
      _isOffline = true;
      _feedFromCache = _feedEntries.isNotEmpty;
      _feedError = e.message;
    } on CallsException catch (e) {
      await _settlePaint(paint);
      if (!_isCurrent('feed', request)) return;
      developer.log('CallsProvider.loadFeed failed: $e');
      _feedError = e.message;
    } catch (e) {
      await _settlePaint(paint);
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
  bool _catalogServed = false;
  bool _isLoadingOpenMarkets = false;
  String? _openMarketsError;
  DateTime? _openMarketsLoadedAt;

  /// When the last background price read for a market started. Bounds how
  /// often a market whose price will not come is asked again.
  final Map<String, DateTime> _priceAttempts = {};

  /// How long a loaded catalog is shown before [refreshOpenMarketsIfStale]
  /// reads it again, silently, behind what is already on screen.
  static const catalogRefreshAfter = Duration(minutes: 2);

  /// When a shown price is read again: at four minutes, inside the server's
  /// own refresh (half of the venue price's ten-minute validity), so the
  /// figure on screen is replaced before it lapses rather than after.
  static const priceRefreshAfter = Duration(minutes: 4);

  /// The shortest gap between two background reads of one market's price,
  /// so a market the venue has no price for is not asked on every frame.
  /// The server itself retries a missing side after a minute.
  static const priceRetryAfter = Duration(minutes: 1);

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
    final paint =
        _openMarkets.isEmpty && !_catalogServed
            ? _paintSavedCatalog(request)
            : null;
    try {
      final repository = _repository;
      final markets =
          repository is CallsCatalogRepository
              ? await (repository as CallsCatalogRepository)
                  .fetchMarketCatalog()
              : await repository.fetchOpenMarkets();
      if (!_isCurrent('catalog', request)) return;
      _openMarkets = markets;
      _catalogServed = true;
      _openMarketsLoadedAt = _clock();
      _isOffline = false;
    } on CallVocabularyException {
      await _settlePaint(paint);
      if (!_isCurrent('catalog', request)) return;
      _openMarketsError =
          'The market data format changed. Please update the app or try again later.';
    } on CallsOfflineException catch (e) {
      await _settlePaint(paint);
      if (!_isCurrent('catalog', request)) return;
      _isOffline = true;
      _openMarketsError = e.message;
    } on CallsException catch (e) {
      await _settlePaint(paint);
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

  Future<void> _paintSavedCatalog(Object request) async {
    final saved = await _snapshots?.savedMarketCatalog();
    if (saved == null || saved.isEmpty) return;
    if (!_isCurrent('catalog', request) || _openMarkets.isNotEmpty) return;
    _openMarkets = saved;
    _notify();
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

  /// Reads the open catalog again when the copy on screen is older than
  /// [catalogRefreshAfter], or was never loaded. Silent: what is shown stays
  /// shown while it runs, and a failed read keeps it (the screen decides
  /// whether an empty catalog's error deserves a state of its own).
  Future<void> refreshOpenMarketsIfStale() async {
    final loadedAt = _openMarketsLoadedAt;
    if (loadedAt != null &&
        _clock().difference(loadedAt) < catalogRefreshAfter) {
      return;
    }
    await loadOpenMarkets(force: true);
  }

  /// Whether [refreshPriceIfStale] would read [marketId] again right now:
  /// never read, a Panta price missing a side, or one older than
  /// [priceRefreshAfter] — and not already in flight or tried within
  /// [priceRetryAfter]. A price stamped slightly ahead of this device's clock
  /// is treated as new, not as broken.
  bool priceRefreshDue(String marketId) {
    if (_marketsInFlight.contains(marketId)) return false;
    final now = _clock();
    final attempted = _priceAttempts[marketId];
    if (attempted != null && now.difference(attempted) < priceRetryAfter) {
      return false;
    }
    final detail = _marketDetails[marketId];
    if (detail == null) return true;
    // Demo and other venues carry no Panta share price to keep current.
    if (detail.market.venue != MarketVenue.panta) return false;
    final price = detail.sharePrice;
    if (price == null || price.yesPrice == null || price.noPrice == null) {
      return true;
    }
    return now.toUtc().difference(price.observedAtUtc) >= priceRefreshAfter;
  }

  /// Keeps a shown market's price current without the person asking: reads
  /// the market again in the background when [priceRefreshDue]. Nothing on
  /// screen changes while it runs — the last good price stays until the new
  /// one lands, and a failed read leaves it in place. Safe to call from every
  /// visible row on every build; the guard above makes repeats free.
  void refreshPriceIfStale(String marketId) {
    if (!priceRefreshDue(marketId)) return;
    _priceAttempts[marketId] = _clock();
    unawaited(loadMarketDetail(marketId, force: true));
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
    final paint =
        !_personDetails.containsKey(ref) && ref == _viewerUserId
            ? _paintSavedPerson(key, request, ref)
            : null;
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
      await _settlePaint(paint);
      if (!_isCurrent(key, request)) return null;
      _isOffline = true;
      _personErrors[ref] = e.message;
      return _personDetails[ref];
    } on CallsException catch (e) {
      await _settlePaint(paint);
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

  /// Your own profile and record, as last seen, while the live one loads.
  Future<void> _paintSavedPerson(String key, Object request, String ref) async {
    final saved = await _snapshots?.savedPerson(ref);
    if (saved == null) return;
    if (!_isCurrent(key, request) || _personDetails.containsKey(ref)) return;
    _personDetails[ref] = saved;
    _notify();
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
      _applyFollowChange(personId, confirmed);
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

  /// Every cache a confirmed follow or unfollow of [personId] touches.
  void _applyFollowChange(String personId, bool confirmed) {
    for (final ref in _personDetails.keys.toList()) {
      final cached = _personDetails[ref];
      if (cached?.person.id != personId) continue;
      _personDetails[ref] = cached!.copyWith(
        calls:
            confirmed
                ? cached.calls
                : cached.calls
                    .where(
                      (entry) => entry.call.visibility == CallVisibility.public,
                    )
                    .toList(),
        viewerIsFollowing: confirmed,
      );
    }
    // The follow list changed; read it again rather than editing it here.
    // A read already in flight predates this change, so it is discarded
    // rather than allowed to refill the list with the old membership.
    _requests.remove('following');
    _isLoadingFollowing = false;
    _followingError = null;
    _following = null;
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
  }

  /// Follow or unfollow one canonical person by id, from a card that is not
  /// their profile (Add a friend). The same durable, never-optimistic write
  /// as [setFollowing]: the state changes only once the BFF acknowledges it.
  /// The feed is read again in the background, so the card answers at once.
  /// No wallet signature: the session is the authority.
  Future<bool> setFollowingById(String personId, bool following) async {
    final viewer = _viewerUserId;
    if (viewer == null || viewer.isEmpty) throw const CallsSignedOutException();
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
      _applyFollowChange(personId, confirmed);
      unawaited(loadFeed(force: true));
      return confirmed;
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _followsInFlight.remove(personId);
        _notify();
      }
    }
  }

  /// Follow one canonical person by id, for a person who is not on screen
  /// (follows chosen during onboarding, applied after sign-in). Idempotent on
  /// the server: following someone already followed changes nothing. Returns
  /// the server's confirmed state; throws as [setFollowing] does.
  Future<bool> followPersonById(String personId) async {
    final viewer = _viewerUserId;
    if (viewer == null || viewer.isEmpty) throw const CallsSignedOutException();
    if (personId == viewer) {
      throw const CallsRejectedException("You can't follow yourself.");
    }
    if (_followsInFlight.contains(personId)) return true;
    final key = 'follow:$personId';
    final request = _beginRequest(key);
    _followsInFlight.add(personId);
    _notify();
    try {
      final confirmed = await _repository.setFollowing(
        personId: personId,
        following: true,
        viewerUserId: viewer,
      );
      if (!_isCurrent(key, request)) throw _accountChanged;
      _analytics.record(
        AnalyticsEvents.followCreated(
          personId: personId,
          surface: AnalyticsSurface.onboarding,
        ),
      );
      for (final ref in _personDetails.keys.toList()) {
        final cached = _personDetails[ref];
        if (cached?.person.id != personId) continue;
        _personDetails[ref] = cached!.copyWith(viewerIsFollowing: confirmed);
      }
      // The follow list and the Following feed are read again when next
      // shown, never edited here.
      _requests.remove('following');
      _isLoadingFollowing = false;
      _following = null;
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
    // Same gate on Home's top calls: a top call on this market now carries
    // its split (and, after a Back/Fade, one more response). The strip on
    // screen stays until the server's answer replaces it.
    if (_topCalls?.any((top) => top.market.id == entry.market.id) ?? false) {
      unawaited(loadTopCalls(force: true));
    }

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
  // The people layer — leaderboard, following, top calls, search, thesis
  // -------------------------------------------------------------------------
  //
  // Available only when the repository implements [PeopleRepository] (the
  // live BFF does; the seeded mock does not). Without it every surface below
  // reports itself unavailable instead of inventing rankings or activity.

  PeopleRepository? get _people =>
      _repository is PeopleRepository ? _repository as PeopleRepository : null;

  /// Whether this build can show the people layer at all.
  bool get supportsPeople => _people != null;

  final Map<LeaderboardWindow, Leaderboard> _leaderboards = {};
  final Set<LeaderboardWindow> _leaderboardsInFlight = {};
  final Map<LeaderboardWindow, String> _leaderboardErrors = {};

  List<TopCall>? _topCalls;
  bool _isLoadingTopCalls = false;
  String? _topCallsError;

  List<PersonCard>? _following;
  bool _isLoadingFollowing = false;
  String? _followingError;

  Leaderboard? leaderboard(LeaderboardWindow window) => _leaderboards[window];
  bool isLoadingLeaderboard(LeaderboardWindow window) =>
      _leaderboardsInFlight.contains(window);
  String? leaderboardError(LeaderboardWindow window) =>
      _leaderboardErrors[window];

  /// Null until loaded; empty means "loaded, nothing to show".
  List<TopCall>? get topCalls =>
      _topCalls == null ? null : List.unmodifiable(_topCalls!);
  bool get isLoadingTopCalls => _isLoadingTopCalls;
  String? get topCallsError => _topCallsError;

  /// The signed-in person's follow list. Null until loaded.
  List<PersonCard>? get following =>
      _following == null ? null : List.unmodifiable(_following!);
  bool get isLoadingFollowing => _isLoadingFollowing;
  String? get followingError => _followingError;

  void _clearPeople() {
    _leaderboards.clear();
    _leaderboardsInFlight.clear();
    _leaderboardErrors.clear();
    _topCalls = null;
    _isLoadingTopCalls = false;
    _topCallsError = null;
    _following = null;
    _isLoadingFollowing = false;
    _followingError = null;
  }

  static String _messageOf(Object error) =>
      error is CallsException ? error.message : const CallsFailure().message;

  Future<void> loadLeaderboard(
    LeaderboardWindow window, {
    bool force = false,
  }) async {
    final people = _people;
    if (people == null) return;
    if (_leaderboardsInFlight.contains(window)) return;
    if (!force && _leaderboards.containsKey(window)) return;
    final key = 'leaderboard:${window.wire}';
    final request = _beginRequest(key);
    _leaderboardsInFlight.add(window);
    _leaderboardErrors.remove(window);
    _notify();
    try {
      final board = await people.fetchLeaderboard(window: window);
      if (!_isCurrent(key, request)) return;
      _leaderboards[window] = board;
      _isOffline = false;
    } on CallsOfflineException catch (e) {
      if (!_isCurrent(key, request)) return;
      _isOffline = true;
      _leaderboardErrors[window] = e.message;
    } catch (e) {
      if (!_isCurrent(key, request)) return;
      developer.log('CallsProvider.loadLeaderboard failed: $e');
      _leaderboardErrors[window] = _messageOf(e);
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _leaderboardsInFlight.remove(window);
        _notify();
      }
    }
  }

  Future<void> loadTopCalls({bool force = false}) async {
    final people = _people;
    if (people == null || _isLoadingTopCalls) return;
    if (!force && _topCalls != null) return;
    const key = 'top-calls';
    final request = _beginRequest(key);
    _isLoadingTopCalls = true;
    _topCallsError = null;
    _notify();
    try {
      final calls = await people.fetchTopCalls();
      if (!_isCurrent(key, request)) return;
      _topCalls = calls;
    } catch (e) {
      if (!_isCurrent(key, request)) return;
      developer.log('CallsProvider.loadTopCalls failed: $e');
      _topCallsError = _messageOf(e);
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _isLoadingTopCalls = false;
        _notify();
      }
    }
  }

  Future<void> loadFollowing({bool force = false}) async {
    final people = _people;
    if (people == null || !isSignedIn || _isLoadingFollowing) return;
    if (!force && _following != null) return;
    const key = 'following';
    final request = _beginRequest(key);
    _isLoadingFollowing = true;
    _followingError = null;
    _notify();
    final paint = _following == null ? _paintSavedFollowing(request) : null;
    try {
      final list = await people.fetchFollowing();
      if (!_isCurrent(key, request)) return;
      _following = list;
    } catch (e) {
      await _settlePaint(paint);
      if (!_isCurrent(key, request)) return;
      developer.log('CallsProvider.loadFollowing failed: $e');
      _followingError = _messageOf(e);
    } finally {
      if (_isCurrent(key, request)) {
        _requests.remove(key);
        _isLoadingFollowing = false;
        _notify();
      }
    }
  }

  Future<void> _paintSavedFollowing(Object request) async {
    final saved = await _snapshots?.savedFollowing();
    if (saved == null) return;
    if (!_isCurrent('following', request) || _following != null) return;
    _following = saved;
    _notify();
  }

  /// One search, returned directly: results belong to the screen asking, not
  /// to a shared cache. A result for a viewer who has since changed is
  /// discarded rather than shown.
  Future<List<PersonCard>> searchPeople(String query) async {
    final people = _people;
    if (people == null) {
      throw const CallsFailure('People search is not available in this build.');
    }
    final viewer = _viewerUserId;
    final results = await people.searchPeople(query);
    if (_disposed || viewer != _viewerUserId) throw _accountChanged;
    return results;
  }

  /// Whether this build can look a person up before adding them.
  bool get supportsPersonFinder => _repository is PersonFinderRepository;

  /// `people.find`: who an X handle, @username or wallet belongs to, for the
  /// Add a friend card. Session only; writes nothing. A result for a viewer
  /// who has since changed is discarded rather than shown.
  Future<PersonLookup> findPerson(String query) async {
    final Object repository = _repository;
    if (repository is! PersonFinderRepository) {
      throw const PersonFinderUnavailable();
    }
    final viewer = _viewerUserId;
    if (viewer == null || viewer.isEmpty) throw const CallsSignedOutException();
    final lookup = await repository.findPerson(query);
    if (_disposed || viewer != _viewerUserId) throw _accountChanged;
    return lookup;
  }

  /// Append to the viewer's own call's thesis, then re-read the call so the
  /// thread on screen is the server's, not a local guess.
  Future<ThesisUpdate> appendThesisUpdate(String callId, String body) async {
    final people = _people;
    if (people == null) {
      throw const CallsRejectedException(
        'Thesis updates are not available in this build.',
      );
    }
    if (!isSignedIn) throw const CallsSignedOutException();
    if (_isSubmitting) {
      throw const CallsRejectedException('Already posting that.');
    }
    final request = _beginRequest('submit');
    _isSubmitting = true;
    _notify();
    try {
      final update = await people.appendThesisUpdate(
        callId: callId,
        body: body,
      );
      if (!_isCurrent('submit', request)) throw _accountChanged;
      // Keeps the action busy until the thread on screen includes it.
      await loadCall(callId, force: true, reportOpen: false);
      return update;
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

/// One feed tab as it was last shown.
class _FeedMemory {
  const _FeedMemory({
    required this.entries,
    required this.servedAt,
    required this.nextCursor,
    required this.fromCache,
  });

  final List<CallFeedEntry> entries;
  final int servedAt;
  final String? nextCursor;
  final bool fromCache;
}
