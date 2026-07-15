import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:solana/solana.dart' as solana;
import 'package:chumbucket/shared/services/pinocchio_escrow_service.dart';
import 'package:chumbucket/shared/services/realtime_service.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/config/network_config.dart';

/// MWA-compatible Challenge Service
/// Uses wallet_address as user identifier instead of privy_id
class MwaChallengeService {
  final SupabaseClient _supabase;
  PinocchioEscrowService? _escrowService;
  late final RealtimeService _realtimeService;

  // Platform configuration - Simple flat fee structure
  // 2.5% fee, capped at 0.1 SOL (~$20)
  static const double FEE_PERCENTAGE = 0.025; // 2.5%
  static const double MAX_FEE_SOL = 0.1; // Cap fee at 0.1 SOL (~$20)

  String get platformWalletAddress =>
      dotenv.env['PLATFORM_WALLET_ADDRESS'] ??
      PinocchioEscrowService.PLATFORM_FEE_WALLET;

  // Getters for accessing services
  RealtimeService get realtimeService => _realtimeService;
  PinocchioEscrowService get escrowService => _escrowService!;

  MwaChallengeService({required SupabaseClient supabase})
    : _supabase = supabase {
    _realtimeService = RealtimeService(supabase: _supabase);

    // Initialize unified database service with Supabase
    UnifiedDatabaseService.configure(supabase: _supabase);

    log('MwaChallengeService initialized');
  }

  /// Initialize the PinocchioEscrowService
  Future<void> initializeEscrow({required String rpcUrl}) async {
    final client = solana.SolanaClient(
      rpcUrl: Uri.parse(rpcUrl),
      websocketUrl: Uri.parse(
        rpcUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws'),
      ),
    );

    _escrowService = PinocchioEscrowService(client: client);

    // Verify program exists
    final exists = await _escrowService!.verifyProgramExists();
    if (!exists) {
      log('⚠️ Warning: Pinocchio program not found on-chain');
    }

    log('✅ PinocchioEscrowService initialized');
    log('🔗 Using RPC: $rpcUrl');
  }

  /// Calculate progressive platform fee
  static double calculatePlatformFee(double challengeAmount) {
    return PinocchioEscrowService.calculatePlatformFee(challengeAmount);
  }

  /// Get detailed fee breakdown for a challenge
  static Map<String, double> getFeeBreakdown(double challengeAmount) {
    return PinocchioEscrowService.getFeeBreakdown(challengeAmount);
  }

  /// Create a challenge record in the database
  /// Note: On-chain transaction is handled by MwaWalletProvider
  Future<Challenge> createChallenge({
    required String title,
    required String description,
    required double amountInSol,
    required String creatorWalletAddress, // Wallet address instead of privy_id
    required String member1Address, // Creator's wallet
    required String member2Address, // Witness wallet
    DateTime? expiresAt,
    String? participantEmail,
    String? onChainAddress, // Challenge account address from blockchain
    String? witnessDisplayName, // Cached display name for witness
  }) async {
    log('🚀 MwaChallengeService.createChallenge');
    log('📝 Title: $title');
    log('💰 Amount: $amountInSol SOL');
    log('👤 Creator wallet: $creatorWalletAddress');
    log('👥 Witness wallet: $member2Address');

    try {
      // Calculate fees
      final feeBreakdown = getFeeBreakdown(amountInSol);
      final platformFee = feeBreakdown['platformFee']!;
      final winnerAmount = feeBreakdown['winnerAmount']!;

      // Create challenge in database
      final createdChallenge = await _createChallengeInDatabase(
        title: title,
        description: description,
        amountInSol: amountInSol,
        creatorWalletAddress: creatorWalletAddress,
        member1Address: member1Address,
        member2Address: member2Address,
        expiresAt: expiresAt,
        participantEmail: participantEmail ?? '',
        escrowAddress: onChainAddress ?? '',
        platformFee: platformFee,
        winnerAmount: winnerAmount,
        witnessDisplayName: witnessDisplayName,
      );

      log('✅ Challenge created in database: ${createdChallenge.id}');
      return createdChallenge;
    } catch (e, stackTrace) {
      log('❌ Error creating challenge: $e');
      log('📍 Stack trace: $stackTrace');
      throw Exception('Failed to create challenge: $e');
    }
  }

  /// Create challenge record in database using wallet_address
  Future<Challenge> _createChallengeInDatabase({
    required String title,
    required String description,
    required double amountInSol,
    required String creatorWalletAddress,
    required String member1Address,
    required String member2Address,
    DateTime? expiresAt,
    required String participantEmail,
    required String escrowAddress,
    required double platformFee,
    required double winnerAmount,
    String? witnessDisplayName,
  }) async {
    final now = DateTime.now();
    final defaultExpiry = now.add(const Duration(days: 30));

    // Look up creator's user ID by wallet_address
    String? creatorUserId;
    try {
      final userResponse =
          await _supabase
              .from('users')
              .select('id')
              .eq('wallet_address', creatorWalletAddress)
              .maybeSingle();

      if (userResponse != null) {
        creatorUserId = userResponse['id'] as String?;
        log('📎 Found creator user ID: $creatorUserId');
      } else {
        log('⚠️ No user found for wallet: $creatorWalletAddress');
      }
    } catch (e) {
      log('⚠️ Error looking up user: $e');
    }

    // Only include columns that exist in the database schema
    final challengeData = {
      'title': title,
      'description': description,
      'amount': amountInSol, // Required column
      'amount_in_sol': amountInSol, // Optional alias
      'platform_fee_sol': platformFee,
      'winner_amount_sol': winnerAmount,
      'creator_wallet_address': creatorWalletAddress,
      if (creatorUserId != null) 'creator_id': creatorUserId,
      'member1_address': member1Address,
      'member2_address': member2Address,
      'expires_at': (expiresAt ?? defaultExpiry).toIso8601String(),
      'participant_email': participantEmail,
      'escrow_address': escrowAddress,
      'multisig_address': escrowAddress, // Legacy alias
      'status': 'active',
      // IMPORTANT: Set blockchain_id for sync deduplication
      // This prevents blockchain sync from creating duplicate challenges
      if (escrowAddress.isNotEmpty) 'blockchain_id': 'onchain_$escrowAddress',
      // IMPORTANT: Set network for devnet/mainnet separation
      'network': NetworkConfig.currentNetwork,
      // Cached witness display name (SNS domain or full_name)
      if (witnessDisplayName != null && witnessDisplayName.isNotEmpty)
        'witness_display_name': witnessDisplayName,
    };

    log('📤 Inserting challenge data: $challengeData');

    // Retry logic for transient network issues
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response =
            await _supabase
                .from('challenges')
                .insert(challengeData)
                .select()
                .single();

        final challenge = Challenge.fromJson(response);

        // Send push notification to witness (best-effort, don't block)
        _sendChallengeCreatedNotification(
          challengeId: challenge.id,
          witnessWallet: member2Address,
          initiatorName:
              witnessDisplayName ?? 'A friend', // Use witness name as fallback
          challengeTitle: title,
          amountSol: amountInSol,
        );

        return challenge;
      } catch (e) {
        log('⚠️ Insert attempt $attempt failed: $e');
        if (attempt < maxRetries) {
          log('🔄 Retrying in ${retryDelay.inMilliseconds}ms...');
          await Future.delayed(retryDelay);
        } else {
          rethrow;
        }
      }
    }

    throw Exception('Failed to insert challenge after $maxRetries attempts');
  }

  /// Send notification to witness when challenge is created (fire-and-forget)
  void _sendChallengeCreatedNotification({
    required String challengeId,
    required String witnessWallet,
    required String initiatorName,
    required String challengeTitle,
    required double amountSol,
  }) {
    // Fire-and-forget: don't await, don't block challenge creation
    FcmTokenService.notifyChallengeCreated(
      challengeId: challengeId,
      witnessWallet: witnessWallet,
      initiatorName: initiatorName,
      challengeTitle: challengeTitle,
      amountSol: amountSol,
    ).catchError((e) {
      log('⚠️ Failed to send challenge notification: $e');
    });
  }

  /// Get challenges for a user by wallet address
  Future<List<Challenge>> getChallengesForUser(String walletAddress) async {
    try {
      final response = await _supabase
          .from('challenges')
          .select()
          .or(
            'member1_address.eq.$walletAddress,member2_address.eq.$walletAddress',
          )
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => Challenge.fromJson(json))
          .toList();
    } catch (e) {
      log('Error fetching challenges: $e');
      return [];
    }
  }

  /// Get challenge by ID
  Future<Challenge?> getChallengeById(String challengeId) async {
    try {
      final response =
          await _supabase
              .from('challenges')
              .select()
              .eq('id', challengeId)
              .single();

      return Challenge.fromJson(response);
    } catch (e) {
      log('Error fetching challenge: $e');
      return null;
    }
  }

  /// Get challenge by on-chain address
  Future<Challenge?> getChallengeByEscrowAddress(String escrowAddress) async {
    try {
      final response =
          await _supabase
              .from('challenges')
              .select()
              .eq('escrow_address', escrowAddress)
              .single();

      return Challenge.fromJson(response);
    } catch (e) {
      log('Challenge not found by escrow address: $e');
      return null;
    }
  }

  /// Update challenge status
  Future<bool> updateChallengeStatus({
    required String challengeId,
    required String status,
    String? winnerId,
    String? transactionSignature,
  }) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (winnerId != null) {
        updateData['winner_id'] = winnerId;
      }
      if (transactionSignature != null) {
        updateData['resolution_tx'] = transactionSignature;
      }

      await _supabase
          .from('challenges')
          .update(updateData)
          .eq('id', challengeId);

      log('✅ Challenge status updated: $challengeId -> $status');
      return true;
    } catch (e) {
      log('❌ Error updating challenge status: $e');
      return false;
    }
  }

  /// Sync on-chain challenge data with database
  Future<void> syncChallengeFromChain(String escrowAddress) async {
    if (_escrowService == null) {
      log('⚠️ Escrow service not initialized');
      return;
    }

    try {
      final onChainData = await _escrowService!.getChallengeData(escrowAddress);
      if (onChainData == null) {
        log('⚠️ Challenge not found on-chain: $escrowAddress');
        return;
      }

      // Update database with on-chain status
      String status;
      if (onChainData.isCancelled) {
        status = 'cancelled';
      } else if (onChainData.isResolved) {
        status = onChainData.isSuccess ? 'completed' : 'failed';
      } else if (onChainData.isExpired) {
        status = 'expired';
      } else {
        status = 'active';
      }

      await _supabase
          .from('challenges')
          .update({
            'status': status,
            'amount_in_sol': onChainData.amountSol,
            'platform_fee_sol': onChainData.platformFeeSol,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('escrow_address', escrowAddress);

      log('✅ Challenge synced from chain: $escrowAddress');
    } catch (e) {
      log('❌ Error syncing challenge: $e');
    }
  }

  /// Get active challenges count for user
  Future<int> getActiveChallengesCount(String walletAddress) async {
    try {
      final response = await _supabase
          .from('challenges')
          .select('id')
          .or(
            'member1_address.eq.$walletAddress,member2_address.eq.$walletAddress',
          )
          .eq('status', 'active');

      return (response as List).length;
    } catch (e) {
      log('Error counting active challenges: $e');
      return 0;
    }
  }

  /// Get total staked amount for user
  Future<double> getTotalStakedAmount(String walletAddress) async {
    try {
      final response = await _supabase
          .from('challenges')
          .select('amount_in_sol')
          .eq('member1_address', walletAddress)
          .eq('status', 'active');

      double total = 0.0;
      for (final row in response as List) {
        total += (row['amount_in_sol'] as num).toDouble();
      }

      return total;
    } catch (e) {
      log('Error calculating total staked: $e');
      return 0.0;
    }
  }
}
