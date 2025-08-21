import 'dart:developer';
import 'dart:typed_data';
import 'package:solana/solana.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:chumbucket/services/escrow_service.dart';
import 'package:chumbucket/services/realtime_service.dart';
import 'package:chumbucket/services/unified_database_service.dart';
import 'package:chumbucket/models/models.dart';

class ChallengeService {
  final SupabaseClient _supabase;
  final EscrowService _escrowService;
  late final RealtimeService _realtimeService;

  // Platform configuration
  static const double PLATFORM_FEE_PERCENTAGE = 0.01; // 1%
  static const double MIN_FEE_SOL = 0.001; // Minimum fee in SOL
  static const double MAX_FEE_SOL = 0.1; // Maximum fee in SOL

  String get platformWalletAddress =>
      dotenv.env['PLATFORM_WALLET_ADDRESS'] ??
      'CHANGEME_YourActualPlatformWalletAddress';

  // Getters for accessing services
  RealtimeService get realtimeService => _realtimeService;
  EscrowService get escrowService => _escrowService;

  ChallengeService({
    required SupabaseClient supabase,
    required SolanaClient solanaClient,
  }) : _supabase = supabase,
       _escrowService = EscrowService(client: solanaClient) {
    _realtimeService = RealtimeService(supabase: _supabase);

    // Initialize unified database service
    UnifiedDatabaseService.configure(
      mode: DatabaseMode.local, // Use local SQLite for development
      supabase: _supabase,
    );
    log(
      'ChallengeService initialized with ${UnifiedDatabaseService.currentMode} database and EscrowService for Anchor program',
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
    Function(List<int>, Ed25519HDKeyPair)?
    transactionSigner, // Add transaction signer callback with challenge keypair
  }) async {
    try {
      // Calculate fees
      final feeBreakdown = getFeeBreakdown(amountInSol);
      final platformFee = feeBreakdown['platformFee']!;
      final winnerAmount = feeBreakdown['winnerAmount']!;

      log('Creating challenge:');
      log('- Friend: $member2Address');
      log('- Amount: ${amountInSol.toStringAsFixed(4)} SOL');
      log('- Description: $description');
      log('- Duration: 7 days');

      // Create escrow challenge using the deployed Anchor program
      final escrowInfo = await _escrowService.createChallenge(
        initiatorAddress: member1Address,
        witnessAddress: member2Address,
        amountSol: amountInSol,
        durationDays: 7, // Default 7 days
      );

      // If a transaction signer is provided, this means we need to create and send the actual blockchain transaction
      if (transactionSigner != null) {
        log('🔧 Building Solana transaction for Anchor program...');

        // Build the complete Solana transaction
        final transactionBytes = await _buildChallengeTransaction(
          escrowInfo: escrowInfo,
          member1Address: member1Address,
          member2Address: member2Address,
          amountInSol: amountInSol,
        );

        // Sign and send the transaction through the wallet provider
        log('📡 Signing and sending challenge creation transaction...');
        final challengeKeypair =
            escrowInfo['challengeKeypair'] as Ed25519HDKeyPair;
        await transactionSigner(transactionBytes, challengeKeypair);

        log('✅ Challenge transaction signed and sent');
        log('🔗 View on Solana Explorer (devnet)');

        // Wait for transaction confirmation before saving to database
        await Future.delayed(const Duration(seconds: 2));
      }

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
        escrowAddress:
            escrowInfo['challengeAddress'], // Use challenge address from Anchor program
        vaultAddress:
            EscrowService.PROGRAM_ID, // Use program ID as vault reference
        platformFee: platformFee,
        winnerAmount: winnerAmount,
      );

      log('✅ Challenge created in database');
      return createdChallenge;
    } catch (e) {
      log('❌ Error creating challenge: $e');

      // Throw a user-friendly error
      throw Exception('Failed to create challenge escrow. Please try again.');
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

  // Database operations - simplified for now
  Future<List<Challenge>> getChallenges({String? userId}) async {
    try {
      // For now, return empty list - implement when database methods are ready
      log('Getting challenges for user: $userId');
      return [];
    } catch (e) {
      log('❌ Error getting challenges: $e');
      return [];
    }
  }

  Future<Challenge?> getChallengeById(String challengeId) async {
    try {
      // For now, return null - implement when database methods are ready
      log('Getting challenge by ID: $challengeId');
      return null;
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
      // For now, return true - implement when database methods are ready
      log('Updating challenge $challengeId status to: $status');
      return true;
    } catch (e) {
      log('❌ Error updating challenge status: $e');
      return false;
    }
  }

  /// Build complete Solana transaction for challenge creation
  Future<List<int>> _buildChallengeTransaction({
    required Map<String, dynamic> escrowInfo,
    required String member1Address,
    required String member2Address,
    required double amountInSol,
  }) async {
    try {
      final instructionData = escrowInfo['instructionData'] as Uint8List;

      log('🔧 Building complete Solana transaction message...');
      log('   Challenge account: ${escrowInfo['challengeAddress']}');
      log('   Initiator: $member1Address');
      log('   Witness: $member2Address');
      log('   Amount: ${amountInSol.toStringAsFixed(4)} SOL');

      // Build a proper Solana transaction message format:
      // [numRequiredSignatures, numReadonlySigned, numReadonlyUnsigned,
      //  shortvec(accounts), recentBlockhash, shortvec(instructions)]

      final messageBuilder = BytesBuilder();

      // Header (3 bytes)
      // Account layout: [initiator(signer), challenge(signer), witness(readonly), system_program(readonly), escrow_program(readonly)]
      // numReadonlyUnsigned only counts truly readonly accounts (witness, system_program, escrow_program)
      messageBuilder.add([
        2, // numRequiredSignatures (initiator + challenge account)
        0, // numReadonlySigned (no signed readonly accounts)
        3, // numReadonlyUnsigned (witness, system_program, escrow_program only)
      ]);

      // Accounts array (shortvec format)
      // Solana transaction account ordering: [signers, writable_non_signers, readonly]
      // Account order: [initiator(signer), challenge(signer), witness(readonly), system_program(readonly), escrow_program(readonly)]
      final accounts = [
        member1Address, // 0: initiator (signer)
        escrowInfo['challengeAddress'], // 1: challenge account (signer for init)
        member2Address, // 2: witness (readonly)
        '11111111111111111111111111111111', // 3: system program (readonly)
        EscrowService.PROGRAM_ID, // 4: escrow program (readonly)
      ];

      // Encode accounts count
      messageBuilder.add(_shortVecEncode(accounts.length));

      // Add each account as 32 bytes
      for (final account in accounts) {
        final decoded = _base58Decode(account);
        if (decoded.length != 32) {
          throw Exception('Invalid account address: $account');
        }
        messageBuilder.add(decoded);
      }

      // Recent blockhash - fetch from Solana RPC
      log('📡 Fetching recent blockhash from Solana RPC...');
      final client = SolanaClient(
        rpcUrl: Uri.parse('https://api.devnet.solana.com'),
        websocketUrl: Uri.parse('wss://api.devnet.solana.com'),
      );
      final recentBlockhash = await client.rpcClient.getLatestBlockhash();
      final blockhashBytes = _base58Decode(recentBlockhash.value.blockhash);
      messageBuilder.add(blockhashBytes);
      log('✅ Recent blockhash: ${recentBlockhash.value.blockhash}');

      // Instructions array (shortvec format)
      messageBuilder.add(_shortVecEncode(1)); // one instruction

      // Instruction format: [programIdIndex, shortvec(accountIndexes), shortvec(data)]
      messageBuilder.add([4]); // program ID index (escrow program at index 4)

      // Account indexes for the instruction (mapping to CreateChallenge struct order)
      // CreateChallenge expects: [initiator, witness, challenge, system_program]
      // Transaction accounts: [initiator(0), challenge(1), witness(2), system_program(3), escrow_program(4)]
      final accountIndexes = [
        0, // initiator
        2, // witness
        1, // challenge
        3, // system_program
      ];
      messageBuilder.add(_shortVecEncode(accountIndexes.length));
      for (final index in accountIndexes) {
        messageBuilder.add([index]);
      }

      // Instruction data
      messageBuilder.add(_shortVecEncode(instructionData.length));
      messageBuilder.add(instructionData);

      final transactionMessage = messageBuilder.toBytes();
      log('✅ Built transaction message: ${transactionMessage.length} bytes');

      return transactionMessage;
    } catch (e) {
      log('❌ Error building challenge transaction: $e');
      rethrow;
    }
  }

  // Helper methods for transaction building
  List<int> _shortVecEncode(int value) {
    final out = <int>[];
    var v = value;
    while (true) {
      var elem = v & 0x7f;
      v >>= 7;
      if (v == 0) {
        out.add(elem);
        break;
      } else {
        out.add(elem | 0x80);
      }
    }
    return out;
  }

  List<int> _base58Decode(String input) {
    try {
      // Use solana package for proper base58 decoding
      final publicKey = Ed25519HDPublicKey.fromBase58(input);
      return publicKey.bytes;
    } catch (e) {
      // Fallback for special addresses
      if (input == '11111111111111111111111111111111') {
        return List.filled(32, 0); // System program
      } else {
        throw Exception('Invalid base58 address: $input');
      }
    }
  }
}
