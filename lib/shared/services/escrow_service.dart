import 'dart:convert';
import 'dart:developer';
import 'package:chumbucket/features/wallet/data/privy_wallet.dart';
import 'package:flutter/services.dart';
import 'package:coral_xyz/coral_xyz_anchor.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EscrowService {
  static const String PROGRAM_ID =
      'Es4Z5VVh54APWZ2LFy1FRebbHwPpSpA8W47oAfPrA4bV';
  static const int LAMPORTS_PER_SOL = 1000000000;

  // Private members to store the initialized program and provider
  late final Program _program;
  late final AnchorProvider _provider;
  late final PrivyWallet _wallet;
  late final Connection _connection;

  EscrowService._();

  /// Create and initialize EscrowService with PrivyWallet and coral-xyz-anchor
  static Future<EscrowService> create({
    required EmbeddedSolanaWallet embeddedWallet,
    required String walletAddress,
    String rpcUrl = 'https://api.devnet.solana.com',
  }) async {
    log('🚀 Initializing EscrowService');
    log('🔗 RPC URL: $rpcUrl');
    log('🔑 Wallet Address: $walletAddress');

    final service = EscrowService._();

    try {
      // Load IDL
      final idlJson = await rootBundle.loadString(
        'assets/chumbucket_escrow_idl.json',
      );
      final idlMap = jsonDecode(idlJson) as Map<String, dynamic>;
      final idl = Idl.fromJson(idlMap);
      log('📋 IDL loaded successfully');

      // Setup connection and wallet provider
      service._connection = Connection(rpcUrl);
      service._wallet = PrivyWallet(
        walletAddress: walletAddress,
        embeddedWallet: embeddedWallet,
      );
      service._provider = AnchorProvider(service._connection, service._wallet);

      // Initialize Program
      service._program = Program.withProgramId(
        idl,
        PublicKey.fromBase58(PROGRAM_ID),
        provider: service._provider,
      );
      log('📦 Program initialized: ${service._program.programId}');

      // Verify program exists on-chain
      try {
        final programAccount = await service._connection.getAccountInfo(
          PublicKey.fromBase58(PROGRAM_ID).toBase58(),
        );
        if (programAccount == null) {
          throw Exception(
            'Program not found on-chain. Please deploy it first.',
          );
        }
        log('✅ Program account verified on-chain');
      } catch (e) {
        log('⚠️ Warning: Could not verify program on-chain: $e');
        // Continue anyway - might be network issue
      }

      log('✅ EscrowService initialized successfully');
      return service;
    } catch (e, stackTrace) {
      log('❌ Failed to initialize EscrowService: $e');
      log('📍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Get the current wallet address
  String get walletAddress => _wallet.publicKey.toBase58();

  /// Create a new challenge on-chain
  Future<String> createChallenge({
    required String initiatorAddress,
    required String witnessAddress,
    required double amountSol,
    required int durationDays,
    String? description, // Add description parameter
  }) async {
    log('🚀 Creating challenge on-chain');
    log('💰 Amount: $amountSol SOL');
    log('⏰ Duration: $durationDays days');
    log('👤 Initiator: $initiatorAddress');
    log('👁️ Witness: $witnessAddress');

    try {
      // Convert SOL to lamports
      final lamports = BigInt.from((amountSol * LAMPORTS_PER_SOL).round());

      // Calculate deadline (current time + duration in seconds)
      final deadline = BigInt.from(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + durationDays * 86400,
      );

      // Generate new challenge keypair - this will be the account that stores the challenge data
      final challengeKeypair = await Keypair.generate();
      log('🔑 Generated challenge keypair: ${challengeKeypair.publicKey}');

      // Build accounts map for the instruction
      final accounts = {
        'initiator': PublicKey.fromBase58(initiatorAddress),
        'witness': PublicKey.fromBase58(witnessAddress),
        'challenge': challengeKeypair.publicKey,
        'system_program': SystemProgram.programId,
      };
      //TODO: Add platform wallet to accounts if needed

      log('📦 Calling create_challenge instruction...');

      // Call the create_challenge instruction
      final signature =
          await (_program.methods as dynamic)
              .create_challenge(lamports, deadline)
              .accounts(accounts)
              .signers([challengeKeypair])
              .rpc();

      // Store the description in a map for later retrieval (temporary solution)
      if (description != null && description.isNotEmpty) {
        log('📝 Storing description for challenge: $description');
        await _storeDescriptionLocally(
          challengeKeypair.publicKey.toString(),
          description,
        );
      }
      log('✅ Challenge created successfully!');
      log('📝 Transaction Signature: $signature');
      log('🏦 Challenge Account: ${challengeKeypair.publicKey}');

      // Return both signature and challenge address (we'll use challenge address as identifier)
      return '${challengeKeypair.publicKey}';
    } catch (e, stackTrace) {
      log('❌ Error creating challenge: $e');
      log('📍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Resolve an existing challenge on-chain
  Future<String> resolveChallenge({
    required String challengeAddress,
    required String initiatorAddress,
    required String witnessAddress,
    required bool success,
  }) async {
    log('🎯 Resolving challenge on-chain');
    log('🏦 Challenge: $challengeAddress');
    log('👤 Initiator: $initiatorAddress');
    log('👁️ Witness: $witnessAddress');
    log('🏆 Success (initiator wins): $success');

    try {
      // Get platform wallet address from environment
      final platformWallet =
          dotenv.env['PLATFORM_WALLET_ADDRESS'] ??
          '3yHQosvdAhoFZHs66iFcdfRuT2aApAu6Yst2yoeDNjZm';

      // Build accounts map for the instruction
      final accounts = {
        'challenge': PublicKey.fromBase58(challengeAddress),
        'initiator': PublicKey.fromBase58(initiatorAddress),
        'witness': PublicKey.fromBase58(witnessAddress),
        // FIX: IDL account name uses snake_case
        'platform_wallet': PublicKey.fromBase58(platformWallet),
      };

      log('📦 Calling resolve_challenge instruction...');

      // Call the resolve_challenge instruction
      final signature =
          await (_program.methods as dynamic)
              .resolve_challenge(success)
              .accounts(accounts)
              .rpc();

      log('✅ Challenge resolved successfully!');
      log('📝 Transaction Signature: $signature');

      return signature;
    } catch (e, stackTrace) {
      log('❌ Error resolving challenge: $e');
      log('📍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Fetch challenge data from on-chain
  Future<Map<String, dynamic>?> getChallengeData(
    String challengeAddress,
  ) async {
    try {
      log('📊 Fetching challenge data for: $challengeAddress');

      final challengeAccount = await _program.account['Challenge']!.fetch(
        PublicKey.fromBase58(challengeAddress),
      );

      if (challengeAccount == null) {
        log('⚠️ Challenge not found: $challengeAddress');
        return null;
      }

      // Convert BigInt values to regular numbers for easier handling
      final data = Map<String, dynamic>.from(challengeAccount);

      // Convert lamports to SOL for display
      if (data['amount'] != null) {
        data['amountSol'] =
            (data['amount'] as BigInt).toDouble() / LAMPORTS_PER_SOL;
      }
      if (data['original_amount'] != null) {
        data['originalAmountSol'] =
            (data['original_amount'] as BigInt).toDouble() / LAMPORTS_PER_SOL;
      }
      if (data['platform_fee'] != null) {
        data['platformFeeSol'] =
            (data['platform_fee'] as BigInt).toDouble() / LAMPORTS_PER_SOL;
      }

      log('✅ Challenge data fetched successfully');
      return data;
    } catch (e, stackTrace) {
      log('❌ Error fetching challenge data: $e');
      log('📍 Stack trace: $stackTrace');
      return null;
    }
  }

  /// Check if the current wallet is the initiator of a challenge
  Future<bool> isInitiator(String challengeAddress) async {
    try {
      final challengeData = await getChallengeData(challengeAddress);
      if (challengeData == null) return false;

      final initiatorKey = challengeData['initiator'] as PublicKey;
      return initiatorKey.toString() == _wallet.publicKey.toString();
    } catch (e) {
      log('❌ Error checking initiator: $e');
      return false;
    }
  }

  /// Get current wallet's SOL balance
  Future<double> getBalance() async {
    try {
      final balance = await _connection.getBalance(
        _wallet.publicKey.toBase58(),
      );
      return balance.toDouble() / LAMPORTS_PER_SOL;
    } catch (e) {
      log('❌ Error getting balance: $e');
      return 0.0;
    }
  }

  /// Store challenge description locally (temporary solution until on-chain storage)
  static final Map<String, String> _challengeDescriptions = {};

  Future<void> _storeDescriptionLocally(
    String challengeAddress,
    String description,
  ) async {
    _challengeDescriptions[challengeAddress] = description;
    log('💾 Stored description locally for $challengeAddress');
  }

  /// Retrieve challenge description from local storage
  String? getStoredDescription(String challengeAddress) {
    return _challengeDescriptions[challengeAddress];
  }

  /// Static method to retrieve descriptions (for use in blockchain sync)
  static String? getStoredDescriptionStatic(String challengeAddress) {
    return _challengeDescriptions[challengeAddress];
  }
}
