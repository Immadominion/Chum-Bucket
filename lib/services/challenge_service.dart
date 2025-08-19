import 'dart:developer';
import 'package:solana/solana.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:chumbucket/services/multisig_service.dart';
import 'package:chumbucket/services/realtime_service.dart';
import 'package:chumbucket/services/unified_database_service.dart';
import 'package:chumbucket/models/models.dart';

class ChallengeService {
  final SupabaseClient _supabase;
  final SolanaClient _solanaClient;
  late final MultisigService _multisigService;
  late final RealtimeService _realtimeService;

  // Platform configuration
  static const double PLATFORM_FEE_PERCENTAGE = 0.01; // 1%
  static const double MIN_FEE_SOL = 0.001; // Minimum fee in SOL
  static const double MAX_FEE_SOL =
      0.1; // Maximum fee in SOL (~$10 at $100/SOL)

  String get platformWalletAddress =>
      dotenv.env['PLATFORM_WALLET_ADDRESS'] ??
      'CHANGEME_YourActualPlatformWalletAddress';

  // Getters for accessing services
  RealtimeService get realtimeService => _realtimeService;

  ChallengeService({
    required SupabaseClient supabase,
    required SolanaClient solanaClient,
    WalletSigningInterface? walletProvider,
  }) : _supabase = supabase,
       _solanaClient = solanaClient {
    _multisigService = MultisigService(
      solanaClient: _solanaClient,
      walletProvider: walletProvider,
    );
    _realtimeService = RealtimeService(supabase: _supabase);

    // Initialize unified database service
    UnifiedDatabaseService.configure(
      mode: DatabaseMode.local, // Use local SQLite for development
      supabase: _supabase,
    );
    log(
      'ChallengeService initialized with ${UnifiedDatabaseService.currentMode} database',
    );
  }

  /// Calculate platform fee for a challenge
  /// Returns fee in SOL, clamped to min/max limits
  static double calculatePlatformFee(double challengeAmount) {
    double fee = challengeAmount * PLATFORM_FEE_PERCENTAGE;
    return fee.clamp(MIN_FEE_SOL, MAX_FEE_SOL);
  }

  /// Get detailed fee breakdown for a challenge
  static Map<String, double> getFeeBreakdown(double challengeAmount) {
    final platformFee = calculatePlatformFee(challengeAmount);
    final winnerAmount = challengeAmount - platformFee;

    return {
      'challengeAmount': challengeAmount,
      'platformFee': platformFee,
      'winnerAmount': winnerAmount,
      'feePercentage': PLATFORM_FEE_PERCENTAGE,
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
  }) async {
    try {
      // Calculate fees
      final feeBreakdown = getFeeBreakdown(amountInSol);
      final platformFee = feeBreakdown['platformFee']!;
      final winnerAmount = feeBreakdown['winnerAmount']!;

      // Generate a temporary challenge ID for multisig creation
      final tempChallengeId = DateTime.now().millisecondsSinceEpoch.toString();

      // Create multisig for this challenge
      final multisigInfo = await _multisigService.createChallengeMultisig(
        challengeId: tempChallengeId,
        member1Address: member1Address,
        member2Address: member2Address,
      );

      // Create challenge in database using unified service
      final createdChallenge = await UnifiedDatabaseService.createChallenge(
        title: title,
        description: description,
        amountInSol: amountInSol,
        creatorId: creatorId,
        member1Address: member1Address,
        member2Address: member2Address,
        expiresAt: expiresAt,
        participantEmail: participantEmail,
        multisigAddress: multisigInfo['multisig_address'],
        vaultAddress: multisigInfo['vault_address'],
        platformFee: platformFee,
        winnerAmount: winnerAmount,
      );

      log('Challenge created successfully with ID: ${createdChallenge.id}');

      // Initiate fund staking to multisig vault
      try {
        log('Initiating fund staking for challenge ${createdChallenge.id}');
        final stakeResult = await _multisigService.depositToVault(
          vaultAddress: multisigInfo['vault_address']!,
          amountSol: amountInSol,
          senderAddress: member1Address,
        );

        log('Funds staked successfully: $stakeResult');

        // Update challenge status to funded
        await UnifiedDatabaseService.updateChallengeStatus(
          createdChallenge.id,
          'funded',
          transactionSignature: stakeResult,
        );

        log('Challenge status updated to funded');
      } catch (stakeError) {
        log('Warning: Fund staking failed: $stakeError');
        // Challenge created but funds not staked - this should be handled in UI
      }

      return createdChallenge;
    } catch (e) {
      print('Error creating challenge: $e');
      rethrow;
    }
  }

  /// Deposit funds to a challenge's multisig vault
  Future<Map<String, dynamic>> depositToChallenge({
    required String challengeId,
    required double amountSol,
    required String fromWalletAddress,
  }) async {
    try {
      final challenge = await getChallenge(challengeId);
      if (challenge == null) {
        throw Exception('Challenge not found');
      }

      final vaultAddress = challenge.vaultAddress;
      if (vaultAddress == null) {
        throw Exception('Challenge vault not configured');
      }

      // Use multisig service to handle deposit
      final transactionSignature = await _multisigService.depositToVault(
        vaultAddress: vaultAddress,
        amountSol: amountSol,
        senderAddress: fromWalletAddress,
      );

      // Update challenge with transaction signature
      await _supabase
          .from('challenges')
          .update({
            'transaction_signature': transactionSignature,
            'status': 'funded',
          })
          .eq('id', challengeId);

      return {
        'transactionSignature': transactionSignature,
        'status': 'funded',
        'amount': amountSol,
      };
    } catch (e) {
      print('Error depositing to challenge: $e');
      rethrow;
    }
  }

  /// Get vault balance for a challenge
  Future<double> getChallengeVaultBalance(String challengeId) async {
    try {
      final challenge = await getChallenge(challengeId);
      if (challenge == null) {
        throw Exception('Challenge not found');
      }

      final vaultAddress = challenge.vaultAddress;
      if (vaultAddress == null) {
        return 0.0;
      }

      return await _multisigService.getVaultBalance(vaultAddress);
    } catch (e) {
      print('Error getting vault balance: $e');
      return 0.0;
    }
  }

  /// Release funds from challenge vault to winner
  Future<Map<String, dynamic>> releaseFundsToWinner({
    required String challengeId,
    required String winnerId,
    required String winnerWalletAddress,
    required List<String>
    signerAddresses, // Both platform and winner signatures
  }) async {
    try {
      final challenge = await getChallenge(challengeId);
      if (challenge == null) {
        throw Exception('Challenge not found');
      }

      final multisigAddress = challenge.multisigAddress;
      final vaultAddress = challenge.vaultAddress;
      final winnerAmount = challenge.winnerAmount;
      final platformFee = challenge.platformFee;

      if (multisigAddress == null || vaultAddress == null) {
        throw Exception('Challenge configuration incomplete');
      }

      // Release winner amount to winner
      final winnerResult = await _multisigService.withdrawFromVault(
        multisigAddress: multisigAddress,
        vaultAddress: vaultAddress,
        recipientAddress: winnerWalletAddress,
        amountSol: winnerAmount,
        signerAddresses: signerAddresses,
      );

      // Release platform fee to platform wallet
      final feeResult = await _multisigService.withdrawFromVault(
        multisigAddress: multisigAddress,
        vaultAddress: vaultAddress,
        recipientAddress: platformWalletAddress,
        amountSol: platformFee,
        signerAddresses: signerAddresses,
      );

      // Update challenge as completed
      await _supabase
          .from('challenges')
          .update({
            'winner_privy_id': winnerId,
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
            'transaction_signature': winnerResult,
            'fee_transaction_signature': feeResult,
          })
          .eq('id', challengeId);

      return {
        'winnerTransaction': winnerResult,
        'feeTransaction': feeResult,
        'status': 'completed',
      };
    } catch (e) {
      print('Error releasing funds: $e');
      rethrow;
    }
  }

  /// Get platform fee statistics
  Future<Map<String, dynamic>> getFeeStatistics() async {
    try {
      // Get total fees collected
      final totalFeesQuery = await _supabase
          .from('challenges')
          .select('platform_fee_sol')
          .eq('status', 'completed');

      double totalFeesCollected = 0.0;
      int completedChallenges = totalFeesQuery.length;

      for (final challenge in totalFeesQuery) {
        final fee = challenge['platform_fee_sol'] as double? ?? 0.0;
        totalFeesCollected += fee;
      }

      // Get active challenges
      final activeChallengesQuery = await _supabase
          .from('challenges')
          .select('id')
          .filter('status', 'in', '(pending,accepted,funded)');

      return {
        'totalFeesCollected': totalFeesCollected,
        'completedChallenges': completedChallenges,
        'activeChallenges': activeChallengesQuery.length,
        'averageFeePerChallenge':
            completedChallenges > 0
                ? totalFeesCollected / completedChallenges
                : 0.0,
        'feePercentage': PLATFORM_FEE_PERCENTAGE,
        'minFee': MIN_FEE_SOL,
        'maxFee': MAX_FEE_SOL,
      };
    } catch (e) {
      print('Error getting platform fee statistics: $e');
      return {};
    }
  }

  /// Get challenge by ID
  Future<Challenge?> getChallenge(String challengeId) async {
    try {
      return await UnifiedDatabaseService.getChallenge(challengeId);
    } catch (e) {
      log('Error fetching challenge: $e');
      return null;
    }
  }

  /// Get challenges for a user
  Future<List<Challenge>> getUserChallenges(String privyId) async {
    try {
      return await UnifiedDatabaseService.getChallengesForUser(privyId);
    } catch (e) {
      log('Error fetching user challenges: $e');
      return [];
    }
  }

  /// Accept a challenge (placeholder)
  Future<bool> acceptChallenge(
    String challengeId,
    String participantPrivyId,
  ) async {
    try {
      await _supabase
          .from('challenges')
          .update({
            'participant_privy_id': participantPrivyId,
            'status': 'accepted',
          })
          .eq('id', challengeId);

      log('Challenge accepted: $challengeId');
      return true;
    } catch (e) {
      log('Error accepting challenge: $e');
      return false;
    }
  }

  /// Complete a challenge and release funds to winner (requires both signatures)
  Future<Map<String, dynamic>> completeChallenge(
    String challengeId,
    String winnerId, {
    List<String>? signerAddresses,
  }) async {
    try {
      // Get challenge details
      final challenge = await getChallenge(challengeId);
      if (challenge == null) {
        throw Exception('Challenge not found: $challengeId');
      }

      log('Completing challenge: ${challenge.title}');
      log('Winner: $winnerId');
      log('Challenge amount: ${challenge.amount} SOL');
      log('Platform fee: ${challenge.platformFee} SOL');
      log('Winner amount: ${challenge.winnerAmount} SOL');

      // Validate challenge is in correct state
      if (challenge.status != ChallengeStatus.funded) {
        throw Exception(
          'Challenge must be funded to complete. Current status: ${challenge.status}',
        );
      }

      // Default signers (both challenger and participant must sign)
      final finalSigners =
          signerAddresses ??
          [
            challenge.creatorId, // This should be wallet address in production
            challenge.participantId ??
                'participant_address', // This should be actual participant wallet
          ];

      // Release funds using multisig service
      final releaseResult = await _multisigService.releaseFundsToWinner(
        multisigAddress: challenge.multisigAddress!,
        vaultAddress: challenge.vaultAddress!,
        winnerAddress:
            'winner_wallet_address', // This should be actual winner wallet
        platformAddress: platformWalletAddress,
        winnerAmount: challenge.winnerAmount,
        platformFee: challenge.platformFee,
        signerAddresses: finalSigners,
      );

      log('Funds released successfully');
      log('Winner transaction: ${releaseResult['winnerTransaction']}');
      log('Platform transaction: ${releaseResult['platformTransaction']}');

      // Update challenge status to completed
      await UnifiedDatabaseService.updateChallengeStatus(
        challengeId,
        'completed',
        transactionSignature: releaseResult['winnerTransaction'],
        winnerId: winnerId,
        completedAt: DateTime.now(),
      );

      // Record platform fee collection
      await _recordPlatformFee(
        challengeId: challengeId,
        amount: challenge.platformFee,
        transactionSignature: releaseResult['platformTransaction'],
      );

      log('Challenge completed successfully: $challengeId');

      return {
        'challengeId': challengeId,
        'winnerId': winnerId,
        'winnerAmount': challenge.winnerAmount,
        'platformFee': challenge.platformFee,
        'winnerTransaction': releaseResult['winnerTransaction'],
        'platformTransaction': releaseResult['platformTransaction'],
        'status': 'completed',
        'completedAt': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      log('Error completing challenge: $e');
      rethrow;
    }
  }

  /// Record platform fee collection
  Future<void> _recordPlatformFee({
    required String challengeId,
    required double amount,
    required String transactionSignature,
  }) async {
    try {
      // Create platform fee record
      final platformFee = PlatformFee(
        id: 'fee_${DateTime.now().millisecondsSinceEpoch}',
        challengeId: challengeId,
        amount: amount,
        transactionSignature: transactionSignature,
        collectedAt: DateTime.now(),
        feePercentage: PLATFORM_FEE_PERCENTAGE,
        platformWalletAddress: platformWalletAddress,
      );

      await UnifiedDatabaseService.insertPlatformFee(platformFee);
      log('Platform fee recorded: $amount SOL');
    } catch (e) {
      log('Error recording platform fee: $e');
      // Don't throw - fee collection succeeded even if recording failed
    }
  }
}
