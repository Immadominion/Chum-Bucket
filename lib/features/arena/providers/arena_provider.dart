import 'dart:convert';
import 'dart:async';
import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:chumbucket/core/utils/base_change_notifier.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_backend_service.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/data/match_arena_service.dart';

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

  List<ArenaActivityEvent> get activity => List.unmodifiable(_activity);
  bool get isLoadingActivity => _isLoadingActivity;
  String? get activityError => _activityError;

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

  /// Stake USDC on [bucket] for [match]. Requires [ensureArenaService] to
  /// have been called first (and to have succeeded).
  Future<String> placeCall({
    required ArenaMatchEntry match,
    required int bucket,
    required double amountUsdc,
  }) async {
    final service = _arenaService;
    if (service == null) {
      throw StateError('Arena service is not initialized yet');
    }

    final signature = await service.placeCall(
      matchId: match.fixture.matchId,
      bucket: bucket,
      amountUsdc: amountUsdc,
    );

    await _recordMyPot(
      MyPotRecord(
        matchId: match.fixture.matchId,
        home: match.fixture.home,
        away: match.fixture.away,
        bucket: bucket,
        amountUsdc: amountUsdc,
        txSignature: signature,
        placedAt: DateTime.now(),
      ),
    );

    unawaited(
      _backendService
          .recordPredictionCall(
            walletAddress: service.walletAddress,
            matchId: match.fixture.matchId,
            bucket: bucket,
            stakeBaseUnits: BigInt.from(
              MatchArenaService.usdcToBaseUnits(amountUsdc),
            ),
            txSignature: signature,
            metadata: {
              'home': match.fixture.home,
              'away': match.fixture.away,
              'competition': match.fixture.competition,
              'kickoff': match.fixture.kickoff.toIso8601String(),
            },
          )
          .catchError((e) {
            // Social mirroring is best-effort here. The transaction already landed
            // and the backend indexer can reconcile by signature later.
            log('⚠️ ArenaProvider.recordPredictionCall failed: $e');
          }),
    );

    return signature;
  }

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

  Future<void> loadActivity({String? walletAddress, String? matchId}) async {
    _isLoadingActivity = true;
    _activityError = null;
    notifyListeners();

    try {
      _activity = await _backendService.fetchActivity(
        walletAddress: walletAddress,
        matchId: matchId,
      );
    } catch (e) {
      log('❌ ArenaProvider.loadActivity failed: $e');
      _activityError = e.toString();
    } finally {
      _isLoadingActivity = false;
      notifyListeners();
    }
  }
}
