import 'package:chumbucket/core/utils/app_logger.dart';
import 'dart:async';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/services/blockchain_sync_service.dart';
import 'package:chumbucket/shared/services/local_database_service.dart';
import 'package:solana/solana.dart' as solana;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Efficient local-first sync service that minimizes blockchain calls
/// Following best practices for web3 apps and mobile performance:
///
/// ## Database-First Approach:
/// 1. ALWAYS load from local database FIRST (instant UI, no blockchain blocking)
/// 2. Return database results immediately to prevent UI blocking
/// 3. Handle blockchain sync in background, never blocking user experience
///
/// ## Smart Blockchain Verification:
/// 1. Only verify with blockchain when necessary (not every hot restart)
/// 2. Intelligent sync intervals: 10min normal, 30min verification
/// 3. Skip verification when app is backgrounded (save battery/data)
/// 4. Prioritize pending challenges for status updates
///
/// ## Performance Features:
/// - Prevents duplicate sync operations
/// - App lifecycle awareness (pause/resume)
/// - Configurable sync intervals
/// - Background task management
/// - Resource-efficient mobile design
///
/// ## Usage Pattern:
/// ```dart
/// // UI gets instant data from database
/// final challenges = await EfficientSyncService.instance.getChallenges(
///   userId: userId,
///   walletAddress: walletAddress,
/// );
/// // Blockchain verification happens in background, doesn't block UI
/// ```
class EfficientSyncService {
  static EfficientSyncService? _instance;
  static EfficientSyncService get instance {
    _instance ??= EfficientSyncService._internal();
    return _instance!;
  }

  EfficientSyncService._internal();

  // Sync state tracking
  static final Map<String, DateTime> _lastSyncTimes = {};
  static const Duration _syncInterval = Duration(
    minutes: 5,
  ); // Sync every 10 minutes (less frequent)
  static const Duration _backgroundSyncInterval = Duration(
    minutes: 10,
  ); // Background sync every 30 minutes (much less frequent)
  static const Duration _verificationInterval = Duration(
    minutes: 30,
  ); // Blockchain verification every 30 minutes

  // Track if we're currently syncing to prevent duplicate calls
  static final Set<String> _activeSyncs = {};

  // Track app lifecycle for smart syncing
  static DateTime? _lastAppResumeTime;
  static bool _hasInitialSync = false;
  static bool _isAppInBackground = false;

  /// Force immediate blockchain sync (for pull-to-refresh)
  Future<void> forceBlockchainSync({
    required String userId,
    String? walletAddress,
  }) async {
    if (walletAddress == null) {
      AppLogger.debug(
        'No wallet address, skipping force sync',
        tag: 'EfficientSyncService',
      );
      return;
    }

    final key = '${userId}_$walletAddress';

    if (_activeSyncs.contains(key)) {
      AppLogger.debug(
        'Sync already in progress, skipping force sync',
        tag: 'EfficientSyncService',
      );
      return;
    }

    AppLogger.info(
      'Force blockchain sync triggered by user',
      tag: 'EfficientSyncService',
    );
    _activeSyncs.add(key);

    try {
      // Reset sync timestamps to force immediate verification
      _lastSyncTimes.remove(key);
      _lastSyncTimes.remove('verification_$key');

      // Build required clients
      final rpcUrl =
          dotenv.env['SOLANA_RPC_URL'] ?? 'https://api.devnet.solana.com';
      final wsUrl = rpcUrl.replaceFirst('http', 'ws');
      final solanaClient = solana.SolanaClient(
        rpcUrl: Uri.parse(rpcUrl),
        websocketUrl: Uri.parse(wsUrl),
      );
      final supabase = Supabase.instance.client;

      // Perform a real full sync with blockchain and update database
      final sync = BlockchainSyncService(
        solanaClient: solanaClient,
        supabase: supabase,
      );
      final onChain = await sync.fullSyncForUser(walletAddress, userId);

      // Get existing local challenges for the user to prevent duplicates
      final localChallenges = await UnifiedDatabaseService.getChallengesForUser(
        userId,
      );

      // Persist to local database via UnifiedDatabaseService
      for (final c in onChain) {
        // Try to find an existing challenge by multisig/escrow address
        Challenge? existing;
        for (final lc in localChallenges) {
          if (lc.escrowAddress != null && lc.escrowAddress == c.escrowAddress) {
            existing = lc;
            break;
          }
        }

        // Prefer existing human-authored text over generic on-chain placeholders
        String titleToUse = c.title;
        String descToUse = c.description;
        bool isGenericTitle(String t) {
          final s = t.trim().toLowerCase();
          return s == 'on-chain challenge' || s.startsWith('challenge: ');
        }

        bool isGenericDesc(String d) {
          final s = d.trim().toLowerCase();
          return s.startsWith('challenge discovered from blockchain');
        }

        if (existing != null) {
          if (isGenericTitle(titleToUse) &&
              (existing.title).trim().isNotEmpty) {
            titleToUse = existing.title;
          }
          if (isGenericDesc(descToUse) &&
              (existing.description).trim().isNotEmpty) {
            descToUse = existing.description;
          }
        }

        final participantIdToUse = existing?.participantId ?? c.participantId;
        final participantEmailToUse =
            existing?.participantEmail ?? c.participantEmail;

        final updateData = <String, dynamic>{
          'title': titleToUse,
          'description': descToUse,
          // Use local DB schema column names
          'amount_sol': c.amount,
          'platform_fee_sol': c.platformFee,
          'winner_amount_sol': c.winnerAmount,
          // Do not overwrite creator on update; keep existing DB value
          if (existing == null) 'creator_privy_id': userId,
          'participant_privy_id': participantIdToUse,
          'participant_email': participantEmailToUse,
          'status': c.status.toString().split('.').last,
          'created_at': c.createdAt.toIso8601String(),
          'expires_at': c.expiresAt.toIso8601String(),
          'multisig_address': c.escrowAddress,
          'vault_address': c.vaultAddress,
          'winner_privy_id': c.winnerId,
        };

        if (existing != null) {
          // Update existing row by its ID
          await UnifiedDatabaseService.updateChallenge(existing.id, updateData);
        } else {
          // Insert a new challenge locally using local schema
          final newChallenge = Challenge(
            id: c.id,
            creatorId: userId,
            participantId: participantIdToUse,
            participantEmail: participantEmailToUse,
            title: titleToUse,
            description: descToUse,
            amount: c.amount,
            platformFee: c.platformFee,
            winnerAmount: c.winnerAmount,
            createdAt: c.createdAt,
            expiresAt: c.expiresAt,
            completedAt: c.completedAt,
            status: c.status,
            escrowAddress: c.escrowAddress,
            vaultAddress: c.vaultAddress,
            winnerId: c.winnerId,
            transactionSignature: c.transactionSignature,
            feeTransactionSignature: c.feeTransactionSignature,
          );
          await LocalDatabaseService.insertChallenge(newChallenge);
        }
      }

      _lastSyncTimes[key] = DateTime.now();
      AppLogger.info(
        'Force blockchain sync completed',
        tag: 'EfficientSyncService',
      );
    } catch (e) {
      AppLogger.error(
        'Force blockchain sync error: $e',
        tag: 'EfficientSyncService',
      );
    } finally {
      _activeSyncs.remove(key);
    }
  }

  /// Get challenges with database-first approach
  Future<List<Challenge>> getChallenges({
    required String userId,
    required String? walletAddress,
    bool forceSync = false,
  }) async {
    AppLogger.debug(
      'Getting challenges for user $userId',
      tag: 'EfficientSyncService',
    );

    // 1. ALWAYS load from database first (fast local access)
    final dbChallenges = await UnifiedDatabaseService.getChallengesForUser(
      userId,
    );
    AppLogger.debug(
      'Found ${dbChallenges.length} challenges in database',
      tag: 'EfficientSyncService',
    );

    // 2. Determine if we need to sync with blockchain
    final shouldSync = _shouldSync(userId, walletAddress, forceSync);

    if (shouldSync && walletAddress != null) {
      // 3. Sync in background (non-blocking)
      _syncInBackground(userId, walletAddress);
    }

    // 4. Return database results immediately (no blockchain blocking)
    return dbChallenges;
  }

  /// Get participant wallet address for a challenge
  Future<String?> getParticipantWalletAddress(
    String challengeId,
    String participantPrivyId,
  ) async {
    return await UnifiedDatabaseService.getParticipantWalletAddress(
      challengeId,
      participantPrivyId,
    );
  }

  /// Smart sync decision logic
  bool _shouldSync(String userId, String? walletAddress, bool forceSync) {
    if (forceSync) return true;
    if (walletAddress == null) return false;

    final key = '${userId}_$walletAddress';

    // Don't sync if already syncing
    if (_activeSyncs.contains(key)) {
      AppLogger.debug(
        'EfficientSync: Already syncing for $key, skipping',
        tag: 'EfficientSyncService',
      );
      return false;
    }

    final lastSync = _lastSyncTimes[key];
    final now = DateTime.now();

    // Initial sync (app first load)
    if (!_hasInitialSync) {
      AppLogger.debug(
        'EfficientSync: Initial sync needed',
        tag: 'EfficientSyncService',
      );
      return true;
    }

    // App resume sync (if app was backgrounded and resumed)
    if (_lastAppResumeTime != null &&
        (lastSync == null || _lastAppResumeTime!.isAfter(lastSync))) {
      AppLogger.debug(
        'EfficientSync: App resume sync needed',
        tag: 'EfficientSyncService',
      );
      return true;
    }

    // Periodic sync
    if (lastSync == null || now.difference(lastSync) >= _syncInterval) {
      AppLogger.debug(
        'EfficientSync: Periodic sync needed (last: $lastSync)',
        tag: 'EfficientSyncService',
      );
      return true;
    }

    AppLogger.debug(
      'No sync needed (last sync: ${now.difference(lastSync)} ago)',
      tag: 'EfficientSyncService',
    );
    return false;
  }

  /// Background sync that doesn't block UI
  /// Smart verification approach:
  /// 1. Load from database FIRST (instant UI)
  /// 2. Periodically verify/sync with blockchain in background
  /// 3. Update database if discrepancies found
  /// 4. Only run verification when app is active and has good connection
  Future<void> _syncInBackground(String userId, String walletAddress) async {
    final key = '${userId}_$walletAddress';

    if (_activeSyncs.contains(key)) return;

    _activeSyncs.add(key);
    AppLogger.debug(
      'EfficientSync: Starting background verification for $key',
      tag: 'EfficientSyncService',
    );

    try {
      // Phase 1: Quick database check - verify data integrity
      final dbChallenges = await UnifiedDatabaseService.getChallengesForUser(
        userId,
      );
      AppLogger.debug(
        'EfficientSync: Found ${dbChallenges.length} challenges in database',
        tag: 'EfficientSyncService',
      );

      // Phase 2: Smart blockchain verification (only when needed)
      await _performSmartBlockchainVerification(
        userId,
        walletAddress,
        dbChallenges,
      );

      _lastSyncTimes[key] = DateTime.now();
      _hasInitialSync = true;

      AppLogger.debug(
        'EfficientSync: Background verification completed',
        tag: 'EfficientSyncService',
      );
    } catch (e) {
      AppLogger.debug(
        'EfficientSync: Background verification error: $e',
        tag: 'EfficientSyncService',
      );
      // Don't throw - we still have database data
    } finally {
      _activeSyncs.remove(key);
    }
  }

  /// Smart blockchain verification - only checks when discrepancies suspected
  Future<void> _performSmartBlockchainVerification(
    String userId,
    String walletAddress,
    List<Challenge> dbChallenges,
  ) async {
    AppLogger.debug(
      'EfficientSync: Starting smart blockchain verification',
      tag: 'EfficientSyncService',
    );

    // Only verify if:
    // 1. It's been more than 30 minutes since last verification
    // 2. OR if there are pending challenges (need status updates)
    // 3. OR if it's the first sync after app restart

    final key = '${userId}_$walletAddress';
    final lastVerification = _lastSyncTimes['verification_$key'];
    final now = DateTime.now();

    final shouldVerify =
        lastVerification == null ||
        now.difference(lastVerification) > _verificationInterval ||
        dbChallenges.any((c) => c.status == ChallengeStatus.pending) ||
        !_hasInitialSync;

    if (!shouldVerify) {
      AppLogger.debug(
        'EfficientSync: Skipping blockchain verification - not needed yet',
        tag: 'EfficientSyncService',
      );
      return;
    }

    AppLogger.debug(
      'EfficientSync: Performing selective blockchain verification...',
      tag: 'EfficientSyncService',
    );

    try {
      // TODO: Implement selective blockchain verification
      // For now, we'll mark verification as complete
      // In the future, this would:
      // 1. Check only pending challenges for status updates
      // 2. Verify challenge existence for recent challenges
      // 3. Update database if discrepancies found
      // 4. Add any missing challenges from blockchain

      _lastSyncTimes['verification_$key'] = now;
      AppLogger.debug(
        'EfficientSync: Blockchain verification completed (placeholder)',
        tag: 'EfficientSyncService',
      );
    } catch (e) {
      AppLogger.debug(
        'EfficientSync: Blockchain verification failed: $e',
        tag: 'EfficientSyncService',
      );
      // Don't throw - database data is still valid
    }
  }

  /// Call when app resumes from background
  void onAppResume() {
    _lastAppResumeTime = DateTime.now();
    _isAppInBackground = false;
    AppLogger.debug(
      'EfficientSync: App resumed at $_lastAppResumeTime',
      tag: 'EfficientSyncService',
    );
  }

  /// Call when app goes to background
  void onAppPause() {
    _isAppInBackground = true;
    AppLogger.debug('EfficientSync: App paused', tag: 'EfficientSyncService');
  }

  /// Manual sync trigger (for pull-to-refresh, etc.)
  Future<List<Challenge>> forceSync({
    required String userId,
    required String walletAddress,
  }) async {
    AppLogger.debug(
      'EfficientSync: Force sync requested',
      tag: 'EfficientSyncService',
    );
    return getChallenges(
      userId: userId,
      walletAddress: walletAddress,
      forceSync: true,
    );
  }

  /// Background periodic sync task
  Future<void> startBackgroundSync({
    required String userId,
    required String walletAddress,
  }) async {
    AppLogger.debug(
      'EfficientSync: Starting background sync task',
      tag: 'EfficientSyncService',
    );

    // Don't start multiple background tasks
    final key = '${userId}_$walletAddress';
    if (_activeSyncs.contains('bg_$key')) return;

    _activeSyncs.add('bg_$key');

    try {
      while (true) {
        await Future.delayed(_backgroundSyncInterval);

        if (!_activeSyncs.contains('bg_$key')) break; // Stop if cancelled

        // Only sync when app is in foreground to save battery and data
        if (!_isAppInBackground) {
          AppLogger.debug(
            'EfficientSync: Background sync tick',
            tag: 'EfficientSyncService',
          );
          await _syncInBackground(userId, walletAddress);
        } else {
          AppLogger.debug(
            'EfficientSync: Skipping background sync - app in background',
            tag: 'EfficientSyncService',
          );
        }
      }
    } catch (e) {
      AppLogger.debug(
        'EfficientSync: Background sync task error: $e',
        tag: 'EfficientSyncService',
      );
    } finally {
      _activeSyncs.remove('bg_$key');
    }
  }

  /// Stop background sync task
  void stopBackgroundSync({
    required String userId,
    required String walletAddress,
  }) {
    final key = '${userId}_$walletAddress';
    _activeSyncs.remove('bg_$key');
    AppLogger.debug(
      'EfficientSync: Stopped background sync for $key',
      tag: 'EfficientSyncService',
    );
  }

  /// Clear all sync state (for logout, etc.)
  void clearSyncState() {
    _lastSyncTimes.clear();
    _activeSyncs.clear();
    _hasInitialSync = false;
    _lastAppResumeTime = null;
    AppLogger.debug(
      'EfficientSync: Cleared all sync state',
      tag: 'EfficientSyncService',
    );
  }

  /// Get sync status for UI feedback
  Map<String, dynamic> getSyncStatus(String userId, String? walletAddress) {
    if (walletAddress == null) {
      return {'syncing': false, 'lastSync': null};
    }

    final key = '${userId}_$walletAddress';
    return {
      'syncing': _activeSyncs.contains(key),
      'lastSync': _lastSyncTimes[key],
    };
  }
}
