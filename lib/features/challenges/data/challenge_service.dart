import 'dart:developer';
import 'package:coral_xyz/coral_xyz_anchor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:chumbucket/shared/services/escrow_service.dart';
import 'package:chumbucket/shared/services/realtime_service.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/shared/models/models.dart';

class ChallengeService {
  final SupabaseClient _supabase;
  EscrowService? _escrowService;
  late final RealtimeService _realtimeService;

  // Platform configuration - Simple progressive fee structure
  // Fee gets smaller as stake increases (what the user wanted)
  static const double BASE_FEE_PERCENTAGE = 0.10; // 10% for small amounts
  static const double MIN_FEE_PERCENTAGE = 0.02; // 2% minimum for large amounts
  static const double FEE_REDUCTION_THRESHOLD =
      1.0; // Start reducing fee after 1 SOL
  static const double MAX_FEE_SOL = 0.5; // Cap fee at 0.5 SOL

  String get platformWalletAddress =>
      dotenv.env['PLATFORM_WALLET_ADDRESS'] ??
      'CHANGEME_YourActualPlatformWalletAddress';

  // Getters for accessing services
  RealtimeService get realtimeService => _realtimeService;
  EscrowService get escrowService => _escrowService!;

  ChallengeService({required SupabaseClient supabase}) : _supabase = supabase {
    _realtimeService = RealtimeService(supabase: _supabase);

    // Initialize unified database service with Supabase
    UnifiedDatabaseService.configure(supabase: _supabase);

    log(
      'ChallengeService initialized with ${UnifiedDatabaseService.currentMode} database',
    );
  }

  /// Initialize the EscrowService with PrivyWallet for dart-coral-xyz automation
  Future<void> initializeEscrow({
    required EmbeddedSolanaWallet embeddedWallet,
    required String walletAddress,
  }) async {
    // Prioritize devnet for development - only use local if explicitly enabled
    final rpcUrl =
        dotenv.env['SOLANA_RPC_URL'] ??
        dotenv.env['LOCAL_RPC_URL'] ??
        'https://api.devnet.solana.com';

    _escrowService = await EscrowService.create(
      embeddedWallet: embeddedWallet,
      walletAddress: walletAddress,
      rpcUrl: rpcUrl,
    );
    log('✅ EscrowService initialized with dart-coral-xyz automation');
    log('🔗 Using RPC: $rpcUrl');
  }

  /// Calculate progressive platform fee - gets smaller as stake increases
  /// If they stake $10, we take $1 (10%), they get $9
  /// For larger amounts, fee percentage reduces
  static double calculatePlatformFee(double challengeAmount) {
    if (challengeAmount <= 0) return 0.0;

    double feePercentage;

    if (challengeAmount <= FEE_REDUCTION_THRESHOLD) {
      // For amounts <= 1 SOL, use base percentage (10%)
      feePercentage = BASE_FEE_PERCENTAGE;
    } else {
      // For amounts > 1 SOL, progressively reduce fee
      // Formula: fee reduces by 1% for every additional SOL, down to minimum
      final excessAmount = challengeAmount - FEE_REDUCTION_THRESHOLD;
      final reductionPerSol = 0.01; // 1% reduction per SOL
      final totalReduction = excessAmount * reductionPerSol;

      feePercentage = (BASE_FEE_PERCENTAGE - totalReduction).clamp(
        MIN_FEE_PERCENTAGE,
        BASE_FEE_PERCENTAGE,
      );
    }

    final calculatedFee = challengeAmount * feePercentage;

    // Cap the fee at maximum
    return calculatedFee.clamp(0.0, MAX_FEE_SOL);
  }

  /// Get detailed fee breakdown for a challenge
  static Map<String, double> getFeeBreakdown(double challengeAmount) {
    final platformFee = calculatePlatformFee(challengeAmount);
    final winnerAmount = challengeAmount - platformFee;
    final feePercentage =
        challengeAmount > 0 ? (platformFee / challengeAmount) : 0.0;

    return {
      'challengeAmount': challengeAmount,
      'platformFee': platformFee,
      'winnerAmount': winnerAmount,
      'feePercentage': feePercentage,
    };
  }

  Future<Challenge> createChallenge({
    required String title,
    required String description,
    required double amountInSol,
    required String creatorId, // Privy user ID
    required String member1Address, // Creator's wallet
    required String member2Address, // Platform wallet or second participant
    DateTime? expiresAt,
    String? participantEmail,
    Function(List<int>, Keypair)?
    transactionSigner, // Transaction signer callback with challenge keypair
  }) async {
    log('🚨 ChallengeService.createChallenge CALLED (SIMPLIFIED)');
    log('🚨 Title: $title');
    log('🚨 Description: $description');
    log('🚨 Amount: $amountInSol SOL');
    log('🚨 Creator ID: $creatorId');
    log('🚨 Member1 (creator wallet): $member1Address');
    log('🚨 Member2 (friend wallet): $member2Address');

    try {
      // Calculate fees
      final feeBreakdown = getFeeBreakdown(amountInSol);
      final platformFee = feeBreakdown['platformFee']!;
      final winnerAmount = feeBreakdown['winnerAmount']!;

      log('✅ Creating challenge on-chain using dart-coral-xyz automation');

      // Use dart-coral-xyz automation to create the challenge transaction
      final challengeAddress = await _escrowService!.createChallenge(
        initiatorAddress: member1Address,
        witnessAddress: member2Address,
        amountSol: amountInSol,
        durationDays: 30, // Default 30 days
      );

      log('✅ Challenge created on-chain with dart-coral-xyz automation');
      log('🏦 Challenge Address: $challengeAddress');
      log('🎉 Challenge successfully submitted to blockchain');

      // Create challenge in database with on-chain details
      final createdChallenge = await UnifiedDatabaseService.createChallenge(
        title: title,
        description: description,
        amountInSol: amountInSol,
        creatorPrivyId: creatorId, // Fixed parameter name
        member1Address: member1Address,
        member2Address: member2Address,
        expiresAt: expiresAt,
        participantEmail: participantEmail ?? '',
        escrowAddress: challengeAddress, // Use challenge address as identifier
        vaultAddress: challengeAddress, // Use challenge address as identifier
        platformFee: platformFee,
        winnerAmount: winnerAmount,
        challengeId: challengeAddress, // Use blockchain address as challenge ID
      );

      log('📝 Challenge created in database');
      log(
        '🚨 RETURNING CHALLENGE FROM createChallenge: ${createdChallenge?.id}',
      );

      return createdChallenge!;
    } catch (e, stackTrace) {
      log('❌ Error creating challenge: $e');
      log('❌ Stack trace: $stackTrace');
      throw Exception('Failed to create challenge: $e');
    }
  }

  /// Simplified methods for basic functionality

  Future<String> stakeChallenge({
    required String challengeId,
    required double amountInSol,
    required String stakeholderAddress,
  }) async {
    try {
      log('Staking challenge: $challengeId');

      // For now, return a mock transaction signature
      // The actual staking will be handled by the wallet provider with the escrow program
      return 'mock_stake_signature_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      log('❌ Error staking challenge: $e');
      rethrow;
    }
  }

  Future<double> getVaultBalance(String vaultAddress) async {
    try {
      // For now, return 0.0 - this will be implemented when needed
      return 0.0;
    } catch (e) {
      log('❌ Error getting vault balance: $e');
      return 0.0;
    }
  }

  Future<List<Map<String, dynamic>>> resolveChallenge({
    required String challengeId,
    required String winnerId,
    required String challengeTitle,
    required double totalAmount,
  }) async {
    try {
      log('Resolving challenge: $challengeId');

      // For now, return mock transaction results
      // The actual resolution will be handled by the wallet provider with the escrow program
      return [
        {
          'type': 'winner_payout',
          'signature':
              'mock_winner_signature_${DateTime.now().millisecondsSinceEpoch}',
          'amount': totalAmount * 0.99, // After platform fee
        },
        {
          'type': 'platform_fee',
          'signature':
              'mock_fee_signature_${DateTime.now().millisecondsSinceEpoch}',
          'amount': totalAmount * 0.01,
        },
      ];
    } catch (e) {
      log('❌ Error resolving challenge: $e');
      rethrow;
    }
  }

  // Database operations - implemented to work with UnifiedDatabaseService
  Future<List<Challenge>> getChallenges({String? userId}) async {
    try {
      log('Getting challenges for user: $userId');

      if (userId == null) {
        log('No userId provided, returning empty list');
        return [];
      }

      // Use UnifiedDatabaseService to get challenges
      final challenges = await UnifiedDatabaseService.getChallengesForUser(
        userId,
      );

      log('Found ${challenges.length} challenges for user');
      return challenges;
    } catch (e) {
      log('❌ Error getting challenges: $e');
      return [];
    }
  }

  Future<Challenge?> getChallengeById(String challengeId) async {
    try {
      log('Getting challenge by ID: $challengeId');

      // Use UnifiedDatabaseService to get specific challenge
      final challenge = await UnifiedDatabaseService.getChallenge(challengeId);

      if (challenge != null) {
        log('Found challenge: ${challenge.title}');
      } else {
        log('Challenge not found');
      }

      return challenge;
    } catch (e) {
      log('❌ Error getting challenge: $e');
      return null;
    }
  }

  Future<bool> updateChallengeStatus({
    required String challengeId,
    required ChallengeStatus status,
  }) async {
    try {
      log('Updating challenge $challengeId status to: $status');

      // Use UnifiedDatabaseService to update challenge status
      final success = await UnifiedDatabaseService.updateChallengeStatus(
        challengeId,
        status.toString().split('.').last, // Convert enum to string
      );

      if (success) {
        log('✅ Challenge status updated successfully');
      } else {
        log('❌ Failed to update challenge status');
      }

      return success;
    } catch (e) {
      log('❌ Error updating challenge status: $e');
      return false;
    }
  }

  /// Mark a challenge as completed with REAL on-chain resolution
  /// This calls the actual Anchor program resolve_challenge instruction
  Future<bool> markChallengeCompleted(
    String challengeId,
    String winnerId, {
    String? currentUserId,
    Future<String> Function(List<int> transactionBytes)? transactionSigner,
  }) async {
    try {
      log(
        '🎯 Starting REAL challenge resolution for challengeId: $challengeId, winnerId: $winnerId',
      );

      // 1. Get the challenge to access escrow details
      log('📋 Step 1: Fetching challenge details...');
      final challenge = await getChallengeById(challengeId);
      if (challenge == null) {
        log('❌ Challenge not found: $challengeId');
        return false;
      }

      if (challenge.escrowAddress == null || challenge.escrowAddress!.isEmpty) {
        log('❌ Challenge has no escrow address - cannot resolve on-chain');
        return false;
      }

      log('✅ Challenge found: ${challenge.title}');
      log('🔗 Escrow Address: ${challenge.escrowAddress}');

      // 2. Resolve participant wallet addresses
      log('🔑 Step 2: Resolving participant wallet addresses...');
      final walletMapping = await _resolveParticipantWallets(challenge);
      final hasPlaceholders =
          walletMapping['initiatorWallet']?.startsWith('PLACEHOLDER_') ==
              true ||
          walletMapping['witnessWallet']?.startsWith('PLACEHOLDER_') == true;

      if (hasPlaceholders) {
        log('⚠️ Cannot resolve challenge with placeholder addresses');
        log('💡 Real wallet addresses required for on-chain resolution');

        // Still update database for UI testing, but don't claim success
        await UnifiedDatabaseService.updateChallenge(challengeId, {
          'status':
              'pending', // Keep as pending since we can't resolve on-chain
          'notes': 'Waiting for real wallet addresses',
        });
        return false;
      }

      // 3. Determine if initiator won (success = true) or witness won (success = false)
      final initiatorWon = winnerId == challenge.creatorId;
      log('🏆 Resolution: Initiator won = $initiatorWon');

      // Use dart-coral-xyz automation to resolve the challenge on-chain
      log('🔧 Resolving challenge with dart-coral-xyz automation');

      final signature = await _escrowService!.resolveChallenge(
        challengeAddress: challenge.escrowAddress!,
        initiatorAddress: walletMapping['creator']!,
        witnessAddress: walletMapping['participant']!,
        success: initiatorWon,
      );

      // Update the challenge status in the database with real transaction data
      final success =
          await UnifiedDatabaseService.updateChallenge(challengeId, {
            'status': 'completed',
            'winner_privy_id': initiatorWon ? challenge.creatorId : null,
            'completed_at': DateTime.now().toIso8601String(),
            'transaction_signature': signature,
          });

      if (success) {
        log(
          '✅ Challenge resolved successfully with dart-coral-xyz automation!',
        );
        log('📝 Transaction Signature: $signature');
        return true;
      } else {
        log('❌ Failed to update challenge status in database');
        return false;
      }
    } catch (e, stackTrace) {
      log('❌ Error in markChallengeCompleted: $e');
      log('📍 Stack trace: $stackTrace');
      return false;
    }
  }

  // REMOVED: Manual transaction building methods
  // These have been replaced with a proper web interface using Anchor TypeScript SDK

  // REMOVED: Manual transaction building methods
  // These have been replaced with a proper web interface using Anchor TypeScript SDK

  /// Simplified method to mark a challenge as completed

  /// Resolve user IDs to wallet addresses using available information
  /// This method attempts to get wallet addresses for challenge participants
  Future<Map<String, String?>> _resolveParticipantWallets(
    Challenge challenge,
  ) async {
    try {
      log(
        'Resolving participant wallet addresses for challenge: ${challenge.id}',
      );

      String? creatorWallet;
      String? participantWallet;

      // For the creator, try to get the current user's wallet if they are the creator
      // This assumes the current user is resolving their own challenge
      // In a production app, you'd have a proper user-to-wallet mapping service

      // Option 1: If we have escrow address, we could derive the participants from the contract
      // Option 2: Use a database lookup table that maps user IDs to wallet addresses
      // Option 3: Get wallet addresses from the friends system if participant is a friend

      // For now, let's check if we can get addresses from the friends database
      if (challenge.participantEmail != null) {
        try {
          // TODO: Implement getFriendByEmail method in UnifiedDatabaseService
          // This would query the friends table to find a friend with the given email
          // and return their wallet address
          log('⚠️ Friend lookup by email not yet implemented');
        } catch (e) {
          log(
            '⚠️ Could not resolve participant wallet from friends database: $e',
          );
        }
      }

      // TODO: Implement proper user-to-wallet address mapping
      // This would involve:
      // 1. A user profile service that stores wallet addresses for each Privy user ID
      // 2. Querying that service to get the wallet address for creatorId and participantId
      // 3. Handling cases where users might have multiple wallets or change wallets

      log(
        '⚠️ Using placeholder wallet addresses - implement proper user-to-wallet mapping',
      );
      creatorWallet ??= 'PLACEHOLDER_CREATOR_WALLET_${challenge.creatorId}';
      participantWallet ??=
          'PLACEHOLDER_PARTICIPANT_WALLET_${challenge.participantId ?? challenge.participantEmail}';

      return {'creator': creatorWallet, 'participant': participantWallet};
    } catch (e) {
      log('❌ Error resolving participant wallets: $e');
      return {
        'creator': 'PLACEHOLDER_CREATOR_WALLET_${challenge.creatorId}',
        'participant':
            'PLACEHOLDER_PARTICIPANT_WALLET_${challenge.participantId ?? challenge.participantEmail}',
      };
    }
  }

  // REMOVED: Manual transaction building methods
  // These have been replaced with a proper web interface using Anchor TypeScript SDK

  /// Simplified method to mark a challenge as completed
  /// This updates the database without complex on-chain transactions
  /// Perfect for development and simple use cases
  Future<bool> markChallengeCompletedSimple({
    required String challengeId,
    required String winnerId,
    required String currentUserId,
  }) async {
    try {
      log('🎯 Marking challenge as completed (simplified approach)');
      log('- Challenge ID: $challengeId');
      log('- Winner ID: $winnerId');
      log('- Marked by: $currentUserId');

      // Update the challenge status in the database
      final success = await UnifiedDatabaseService.updateChallenge(
        challengeId,
        {
          'status': 'completed',
          'winner_privy_id': winnerId,
          'completed_at': DateTime.now().toIso8601String(),
          'transaction_signature':
              'simplified_completion_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (success) {
        log('✅ Challenge marked as completed successfully');
        return true;
      } else {
        log('❌ Failed to update challenge in database');
        return false;
      }
    } catch (e) {
      log('❌ Error in markChallengeCompletedSimple: $e');
      return false;
    }
  }
}
