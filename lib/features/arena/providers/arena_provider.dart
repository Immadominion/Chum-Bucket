import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/base58.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_backend_service.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/data/match_arena_service.dart';

enum ArenaFeedMode { global, following }

/// State + orchestration for the Arena feature.
///
/// This is a brand new, separate provider - it does not touch
/// WalletProvider/ChallengeService/EscrowService internals. It borrows the
/// already-initialized MWA auth session (passed in by the caller) purely to
/// lazily construct its own [MatchArenaService]
/// bound to the SEPARATE chumbucket_arena program.
class ArenaProvider extends BaseChangeNotifier {
  MatchArenaService? _arenaService;
  final ArenaBackendService _backendService = ArenaBackendService();

  bool get isArenaServiceReady => _arenaService != null;
  MatchArenaService? get arenaService => _arenaService;

  List<ArenaMatchEntry> _matchday = [];
  bool _isLoadingMatchday = false;
  String? _matchdayError;

  List<ArenaMatchEntry> get matchday => List.unmodifiable(_matchday);
  bool get isLoadingMatchday => _isLoadingMatchday;
  String? get matchdayError => _matchdayError;

  List<MyPotRecord> _myPots = [];
  bool _isLoadingMyPots = false;

  List<MyPotRecord> get myPots => List.unmodifiable(_myPots);
  bool get isLoadingMyPots => _isLoadingMyPots;

  List<ArenaActivityEvent> _activity = [];
  bool _isLoadingActivity = false;
  String? _activityError;
  ArenaFeedMode _feedMode = ArenaFeedMode.global;

  List<ArenaLeaderboardRow> _hotCallers = [];
  bool _isLoadingHotCallers = false;

  final Map<String, List<ArenaMatchCaller>> _matchCallersByMatchId = {};
  final Set<String> _loadingMatchCallerIds = {};
  final Set<String> _matchCallerErrorIds = {};

  final Map<String, ArenaSocialProfile> _profileCache = {};
  final Set<String> _followedWallets = {};
  final Set<String> _followBusyWallets = {};
  String? _profileError;

  final Map<String, ArenaWalletProfile> _walletProfileCache = {};
  final Set<String> _walletProfilesInFlight = {};

  List<ArenaPendingTarget> _pendingTargets = [];
  bool _isLoadingPendingTargets = false;
  String? _pendingTargetsError;
  final Set<String> _pendingTargetBusyHandles = {};

  List<ArenaServerPosition> _claimablePositions = [];
  bool _isLoadingClaimable = false;
  String? _claimableError;

  List<ArenaNotification> _notifications = [];
  int _unreadNotificationCount = 0;
  bool _isLoadingNotifications = false;
  String? _notificationsError;
  RealtimeChannel? _notificationChannel;
  String? _notificationWallet;
  bool _isLinkingIdentity = false;

  List<ArenaActivityEvent> get activity => List.unmodifiable(_activity);
  bool get isLoadingActivity => _isLoadingActivity;
  String? get activityError => _activityError;
  ArenaFeedMode get feedMode => _feedMode;
  List<ArenaLeaderboardRow> get hotCallers => List.unmodifiable(_hotCallers);
  bool get isLoadingHotCallers => _isLoadingHotCallers;
  String? get profileError => _profileError;
  List<ArenaServerPosition> get claimablePositions =>
      List.unmodifiable(_claimablePositions);
  bool get isLoadingClaimable => _isLoadingClaimable;
  String? get claimableError => _claimableError;
  List<ArenaNotification> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotificationCount => _unreadNotificationCount;
  bool get isLoadingNotifications => _isLoadingNotifications;
  String? get notificationsError => _notificationsError;
  bool get isLinkingIdentity => _isLinkingIdentity;

  List<ArenaMatchCaller> matchCallersFor(String matchId) =>
      List.unmodifiable(_matchCallersByMatchId[matchId] ?? const []);
  bool isLoadingMatchCallers(String matchId) =>
      _loadingMatchCallerIds.contains(matchId);
  bool matchCallersHadError(String matchId) =>
      _matchCallerErrorIds.contains(matchId);

  bool isFollowing(String wallet) => _followedWallets.contains(wallet);
  bool isFollowBusy(String wallet) => _followBusyWallets.contains(wallet);
  ArenaSocialProfile? cachedProfile(String wallet) => _profileCache[wallet];

  /// The linked-identity label (X handle/display name) for a wallet, once
  /// [loadWalletProfiles] has resolved it — null until then or if unlinked.
  ArenaWalletProfile? walletProfile(String wallet) =>
      _walletProfileCache[wallet];

  /// Venmo-style "pending, resolves automatically" targets the current
  /// wallet has created (e.g. friends added by X handle who haven't linked
  /// a wallet yet). Populated by [loadPendingTargets].
  List<ArenaPendingTarget> get pendingTargets =>
      List.unmodifiable(_pendingTargets);
  bool get isLoadingPendingTargets => _isLoadingPendingTargets;
  String? get pendingTargetsError => _pendingTargetsError;
  bool isPendingTargetBusy(String handle) =>
      _pendingTargetBusyHandles.contains(_normalizeHandle(handle));

  /// Still-unresolved pending target for [handle], if the viewer has one
  /// outstanding — null once it resolves (or if none was ever created).
  ArenaPendingTarget? pendingTargetForHandle(String handle) {
    final normalized = _normalizeHandle(handle);
    for (final target in _pendingTargets) {
      if (!target.isResolved &&
          target.providerUsername.toLowerCase() == normalized) {
        return target;
      }
    }
    return null;
  }

  /// Lazily create the MatchArenaService the first time it's needed (e.g.
  /// when the user opens the Arena tab). Safe to call repeatedly - a no-op
  /// once initialized.
  Future<void> ensureArenaService({
    required MwaAuthProvider authProvider,
    required String? walletAddress,
    required String rpcUrl,
  }) async {
    if (_arenaService != null) return;
    if (!authProvider.isAuthenticated || walletAddress == null) {
      throw StateError(
        'Wallet is not ready yet - open the Arena tab after logging in.',
      );
    }
    _arenaService = await MatchArenaService.create(
      authProvider: authProvider,
      walletAddress: walletAddress,
      rpcUrl: rpcUrl,
    );
    notifyListeners();
  }

  Future<void> loadMatchday() async {
    _isLoadingMatchday = true;
    _matchdayError = null;
    notifyListeners();
    try {
      _matchday = await _backendService.fetchMatchday();
    } catch (e) {
      log('❌ ArenaProvider.loadMatchday failed: $e');
      _matchdayError = e.toString();
    } finally {
      _isLoadingMatchday = false;
      notifyListeners();
    }
  }

  Future<ArenaMatchEntry> refreshMatch(String matchId) async {
    final fresh = await _backendService.fetchMatch(matchId);
    final index = _matchday.indexWhere((m) => m.fixture.matchId == matchId);
    if (index != -1) {
      _matchday = List.of(_matchday)..[index] = fresh;
      notifyListeners();
    }
    return fresh;
  }

  /// Stake USDC on [bucket] of [market] for [match]. Requires
  /// [ensureArenaService] to have been called first (and to have succeeded).
  ///
  /// MONEY ROUTING: the on-chain pot is derived from `market.potMatchId`, NOT
  /// the fixture matchId. For the RESULT market these are the same string; for
  /// line markets (Over/Under, Handicap) `potMatchId` is a distinct id, so the
  /// stake must land in that market's own pot. [bucketLabel] is the market's
  /// own bucket label ("HOME"/"DRAW"/"AWAY" or "OVER"/"UNDER") used for the
  /// social read model only.
  Future<String> placeCall({
    required ArenaMatchEntry match,
    required ArenaMarket market,
    required int bucket,
    required String bucketLabel,
    required double amountUsdc,
    required MwaAuthProvider authProvider,
  }) async {
    final service = _arenaService;
    if (service == null) {
      throw StateError('Arena service is not initialized yet');
    }

    final potMatchId = market.potMatchId;

    final signature = await service.placeCall(
      matchId: potMatchId,
      bucket: bucket,
      amountUsdc: amountUsdc,
    );

    await _recordMyPot(
      MyPotRecord(
        // Keyed by this market's pot id so claim() hits the same pot the
        // stake went into (line markets have their own pot per fixture).
        matchId: potMatchId,
        home: match.fixture.home,
        away: match.fixture.away,
        bucket: bucket,
        amountUsdc: amountUsdc,
        txSignature: signature,
        placedAt: DateTime.now(),
      ),
    );

    // NOTE: the social-mirror proof signature (a SECOND wallet prompt) used to
    // fire here unawaited, which meant the wallet could pop AFTER the user had
    // already left this screen — reading like a glitch. It's now driven by the
    // caller via [signAndRecordCallProof] so the second approval happens inside
    // the visible submit flow, with on-screen copy explaining it. Money routing
    // is unchanged — this only records the off-chain social read model.
    return signature;
  }

  /// Best-effort: sign the social-mirror proof (a second, lightweight wallet
  /// message signature — NOT another money transaction) and record the pick in
  /// the off-chain read model. The on-chain bet has already landed by the time
  /// this runs; a failure or a user-cancelled signature here is harmless (the
  /// indexer reconciles by signature later), so callers should treat any throw
  /// as non-fatal and NOT surface it as a failed bet.
  Future<void> signAndRecordCallProof({
    required MwaAuthProvider authProvider,
    required ArenaMatchEntry match,
    required ArenaMarket market,
    required String bucketLabel,
    required double amountUsdc,
    required String txSignature,
  }) async {
    final service = _arenaService;
    if (service == null) return;
    final stakeBaseUnits = BigInt.from(
      MatchArenaService.usdcToBaseUnits(amountUsdc),
    );
    final proof = await _signCallProof(
      authProvider: authProvider,
      matchId: match.fixture.matchId,
      bucket: bucketLabel,
      stakeBaseUnits: stakeBaseUnits,
      txSignature: txSignature,
    );
    await _backendService.recordPredictionCall(
      walletAddress: service.walletAddress,
      matchId: match.fixture.matchId,
      marketId: market.marketId,
      bucketLabel: bucketLabel,
      stakeBaseUnits: stakeBaseUnits,
      txSignature: txSignature,
      timestamp: proof.timestamp,
      signature: proof.signature,
      metadata: {
        'home': match.fixture.home,
        'away': match.fixture.away,
        'competition': match.fixture.competition,
        'kickoff': match.fixture.kickoff.toIso8601String(),
        'market': market.label,
      },
    );
  }

  /// Live in-play score + phase for a match (display-only; the on-chain proof
  /// settles bets). Null until the feed has a live snapshot. Passthrough so the
  /// live match strip doesn't reach into the backend service directly.
  Future<ArenaLiveScore?> fetchLiveScore(String matchId) =>
      _backendService.fetchLiveScore(matchId);

  /// Self-serve devnet faucet: mint 100 test USDC of the program's pinned mint
  /// to [wallet] so a tester/judge can fund themselves before betting. Returns
  /// whether the wallet was actually funded (false when it already had enough).
  /// Passthrough so the bet screen doesn't reach into the backend service.
  Future<bool> requestFaucet(String wallet) =>
      _backendService.requestFaucet(wallet);

  /// Pull the payout/refund for a previously-placed call.
  Future<String> claim(MyPotRecord record) async {
    final service = _arenaService;
    if (service == null) {
      throw StateError('Arena service is not initialized yet');
    }

    final signature = await service.claim(matchId: record.matchId);
    await _markClaimedLocally(record.matchId);
    return signature;
  }

  // ---- Local "My Pots" persistence (per-wallet, SharedPreferences) ----
  //
  // The gaffer-backend is read-only and fixture-scoped, not user-scoped, so
  // "which pots am I in" is tracked locally on-device (written the moment a
  // placeCall succeeds) and cross-checked against the authoritative
  // on-chain Position account (bucket/stake/claimed) whenever the chain is
  // reachable.

  String _prefsKey(String walletAddress) => 'arena_my_pots_$walletAddress';

  Future<void> _recordMyPot(MyPotRecord record) async {
    final walletAddress = _arenaService?.walletAddress;
    if (walletAddress == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(walletAddress);
    final existingJson = prefs.getStringList(key) ?? [];
    final existing =
        existingJson
            .map(
              (s) =>
                  MyPotRecord.fromJson(jsonDecode(s) as Map<String, dynamic>),
            )
            .where((r) => r.matchId != record.matchId)
            .toList();
    existing.add(record);
    await prefs.setStringList(
      key,
      existing.map((r) => jsonEncode(r.toJson())).toList(),
    );

    _myPots = existing;
    notifyListeners();
  }

  Future<void> _markClaimedLocally(String matchId) async {
    final walletAddress = _arenaService?.walletAddress;
    if (walletAddress == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(walletAddress);
    final updated =
        _myPots
            .map(
              (r) =>
                  r.matchId == matchId ? r.copyWith(claimedLocally: true) : r,
            )
            .toList();
    await prefs.setStringList(
      key,
      updated.map((r) => jsonEncode(r.toJson())).toList(),
    );
    _myPots = updated;
    notifyListeners();
  }

  /// Load the locally-recorded pots for the current wallet. Best-effort
  /// cross-checks each against the live on-chain Position account (if the
  /// arena service is already initialized) to refresh the claimed flag.
  Future<void> loadMyPots({required String walletAddress}) async {
    _isLoadingMyPots = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _prefsKey(walletAddress);
      final storedJson = prefs.getStringList(key) ?? [];
      var records =
          storedJson
              .map(
                (s) =>
                    MyPotRecord.fromJson(jsonDecode(s) as Map<String, dynamic>),
              )
              .toList();

      final service = _arenaService;
      if (service != null) {
        final refreshed = <MyPotRecord>[];
        for (final record in records) {
          final position = await service.getPosition(matchId: record.matchId);
          final onChainClaimed = position?['claimed'] as bool?;
          refreshed.add(
            onChainClaimed != null
                ? record.copyWith(claimedLocally: onChainClaimed)
                : record,
          );
        }
        records = refreshed;
        await prefs.setStringList(
          key,
          records.map((r) => jsonEncode(r.toJson())).toList(),
        );
      }

      try {
        final serverPositions = await _backendService.fetchMyPositions(
          walletAddress: walletAddress,
        );
        if (serverPositions.isNotEmpty) {
          final localBySignature = {
            for (final record in records) record.txSignature: record,
          };
          final mergedBySignature = <String, MyPotRecord>{};

          for (final position in serverPositions) {
            final local = localBySignature[position.txSignature];
            mergedBySignature[position.txSignature] = position.toMyPotRecord(
              claimedLocally: local?.claimedLocally ?? false,
            );
          }

          for (final record in records) {
            mergedBySignature.putIfAbsent(record.txSignature, () => record);
          }

          records = mergedBySignature.values.toList();
          await prefs.setStringList(
            key,
            records.map((r) => jsonEncode(r.toJson())).toList(),
          );
        }
      } catch (e) {
        log('⚠️ ArenaProvider.fetchMyPositions failed: $e');
      }

      records.sort((a, b) => b.placedAt.compareTo(a.placedAt));
      _myPots = records;
    } catch (e) {
      log('❌ ArenaProvider.loadMyPots failed: $e');
    } finally {
      _isLoadingMyPots = false;
      notifyListeners();
    }
  }

  Future<void> loadActivity({
    String? walletAddress,
    String? matchId,
    ArenaFeedMode? mode,
  }) async {
    if (mode != null) _feedMode = mode;
    _isLoadingActivity = true;
    _activityError = null;
    notifyListeners();

    try {
      if (_feedMode == ArenaFeedMode.following && walletAddress != null) {
        _activity = await _backendService.fetchFollowingFeed(
          walletAddress: walletAddress,
        );
      } else {
        _activity = await _backendService.fetchActivity(
          walletAddress: matchId == null ? null : walletAddress,
          matchId: matchId,
        );
      }
    } catch (e) {
      log('❌ ArenaProvider.loadActivity failed: $e');
      _activityError = e.toString();
    } finally {
      _isLoadingActivity = false;
      notifyListeners();
    }
  }

  Future<void> loadHotCallers() async {
    _isLoadingHotCallers = true;
    notifyListeners();
    try {
      _hotCallers = await _backendService.fetchSocialLeaderboard(limit: 12);
    } catch (e) {
      log('⚠️ ArenaProvider.loadHotCallers failed: $e');
    } finally {
      _isLoadingHotCallers = false;
      notifyListeners();
    }
  }

  Future<void> loadClaimable({required String walletAddress}) async {
    _isLoadingClaimable = true;
    _claimableError = null;
    notifyListeners();
    try {
      _claimablePositions = await _backendService.fetchClaimable(
        walletAddress: walletAddress,
      );
    } catch (e) {
      log('ArenaProvider.loadClaimable failed: $e');
      _claimableError = e.toString();
    } finally {
      _isLoadingClaimable = false;
      notifyListeners();
    }
  }

  Future<void> loadNotifications({required String walletAddress}) async {
    _isLoadingNotifications = true;
    _notificationsError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _backendService.fetchNotifications(walletAddress: walletAddress),
        _backendService.fetchUnreadNotificationCount(
          walletAddress: walletAddress,
        ),
      ]);
      _notifications = results[0] as List<ArenaNotification>;
      _unreadNotificationCount = results[1] as int;
    } catch (e) {
      log('ArenaProvider.loadNotifications failed: $e');
      _notificationsError = e.toString();
    } finally {
      _isLoadingNotifications = false;
      notifyListeners();
    }
  }

  Future<void> loadSocialInbox({required String walletAddress}) async {
    await Future.wait([
      loadClaimable(walletAddress: walletAddress),
      loadNotifications(walletAddress: walletAddress),
    ]);
  }

  Future<void> subscribeNotifications({required String walletAddress}) async {
    if (_notificationWallet == walletAddress && _notificationChannel != null) {
      return;
    }
    await _unsubscribeNotifications();
    _notificationWallet = walletAddress;
    final channel = Supabase.instance.client.channel(
      'arena-notifications:$walletAddress',
    );
    _notificationChannel = channel;
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notification_outbox',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_wallet_address',
            value: walletAddress,
          ),
          callback: (_) {
            unawaited(loadSocialInbox(walletAddress: walletAddress));
          },
        )
        .subscribe();
  }

  Future<void> markNotificationsRead({
    required MwaAuthProvider authProvider,
    List<String>? notificationIds,
  }) async {
    final wallet = authProvider.walletAddress;
    if (wallet == null) throw StateError('Connect your wallet first.');
    final proof = await _signGenericAction(
      authProvider: authProvider,
      action: 'read_notifications',
    );
    await _backendService.markNotificationsRead(
      walletAddress: wallet,
      notificationIds: notificationIds,
      timestamp: proof.timestamp,
      signature: proof.signature,
    );
    final readAt = DateTime.now();
    _notifications =
        _notifications
            .map(
              (notification) =>
                  notificationIds == null ||
                          notificationIds.contains(notification.id)
                      ? notification.copyWith(readAt: readAt)
                      : notification,
            )
            .toList();
    _unreadNotificationCount =
        _notifications.where((item) => item.isUnread).length;
    notifyListeners();
  }

  Future<void> linkOAuthIdentity({
    required MwaAuthProvider authProvider,
    required OAuthProvider provider,
  }) async {
    final wallet = authProvider.walletAddress;
    if (wallet == null) throw StateError('Connect your wallet first.');
    if (provider != OAuthProvider.google && provider != OAuthProvider.twitter) {
      throw ArgumentError('Only Google and X can be linked here.');
    }

    _isLinkingIdentity = true;
    notifyListeners();
    StreamSubscription<AuthState>? subscription;
    try {
      final signedIn = Completer<Session>();
      subscription = Supabase.instance.client.auth.onAuthStateChange.listen((
        state,
      ) {
        if (state.event == AuthChangeEvent.signedIn &&
            state.session != null &&
            !signedIn.isCompleted) {
          signedIn.complete(state.session!);
        }
      });
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: 'dev.cleva.chumbucket://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      final session = await signedIn.future.timeout(const Duration(minutes: 2));
      final proof = await _signGenericAction(
        authProvider: authProvider,
        action: 'link_identity',
      );
      await _backendService.linkIdentity(
        walletAddress: wallet,
        accessToken: session.accessToken,
        timestamp: proof.timestamp,
        signature: proof.signature,
      );
    } finally {
      await subscription?.cancel();
      _isLinkingIdentity = false;
      notifyListeners();
    }
  }

  Future<void> loadMatchCallers({
    required String matchId,
    int limit = 50,
    bool force = false,
  }) async {
    if (!force &&
        (_matchCallersByMatchId.containsKey(matchId) ||
            _loadingMatchCallerIds.contains(matchId))) {
      return;
    }

    _loadingMatchCallerIds.add(matchId);
    _matchCallerErrorIds.remove(matchId);
    notifyListeners();
    try {
      _matchCallersByMatchId[matchId] = await _backendService.fetchMatchCallers(
        matchId: matchId,
        limit: limit,
      );
    } catch (e) {
      log('⚠️ ArenaProvider.loadMatchCallers failed: $e');
      _matchCallerErrorIds.add(matchId);
    } finally {
      _loadingMatchCallerIds.remove(matchId);
      notifyListeners();
    }
  }

  Future<ArenaSocialProfile?> loadProfile({
    required String targetWallet,
    String? viewerWallet,
  }) async {
    _profileError = null;
    notifyListeners();
    try {
      final profile = await _backendService.fetchProfile(
        walletAddress: targetWallet,
      );
      _profileCache[targetWallet] = profile;
      if (viewerWallet != null && viewerWallet != targetWallet) {
        final following = await _backendService.isFollowing(
          viewerWallet: viewerWallet,
          targetWallet: targetWallet,
        );
        if (following) {
          _followedWallets.add(targetWallet);
        } else {
          _followedWallets.remove(targetWallet);
        }
      }
      return profile;
    } catch (e) {
      log('❌ ArenaProvider.loadProfile failed: $e');
      _profileError = e.toString();
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Batch-resolve wallets to their linked X/Google identity, caching results
  /// so repeated calls (e.g. from a rebuilding list) skip wallets already
  /// cached or already in flight. Best-effort — a failure here just leaves
  /// [walletProfile] returning null, falling back to a raw-wallet display.
  Future<void> loadWalletProfiles(List<String> wallets) async {
    final toFetch =
        wallets
            .toSet()
            .where(
              (w) =>
                  w.isNotEmpty &&
                  !_walletProfileCache.containsKey(w) &&
                  !_walletProfilesInFlight.contains(w),
            )
            .toList();
    if (toFetch.isEmpty) return;
    _walletProfilesInFlight.addAll(toFetch);
    try {
      final profiles = await _backendService.fetchWalletProfiles(
        wallets: toFetch,
      );
      for (final p in profiles) {
        _walletProfileCache[p.walletAddress] = p;
      }
      notifyListeners();
    } catch (e) {
      log('❌ ArenaProvider.loadWalletProfiles failed: $e');
    } finally {
      _walletProfilesInFlight.removeAll(toFetch);
    }
  }

  Future<void> toggleFollow({
    required MwaAuthProvider authProvider,
    required String targetWallet,
  }) async {
    final wallet = authProvider.walletAddress;
    if (wallet == null) {
      throw StateError('Connect your wallet first.');
    }
    if (wallet == targetWallet) return;

    final currentlyFollowing = _followedWallets.contains(targetWallet);
    _followBusyWallets.add(targetWallet);
    notifyListeners();

    try {
      final action = currentlyFollowing ? 'unfollow' : 'follow';
      final proof = await _signSocialAction(
        authProvider: authProvider,
        action: action,
        targetWallet: targetWallet,
      );
      if (currentlyFollowing) {
        await _backendService.unfollowWallet(
          walletAddress: wallet,
          targetWallet: targetWallet,
          timestamp: proof.timestamp,
          signature: proof.signature,
        );
        _followedWallets.remove(targetWallet);
      } else {
        await _backendService.followWallet(
          walletAddress: wallet,
          targetWallet: targetWallet,
          timestamp: proof.timestamp,
          signature: proof.signature,
        );
        _followedWallets.add(targetWallet);
      }
      unawaited(loadActivity(walletAddress: wallet));
    } finally {
      _followBusyWallets.remove(targetWallet);
      notifyListeners();
    }
  }

  Future<void> loadPendingTargets({
    required String walletAddress,
    int limit = 50,
  }) async {
    _isLoadingPendingTargets = true;
    _pendingTargetsError = null;
    notifyListeners();
    try {
      _pendingTargets = await _backendService.fetchPendingTargets(
        wallet: walletAddress,
        limit: limit,
      );
    } catch (e) {
      log('⚠️ ArenaProvider.loadPendingTargets failed: $e');
      _pendingTargetsError = e.toString();
    } finally {
      _isLoadingPendingTargets = false;
      notifyListeners();
    }
  }

  /// Add a friend by X handle when they haven't joined ChumBucket yet - the
  /// Venmo-style "pending, resolves automatically once they link that handle
  /// for real" pattern. If [xHandle] already belongs to a linked wallet, the
  /// backend hands that wallet straight back (`alreadyResolved: true`) and
  /// the caller should treat it exactly like a normal add-by-wallet; if not,
  /// it's recorded server-side and this method's return value carries no
  /// wallet - never imply the target is aware of the pending invite.
  Future<ArenaCreatePendingTargetResult> addPendingTargetByHandle({
    required MwaAuthProvider authProvider,
    required String xHandle,
  }) async {
    final wallet = authProvider.walletAddress;
    if (wallet == null) {
      throw StateError('Connect your wallet first.');
    }

    final normalized = _normalizeHandle(xHandle);
    if (normalized.isEmpty) {
      throw ArgumentError('Enter a valid X handle.');
    }

    _pendingTargetBusyHandles.add(normalized);
    notifyListeners();
    try {
      final proof = await _signSocialAction(
        authProvider: authProvider,
        action: 'add_pending_target',
        targetWallet: normalized,
      );
      final result = await _backendService.createPendingTarget(
        wallet: wallet,
        providerUsername: normalized,
        timestamp: proof.timestamp,
        signature: proof.signature,
      );
      unawaited(loadPendingTargets(walletAddress: wallet));
      return result;
    } finally {
      _pendingTargetBusyHandles.remove(normalized);
      notifyListeners();
    }
  }

  /// Lowercase, strip any leading '@' - MUST match the backend's
  /// normalization exactly, since the same string is both what gets signed
  /// (as the `target` token in the `add_pending_target` message) and what's
  /// sent as `providerUsername`; the backend re-derives the message from
  /// `providerUsername` to verify the signature byte-for-byte.
  static String _normalizeHandle(String raw) =>
      raw.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  Future<_SignedProof> _signSocialAction({
    required MwaAuthProvider authProvider,
    required String action,
    required String targetWallet,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final message =
        'ChumBucket: $action $targetWallet\n'
        'net:${NetworkConfig.currentNetwork}\n'
        'ts:$timestamp';
    return _signMessage(authProvider, message, timestamp);
  }

  Future<_SignedProof> _signCallProof({
    required MwaAuthProvider authProvider,
    required String matchId,
    required String bucket,
    required BigInt stakeBaseUnits,
    required String txSignature,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final message =
        'ChumBucket: call $matchId $bucket $stakeBaseUnits $txSignature\n'
        'net:${NetworkConfig.currentNetwork}\n'
        'ts:$timestamp';
    return _signMessage(authProvider, message, timestamp);
  }

  Future<_SignedProof> _signGenericAction({
    required MwaAuthProvider authProvider,
    required String action,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final message =
        'ChumBucket: $action\n'
        'net:${NetworkConfig.currentNetwork}\n'
        'ts:$timestamp';
    return _signMessage(authProvider, message, timestamp);
  }

  Future<void> _unsubscribeNotifications() async {
    final channel = _notificationChannel;
    _notificationChannel = null;
    _notificationWallet = null;
    if (channel != null) {
      await Supabase.instance.client.removeChannel(channel);
    }
  }

  @override
  void dispose() {
    unawaited(_unsubscribeNotifications());
    super.dispose();
  }

  Future<_SignedProof> _signMessage(
    MwaAuthProvider authProvider,
    String message,
    int timestamp,
  ) async {
    final publicKeyBytes = authProvider.publicKeyBytes;
    if (publicKeyBytes == null) {
      throw StateError('Wallet public key is not available.');
    }
    final session = await authProvider.createSigningSession();
    if (session == null) {
      throw StateError('Could not open wallet signing session.');
    }
    try {
      final result = await session.signMessages(
        messages: [Uint8List.fromList(utf8.encode(message))],
        addresses: [publicKeyBytes],
      );
      final signed =
          result.signedMessages.isNotEmpty ? result.signedMessages.first : null;
      final signatureBytes =
          signed != null && signed.signatures.isNotEmpty
              ? signed.signatures.first
              : null;
      if (signatureBytes == null) {
        throw StateError('Wallet did not sign the message.');
      }
      return _SignedProof(
        timestamp: timestamp,
        signature: base58encode(signatureBytes),
      );
    } finally {
      await session.close();
    }
  }
}

class _SignedProof {
  final int timestamp;
  final String signature;

  const _SignedProof({required this.timestamp, required this.signature});
}
