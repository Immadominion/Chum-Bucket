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
    _instance ??= ChallengeStateProvider._internal();
    return _instance!;
  }

  ChallengeStateProvider._internal();

  List<Challenge> _challenges = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  DateTime? _lastUpdate;
  String? _currentUserId;

  // Getters
  List<Challenge> get challenges => List.unmodifiable(_challenges);
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  DateTime? get lastUpdate => _lastUpdate;

  // Get challenges sorted by creation date (most recent first)
  List<Challenge> get sortedChallenges {
    final sorted = [..._challenges];
    sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  // Get pending challenges only
  List<Challenge> get pendingChallenges {
    return _challenges
        .where((c) => c.status == ChallengeStatus.pending)
        .toList();
  }

  /// Initialize the provider with user data
  Future<void> initialize(String userId, {String? walletAddress}) async {
    if (_currentUserId == userId && _challenges.isNotEmpty) {
      AppLogger.debug('ChallengeState: Already initialized for user $userId');
      return; // Already initialized for this user
    }

    _currentUserId = userId;
    _isLoading = true;

    try {
      // Load from database immediately (fast)
      await _loadFromDatabase(userId);

      // Trigger background sync if wallet is available (non-blocking)
      if (walletAddress != null) {
        _triggerBackgroundSync(userId, walletAddress);
      }
    } catch (e) {
      AppLogger.error('ChallengeState: Initialize error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load challenges from local database (fast)
  Future<void> _loadFromDatabase(String userId) async {
    try {
      final dbChallenges = await UnifiedDatabaseService.getChallengesForUser(
        userId,
      );
      _challenges = dbChallenges;
      _lastUpdate = DateTime.now();

      AppLogger.info(
        'ChallengeState: Loaded ${_challenges.length} challenges from database',
      );
      notifyListeners();
    } catch (e) {
      AppLogger.error('ChallengeState: Database load error: $e');
    }
  }

  /// Trigger background sync (non-blocking)
  void _triggerBackgroundSync(String userId, String walletAddress) {
    if (_isSyncing) return;

    _isSyncing = true;
    notifyListeners();

    // Run sync in background without blocking UI
    EfficientSyncService.instance
        .forceBlockchainSync(userId: userId, walletAddress: walletAddress)
        .then((_) async {
          // Reload from database after sync
          await _loadFromDatabase(userId);
        })
        .catchError((e) {
          AppLogger.error('ChallengeState: Background sync error: $e');
        })
        .whenComplete(() {
          _isSyncing = false;
          notifyListeners();
        });
  }

  /// Force refresh (for pull-to-refresh)
  Future<void> forceRefresh(String userId, String walletAddress) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Force blockchain sync
      await EfficientSyncService.instance.forceBlockchainSync(
        userId: userId,
        walletAddress: walletAddress,
      );

      // Reload from database
      await _loadFromDatabase(userId);
    } catch (e) {
      AppLogger.error('ChallengeState: Force refresh error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a new challenge (when created)
  void addChallenge(Challenge challenge) {
    // Check for duplicates by escrow address or ID
    final existingIndex = _challenges.indexWhere(
      (c) =>
          c.id == challenge.id ||
          (c.escrowAddress != null &&
              c.escrowAddress == challenge.escrowAddress),
    );

    if (existingIndex >= 0) {
      // Update existing challenge
      _challenges[existingIndex] = challenge;
      AppLogger.info(
        'ChallengeState: Updated existing challenge ${challenge.id}',
      );
    } else {
      // Add new challenge
      _challenges.add(challenge);
      AppLogger.info('ChallengeState: Added new challenge ${challenge.id}');
    }

    _lastUpdate = DateTime.now();
    notifyListeners();
  }

  /// Update challenge status (when resolved)
  void updateChallenge(String challengeId, Map<String, dynamic> updates) {
    final index = _challenges.indexWhere((c) => c.id == challengeId);
    if (index >= 0) {
      final challenge = _challenges[index];

      // Update the challenge with new data
      _challenges[index] = Challenge(
        id: challenge.id,
        creatorId: challenge.creatorId,
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
        winnerId: updates['winnerId'] ?? challenge.winnerId,
        transactionSignature:
            updates['transactionSignature'] ?? challenge.transactionSignature,
        feeTransactionSignature:
            updates['feeTransactionSignature'] ??
            challenge.feeTransactionSignature,
      );

      _lastUpdate = DateTime.now();
      AppLogger.info('ChallengeState: Updated challenge $challengeId');
      notifyListeners();
    }
  }

  /// Parse status string to enum
  ChallengeStatus _parseStatus(dynamic status) {
    if (status is ChallengeStatus) return status;

    final statusStr = status.toString().toLowerCase();
    switch (statusStr) {
      case 'pending':
        return ChallengeStatus.pending;
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
    _challenges.clear();
    _isLoading = false;
    _isSyncing = false;
    _lastUpdate = null;
    _currentUserId = null;
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

    await _loadFromDatabase(userId);
    _removeDuplicates();
  }
}
