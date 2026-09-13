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
  }) : _repository = repository,
       _clock = clock ?? DateTime.now;

  final CallsRepository _repository;
  final DateTime Function() _clock;

  /// How old served data may be before the UI must say so.
  final Duration staleAfter;

  bool _disposed = false;

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
    if (_feedServedAt == null && _feedEntries.isEmpty) return CallsLoadState.idle;
    if (_feedEntries.isEmpty) return CallsLoadState.empty;
    return CallsLoadState.ready;
  }

  /// Switching the tab is one branch, exactly as `ArenaFeedMode` is.
  Future<void> setFeedMode(CallFeedMode mode) async {
    if (_feedMode == mode) return;
    _feedMode = mode;
    _feedEntries = const [];
    _feedServedAt = null;
    _feedNextCursor = null;
    _notify();
    await loadFeed(force: true);
  }

  Future<void> loadFeed({bool force = false}) async {
    if (_isLoadingFeed) return;
    if (!force && _feedServedAt != null && !isFeedStale) return;

    _isLoadingFeed = true;
    _feedError = null;
    _notify();
    try {
      final page = await _repository.fetchFeed(
        mode: _feedMode,
        viewerUserId: _viewerUserId,
      );
      _feedEntries = page.entries;
      _feedServedAt = page.servedAt;
      _feedNextCursor = page.nextCursor;
      _feedFromCache = page.fromCache;
      _isOffline = false;
    } on CallsOfflineException catch (e) {
      // Keep whatever is already on screen; it is now explicitly cached.
      developer.log('CallsProvider.loadFeed offline: $e');
      _isOffline = true;
      _feedFromCache = _feedEntries.isNotEmpty;
      _feedError = e.message;
    } on CallsException catch (e) {
      developer.log('CallsProvider.loadFeed failed: $e');
      _feedError = e.message;
    } catch (e) {
      developer.log('CallsProvider.loadFeed failed: $e');
      _feedError = const CallsFailure().message;
    } finally {
      _isLoadingFeed = false;
      _notify();
    }
  }

  Future<void> loadMore() async {
    final cursor = _feedNextCursor;
    if (cursor == null || _isLoadingMore || _isLoadingFeed) return;
    _isLoadingMore = true;
    _notify();
    try {
      final page = await _repository.fetchFeed(
        mode: _feedMode,
        viewerUserId: _viewerUserId,
        cursor: cursor,
      );
      _feedEntries = [..._feedEntries, ...page.entries];
      _feedNextCursor = page.nextCursor;
      _isOffline = false;
    } on CallsOfflineException {
      _isOffline = true;
    } on CallsException catch (e) {
      developer.log('CallsProvider.loadMore failed: $e');
    } finally {
      _isLoadingMore = false;
      _notify();
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

  List<VenueMarket> get openMarkets => List.unmodifiable(_openMarkets);
  bool get isLoadingOpenMarkets => _isLoadingOpenMarkets;
  String? get openMarketsError => _openMarketsError;

  MarketDetail? marketDetail(String marketId) => _marketDetails[marketId];
  bool isLoadingMarket(String marketId) => _marketsInFlight.contains(marketId);
  String? marketError(String marketId) => _marketErrors[marketId];

  Future<void> loadOpenMarkets({bool force = false}) async {
    if (_isLoadingOpenMarkets) return;
    if (!force && _openMarkets.isNotEmpty) return;
    _isLoadingOpenMarkets = true;
    _openMarketsError = null;
    _notify();
    try {
      _openMarkets = await _repository.fetchOpenMarkets(category: 'crypto');
      _isOffline = false;
    } on CallsOfflineException catch (e) {
      _isOffline = true;
      _openMarketsError = e.message;
    } on CallsException catch (e) {
      _openMarketsError = e.message;
    } finally {
      _isLoadingOpenMarkets = false;
      _notify();
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

    _marketsInFlight.add(marketId);
    _marketErrors.remove(marketId);
    _notify();
    try {
      final detail = await _repository.fetchMarketDetail(
        marketId: marketId,
        viewerUserId: _viewerUserId,
      );
      _marketDetails[marketId] = detail;
      _isOffline = false;
      return detail;
    } on CallsOfflineException catch (e) {
      _isOffline = true;
      _marketErrors[marketId] = e.message;
      return _marketDetails[marketId];
    } on CallsException catch (e) {
      developer.log('CallsProvider.loadMarketDetail failed: $e');
      _marketErrors[marketId] = e.message;
      return null;
    } finally {
      _marketsInFlight.remove(marketId);
      _notify();
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

  Future<CallDetail?> loadCall(String callId, {bool force = false}) async {
    if (!force &&
        (_callDetails.containsKey(callId) || _callsInFlight.contains(callId))) {
      return _callDetails[callId];
    }
    _callsInFlight.add(callId);
    _callErrors.remove(callId);
    _notify();
    try {
      final detail = await _repository.fetchCall(
        callId: callId,
        viewerUserId: _viewerUserId,
      );
      _callDetails[callId] = detail;
      _isOffline = false;
      return detail;
    } on CallsOfflineException catch (e) {
      _isOffline = true;
      _callErrors[callId] = e.message;
      return _callDetails[callId];
    } on CallsException catch (e) {
      developer.log('CallsProvider.loadCall failed: $e');
      _callErrors[callId] = e.message;
      return null;
    } finally {
      _callsInFlight.remove(callId);
      _notify();
    }
  }

  Future<PersonDetail?> loadPerson(String ref, {bool force = false}) async {
    if (!force &&
        (_personDetails.containsKey(ref) || _peopleInFlight.contains(ref))) {
      return _personDetails[ref];
    }
    _peopleInFlight.add(ref);
    _personErrors.remove(ref);
    _notify();
    try {
      final detail = await _repository.fetchPerson(
        personRef: ref,
        viewerUserId: _viewerUserId,
      );
      _personDetails[ref] = detail;
      _isOffline = false;
      return detail;
    } on CallsOfflineException catch (e) {
      _isOffline = true;
      _personErrors[ref] = e.message;
      return _personDetails[ref];
    } on CallsException catch (e) {
      developer.log('CallsProvider.loadPerson failed: $e');
      _personErrors[ref] = e.message;
      return null;
    } finally {
      _peopleInFlight.remove(ref);
      _notify();
    }
  }

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  /// Locks a new free call. Rethrows so the composer can show the reason
  /// inline; [CallsSignedOutException] is the signed-out path.
  Future<CallFeedEntry> createCall(CreateCallInput input) async {
    if (_isSubmitting) {
      throw const CallsRejectedException('Already locking a call.');
    }
    _isSubmitting = true;
    _notify();
    try {
      final entry = await _repository.createCall(
        input: input,
        viewerUserId: _viewerUserId,
      );
      _onCallCreated(entry);
      return entry;
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  /// Back, Fade or Challenge. Back and Fade return the actor's own new call.
  Future<CallResponseResult> respondToCall(RespondToCallInput input) async {
    if (_isSubmitting) {
      throw const CallsRejectedException('Already sending that.');
    }
    _isSubmitting = true;
    _notify();
    try {
      final result = await _repository.respondToCall(
        input: input,
        viewerUserId: _viewerUserId,
      );
      final own = result.resultingCall;
      if (own != null) _onCallCreated(own);
      // The target's back/fade counter moved; drop its cached detail.
      _callDetails.remove(input.targetCallId);
      return result;
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  void _onCallCreated(CallFeedEntry entry) {
    _feedEntries = [entry, ..._feedEntries];
    // The viewer now has a locked call on this market, so the crowd split
    // becomes available — force a refetch rather than synthesising it here.
    _marketDetails.remove(entry.market.id);
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
    _isLoadingInvitations = true;
    _notify();
    try {
      _invitations = await _repository.fetchInvitations(
        viewerUserId: _viewerUserId,
      );
    } on CallsException catch (e) {
      developer.log('CallsProvider.loadInvitations failed: $e');
    } finally {
      _isLoadingInvitations = false;
      _notify();
    }
  }

  // -------------------------------------------------------------------------
  // Sharing
  // -------------------------------------------------------------------------

  String shareLinkForCall(String callId) => _repository.shareLinkForCall(callId);

  String shareLinkForPerson(String handleOrId) =>
      _repository.shareLinkForPerson(handleOrId);

  /// Exposed so the deep-link resolver can reach the same repository without a
  /// second source of truth.
  CallsRepository get repository => _repository;
}
