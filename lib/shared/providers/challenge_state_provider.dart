import 'package:flutter/foundation.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// Reactive challenge state provider that manages challenge data across the app
/// Eliminates the need for frequent database queries and provides real-time updates
class ChallengeStateProvider extends ChangeNotifier {
  static ChallengeStateProvider? _instance;
  static ChallengeStateProvider get instance {
    _instance ??= ChallengeStateProvider();
    return _instance!;
  }

  ChallengeStateProvider({
    Future<List<Challenge>> Function(String)? loadChallenges,
  }) : _readChallenges =
           loadChallenges ?? UnifiedDatabaseService.getChallengesForUser;
  final Future<List<Challenge>> Function(String) _readChallenges;
  int _accountEpoch = 0;

  List<Challenge> _challenges = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  DateTime? _lastUpdate;
  DateTime? _lastSyncTime; // Throttle sync calls
  String? _currentUserId;
  bool _isInitialized = false; // Track if already initialized
  bool _isInitializing = false; // Lock to prevent concurrent initialization

  // Throttle constants
  static const Duration _minSyncInterval = Duration(seconds: 30);
  static const Duration _minDbLoadInterval = Duration(seconds: 5);

  // Getters
  List<Challenge> get challenges => List.unmodifiable(_challenges);
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  DateTime? get lastUpdate => _lastUpdate;
  bool get isInitialized => _isInitialized;

  // Get challenges sorted by creation date (most recent first)
  List<Challenge> get sortedChallenges {
    final sorted = [..._challenges];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// Earlier escrow challenges that may still hold SOL: not yet resolved or
  /// cancelled. The database writes `active` for a new escrow and `pending`
  /// for older rows; `expired` only means the deadline passed, which the
  /// escrow program does not enforce, so the witness can still settle it.
  List<Challenge> get openChallenges {
    return _challenges.where((c) => isOpenStatus(c.status)).toList();
  }

  static bool isOpenStatus(ChallengeStatus status) =>
      status == ChallengeStatus.pending ||
      status == ChallengeStatus.active ||
      status == ChallengeStatus.expired;

  /// Initialize the provider with user data (only once per user)
  Future<void> initialize(String userId, {String? walletAddress}) async {
    AppLogger.info('ChallengeState: initialize() called with userId: $userId');
    AppLogger.info(
      'ChallengeState: Current state - isInitialized: $_isInitialized, currentUserId: $_currentUserId',
    );

    // Check if initialized for a DIFFERENT user - if so, clear and reinit
    if (_currentUserId != null && _currentUserId != userId) {
      AppLogger.info(
        'ChallengeState: User changed from $_currentUserId to $userId - clearing old state',
      );
      clear();
    }

    // Prevent multiple initializations for the same user
    if (_isInitialized && _currentUserId == userId) {
      AppLogger.debug('ChallengeState: Already initialized for user $userId');
      return;
    }

    // Prevent concurrent initialization attempts
    if (_isInitializing) {
      AppLogger.debug('ChallengeState: Initialization already in progress');
      return;
    }

    AppLogger.info(
      'ChallengeState: Starting fresh initialization for user $userId',
    );
    _isInitializing = true;
    final epoch = _accountEpoch;
    _currentUserId = userId;
    _isLoading = true;
    notifyListeners();

    try {
      // Clear any existing challenges first
      _challenges.clear();

      // Load from database immediately (fast)
      await _loadFromDatabase(userId, notify: false);
      if (epoch != _accountEpoch) return;
      _isInitialized = true;

      // DON'T auto-trigger blockchain sync on initialize
      // User must explicitly pull-to-refresh for blockchain sync
      AppLogger.info(
        'ChallengeState: Initialized with ${_challenges.length} challenges from database',
      );
    } catch (e) {
      AppLogger.error('ChallengeState: Initialize error: $e');
    } finally {
      if (epoch == _accountEpoch) {
        _isLoading = false;
        _isInitializing = false;
        notifyListeners();
      }
    }
  }

  /// Load challenges from local database (fast) with throttling
  Future<void> _loadFromDatabase(String userId, {bool notify = true}) async {
    final epoch = _accountEpoch;
    // Throttle database loads
    if (_lastUpdate != null) {
      final timeSinceLastLoad = DateTime.now().difference(_lastUpdate!);
      if (timeSinceLastLoad < _minDbLoadInterval) {
        AppLogger.debug('ChallengeState: Skipping db load (throttled)');
        return;
      }
    }

    try {
      final dbChallenges = await _readChallenges(userId);
      if (epoch != _accountEpoch || _currentUserId != userId) return;
      _challenges = dbChallenges;
      _lastUpdate = DateTime.now();

      AppLogger.info(
        'ChallengeState: Loaded ${_challenges.length} challenges from database',
      );
      if (notify) notifyListeners();
    } catch (e) {
      AppLogger.error('ChallengeState: Database load error: $e');
    }
  }

  /// Force refresh (for pull-to-refresh ONLY) with throttling
  Future<void> forceRefresh(String userId, String walletAddress) async {
    if (_currentUserId != userId) return;
    final epoch = _accountEpoch;
    // Throttle sync calls to prevent spam
    if (_lastSyncTime != null) {
      final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);
      if (timeSinceLastSync < _minSyncInterval) {
        AppLogger.info(
          'ChallengeState: Skipping refresh (throttled - ${_minSyncInterval.inSeconds - timeSinceLastSync.inSeconds}s remaining)',
        );
        // Just reload from database instead
        await _loadFromDatabase(userId);
        return;
      }
    }

    // Prevent concurrent syncs
    if (_isSyncing) {
      AppLogger.debug('ChallengeState: Sync already in progress');
      return;
    }

    _isLoading = true;
    _isSyncing = true;
    notifyListeners();

    try {
      _lastSyncTime = DateTime.now();

      // Force blockchain sync
      await EfficientSyncService.instance.forceBlockchainSync(
        userId: userId,
        walletAddress: walletAddress,
      );
      if (epoch != _accountEpoch) return;

      // Reload from database (don't notify yet)
      await _loadFromDatabase(userId, notify: false);
    } catch (e) {
      AppLogger.error('ChallengeState: Force refresh error: $e');
    } finally {
      if (epoch == _accountEpoch) {
        _isLoading = false;
        _isSyncing = false;
        notifyListeners();
      }
    }
  }

  /// Update challenge status (when resolved)
  Future<void> updateChallenge(
    String challengeId,
    Map<String, dynamic> updates,
  ) async {
    final index = _challenges.indexWhere((c) => c.id == challengeId);
    if (index >= 0) {
      final challenge = _challenges[index];

      // Update the challenge with new data
      final updatedChallenge = Challenge(
        id: challenge.id,
        creatorId: challenge.creatorId,
        member1Address: challenge.member1Address, // Preserve initiator wallet
        participantId: updates['participantId'] ?? challenge.participantId,
        participantEmail:
            updates['participantEmail'] ?? challenge.participantEmail,
        title: updates['title'] ?? challenge.title,
        description: updates['description'] ?? challenge.description,
        amount: updates['amount'] ?? challenge.amount,
        platformFee: updates['platformFee'] ?? challenge.platformFee,
        winnerAmount: updates['winnerAmount'] ?? challenge.winnerAmount,
        createdAt: challenge.createdAt,
        expiresAt: updates['expiresAt'] ?? challenge.expiresAt,
        completedAt: updates['completedAt'] ?? challenge.completedAt,
        status:
            updates['status'] != null
                ? _parseStatus(updates['status'])
                : challenge.status,
        escrowAddress: updates['escrowAddress'] ?? challenge.escrowAddress,
        vaultAddress: updates['vaultAddress'] ?? challenge.vaultAddress,
        witnessAddress: challenge.witnessAddress,
        witnessDisplayName: challenge.witnessDisplayName,
        winnerId: updates['winnerId'] ?? challenge.winnerId,
        transactionSignature:
            updates['transactionSignature'] ?? challenge.transactionSignature,
        feeTransactionSignature:
            updates['feeTransactionSignature'] ??
            challenge.feeTransactionSignature,
      );

      _challenges[index] = updatedChallenge;
      _lastUpdate = DateTime.now();
      AppLogger.info('ChallengeState: Updated challenge $challengeId');
      notifyListeners();

      // Persist to database - await to ensure it completes
      await _persistChallengeUpdate(updatedChallenge);
    }
  }

  /// Persist challenge update to database
  Future<void> _persistChallengeUpdate(Challenge challenge) async {
    try {
      AppLogger.info(
        'ChallengeState: Persisting challenge ${challenge.id} - status: ${challenge.status.name}, winnerId: ${challenge.winnerId}',
      );
      final success = await UnifiedDatabaseService.updateChallengeStatus(
        challenge.id,
        challenge.status.name,
        winnerId: challenge.winnerId,
        completedAt: challenge.completedAt,
      );
      if (success) {
        AppLogger.info(
          'ChallengeState: ✅ Successfully persisted challenge ${challenge.id} to database',
        );
      } else {
        AppLogger.warning(
          'ChallengeState: ⚠️ Database update returned false for ${challenge.id}',
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('ChallengeState: ❌ Failed to persist challenge: $e');
      AppLogger.error('Stack trace: $stackTrace');
      // Don't throw - UI already updated, db sync will catch up later
    }
  }

  /// Parse status string to enum
  ChallengeStatus _parseStatus(dynamic status) {
    if (status is ChallengeStatus) return status;

    final statusStr = status.toString().toLowerCase();
    switch (statusStr) {
      case 'pending':
        return ChallengeStatus.pending;
      case 'active': // Database uses 'active' for newly created challenges
        return ChallengeStatus.active;
      case 'accepted':
        return ChallengeStatus.accepted;
      case 'funded':
        return ChallengeStatus.funded;
      case 'completed':
        return ChallengeStatus.completed;
      case 'failed':
        return ChallengeStatus.failed;
      case 'cancelled':
        return ChallengeStatus.cancelled;
      case 'expired':
        return ChallengeStatus.expired;
      default:
        return ChallengeStatus.pending;
    }
  }

  /// Clear state (for logout)
  void clear() {
    _accountEpoch++;
    AppLogger.info('ChallengeState: Clearing all state for logout');
    _challenges.clear();
    _isLoading = false;
    _isSyncing = false;
    _lastUpdate = null;
    _lastSyncTime = null;
    _currentUserId = null;
    _isInitialized = false;
    _isInitializing = false;
    AppLogger.info(
      'ChallengeState: State cleared - challenges: ${_challenges.length}, isInitialized: $_isInitialized',
    );
    notifyListeners();
  }

  /// Get challenge by ID
  Challenge? getChallengeById(String id) {
    try {
      return _challenges.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Remove duplicate challenges based on escrow address
  void _removeDuplicates() {
    final seen = <String>{};
    _challenges.removeWhere((challenge) {
      final key = challenge.escrowAddress ?? challenge.id;
      if (seen.contains(key)) {
        AppLogger.info('ChallengeState: Removed duplicate challenge $key');
        return true;
      }
      seen.add(key);
      return false;
    });
  }

  /// Soft refresh (only database, no blockchain sync)
  Future<void> softRefresh(String userId) async {
    if (_currentUserId != userId) return;
    final epoch = _accountEpoch;

    await _loadFromDatabase(userId);
    if (epoch != _accountEpoch) return;
    _removeDuplicates();
  }
}
