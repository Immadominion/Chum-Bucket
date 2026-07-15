import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart' as solana;
import 'package:solana/encoder.dart' as encoder;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/challenges/data/mwa_challenge_service.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart'
    show LoadingState;
import 'package:chumbucket/core/services/analytics_service.dart';
import 'package:chumbucket/core/config/network_config.dart';

/// Pinocchio program instruction discriminators
class PinocchioInstructions {
  static const int createChallenge = 0x01;
  static const int resolveChallenge = 0x02;
  static const int cancelChallenge = 0x03;
}

/// MWA-based wallet provider for Pinocchio escrow program
/// Replaces Privy embedded wallet with Mobile Wallet Adapter
class MwaWalletProvider extends ChangeNotifier {
  // Pinocchio program ID (deployed to devnet)
  static const String ESCROW_PROGRAM_ID =
      'D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1';

  // Platform fee wallet
  static const String PLATFORM_FEE_WALLET =
      '3yHQosvdAhoFZHs66iFcdfRuT2aApAu6Yst2yoeDNjZm';

  // System program
  static const String SYSTEM_PROGRAM_ID = '11111111111111111111111111111111';

  // Minimum stake (0.01 SOL in lamports)
  static const int MIN_STAKE_LAMPORTS = 10_000_000;

  // Challenge account size (matches Pinocchio struct)
  static const int CHALLENGE_ACCOUNT_SIZE = 146;

  late final solana.SolanaClient _client;
  MwaChallengeService? _challengeService;

  double _balance = 0.0;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isLoading = false;
  String? _walletAddress;
  LoadingState _loadingState = LoadingState.idle;

  // Getters
  double get balance => _balance;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  String? get walletAddress => _walletAddress;
  LoadingState get loadingState => _loadingState;

  MwaWalletProvider() {
    final rpcUrl = NetworkConfig.rpcUrl;
    _client = solana.SolanaClient(
      rpcUrl: Uri.parse(rpcUrl),
      websocketUrl: Uri.parse(
        rpcUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws'),
      ),
    );
    log(
      'MwaWalletProvider initialized with RPC: $rpcUrl (network: ${NetworkConfig.currentNetwork})',
      name: 'MwaWalletProvider',
    );
  }

  void setChallengeService(MwaChallengeService service) {
    _challengeService = service;
  }

  /// Get or create the challenge service (lazy initialization)
  MwaChallengeService _getOrCreateChallengeService() {
    if (_challengeService == null) {
      log('Creating MwaChallengeService lazily', name: 'MwaWalletProvider');
      _challengeService = MwaChallengeService(
        supabase: Supabase.instance.client,
      );
    }
    return _challengeService!;
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    _loadingState = loading ? LoadingState.loading : LoadingState.idle;
    notifyListeners();
  }

  void _setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Initialize wallet from MWA auth provider
  Future<void> initializeFromAuth(MwaAuthProvider authProvider) async {
    log(
      '🔄 initializeFromAuth called - current state: isInitialized=$_isInitialized, walletAddress=$_walletAddress',
      name: 'MwaWalletProvider',
    );
    log(
      '🔄 authProvider.walletAddress = ${authProvider.walletAddress}',
      name: 'MwaWalletProvider',
    );

    // Check if already initialized for a DIFFERENT wallet - if so, force re-init
    if (_isInitialized && _walletAddress != authProvider.walletAddress) {
      log(
        '🔄 Wallet address changed from $_walletAddress to ${authProvider.walletAddress}, clearing and re-initializing',
        name: 'MwaWalletProvider',
      );
      clear();
    }

    if (_isInitialized && _walletAddress == authProvider.walletAddress) {
      log(
        '⚠️ Wallet already initialized for same address, skipping',
        name: 'MwaWalletProvider',
      );
      return;
    }

    if (!authProvider.isAuthenticated) {
      throw Exception('User must be authenticated to initialize wallet');
    }

    _setLoading(true);
    try {
      _walletAddress = authProvider.walletAddress;
      await refreshBalance(authProvider.walletAddress!);
      _isInitialized = true;
      log(
        '✅ Wallet initialized for ${authProvider.walletAddress}',
        name: 'MwaWalletProvider',
      );
    } catch (e) {
      _setError('Failed to initialize wallet: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Clear wallet state (for logout)
  void clear() {
    log('🧹 Clearing wallet state for logout', name: 'MwaWalletProvider');
    _balance = 0.0;
    _isInitialized = false;
    _errorMessage = null;
    _isLoading = false;
    _walletAddress = null;
    _loadingState = LoadingState.idle;
    _challengeService = null;
    log(
      '✅ Wallet state cleared - isInitialized: $_isInitialized, walletAddress: $_walletAddress',
      name: 'MwaWalletProvider',
    );
    notifyListeners();
  }

  /// Refresh wallet balance using stored wallet address
  Future<void> refreshWalletBalance() async {
    if (_walletAddress == null) {
      log(
        'No wallet address set, cannot refresh balance',
        name: 'MwaWalletProvider',
      );
      return;
    }
    await refreshBalance(_walletAddress!);
  }

  /// Refresh wallet balance
  Future<void> refreshBalance(String walletAddress) async {
    try {
      final publicKey = solana.Ed25519HDPublicKey.fromBase58(walletAddress);
      final balanceResponse = await _client.rpcClient.getBalance(
        publicKey.toBase58(),
      );
      _balance = balanceResponse.value / solana.lamportsPerSol;
      notifyListeners();
      log('Balance: $_balance SOL', name: 'MwaWalletProvider');
    } catch (e) {
      log('Error refreshing balance: $e', name: 'MwaWalletProvider');
    }
  }

  /// Derive challenge PDA from seeds
  /// Seeds: ["CHALLENGE", initiator, witness, challengeId]
  /// Returns (pda, bump)
  Future<(solana.Ed25519HDPublicKey, int)> deriveChallengeAddress({
    required String initiatorAddress,
    required String witnessAddress,
    required int challengeId,
  }) async {
    final initiatorPubkey = solana.Ed25519HDPublicKey.fromBase58(
      initiatorAddress,
    );
    final witnessPubkey = solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
    final programPubkey = solana.Ed25519HDPublicKey.fromBase58(
      ESCROW_PROGRAM_ID,
    );

    // challengeId as 8 bytes little endian
    final challengeIdBytes = Uint8List(8);
    ByteData.view(
      challengeIdBytes.buffer,
    ).setUint64(0, challengeId, Endian.little);

    // Find PDA with bump
    // Seeds: ["CHALLENGE", initiator_pubkey, witness_pubkey, challenge_id]
    int bump = 255;
    while (bump >= 0) {
      try {
        final pda = await solana.Ed25519HDPublicKey.createProgramAddress(
          seeds: [
            ...'CHALLENGE'.codeUnits,
            ...initiatorPubkey.bytes,
            ...witnessPubkey.bytes,
            ...challengeIdBytes,
            bump,
          ],
          programId: programPubkey,
        );
        return (pda, bump);
      } catch (_) {
        bump--;
      }
    }
    throw Exception('Could not find valid PDA');
  }

  /// Build create challenge transaction for Pinocchio program
  /// Returns serialized transaction bytes ready for MWA signing
  Future<Uint8List> buildCreateChallengeTransaction({
    required String initiatorAddress,
    required String witnessAddress,
    required double amountSol,
    required int durationDays,
    required int challengeId,
    required solana.Ed25519HDPublicKey challengePda,
    required int bump,
  }) async {
    log('Building create challenge transaction', name: 'MwaWalletProvider');

    final initiatorPubkey = solana.Ed25519HDPublicKey.fromBase58(
      initiatorAddress,
    );
    final witnessPubkey = solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
    final platformPubkey = solana.Ed25519HDPublicKey.fromBase58(
      PLATFORM_FEE_WALLET,
    );
    final programPubkey = solana.Ed25519HDPublicKey.fromBase58(
      ESCROW_PROGRAM_ID,
    );
    final systemPubkey = solana.Ed25519HDPublicKey.fromBase58(
      SYSTEM_PROGRAM_ID,
    );

    // Convert SOL to lamports
    final lamports = (amountSol * solana.lamportsPerSol).round();

    // Calculate deadline (current time + duration in seconds)
    final deadline =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) +
        (durationDays * 86400);

    // Build instruction data: discriminator(1) + lamports(8) + deadline(8) + challenge_id(8) + bump(1) = 26 bytes
    // Note: After discriminator is stripped by program, data is 25 bytes
    final instructionData = ByteData(26);
    instructionData.setUint8(0, PinocchioInstructions.createChallenge);
    instructionData.setUint64(1, lamports, Endian.little);
    instructionData.setInt64(9, deadline, Endian.little);
    instructionData.setUint64(17, challengeId, Endian.little);
    instructionData.setUint8(25, bump);

    // Build the instruction with account metas using encoder package
    // Accounts: [initiator (signer, writable), challenge (PDA, writable), platform_fee (writable), witness (readonly), system_program (readonly)]
    // Note: Challenge account is NOT a signer - the program will sign via invoke_signed
    final instruction = encoder.Instruction(
      programId: programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(pubKey: initiatorPubkey, isSigner: true),
        encoder.AccountMeta.writeable(
          pubKey: challengePda,
          isSigner: false,
        ), // PDA - NOT a signer
        encoder.AccountMeta.writeable(pubKey: platformPubkey, isSigner: false),
        encoder.AccountMeta.readonly(pubKey: witnessPubkey, isSigner: false),
        encoder.AccountMeta.readonly(pubKey: systemPubkey, isSigner: false),
      ],
      data: encoder.ByteArray(Uint8List.view(instructionData.buffer)),
    );

    // Get recent blockhash
    final blockhashResult = await _client.rpcClient.getLatestBlockhash();
    final blockhash = blockhashResult.value.blockhash;

    // Build message
    final message = encoder.Message.only(instruction);
    final compiledMessage = message.compile(
      recentBlockhash: blockhash,
      feePayer: initiatorPubkey,
    );

    // Create SignedTx with placeholder signature for MWA
    // MWA expects a serialized transaction with empty signatures that it will fill in
    final placeholderSignature = encoder.Signature(
      List.filled(64, 0),
      publicKey: initiatorPubkey,
    );

    final signedTx = encoder.SignedTx(
      compiledMessage: compiledMessage,
      signatures: [placeholderSignature],
    );

    final txBytes = signedTx.toByteArray();

    log(
      'Built create challenge tx: ${txBytes.length} bytes',
      name: 'MwaWalletProvider',
    );
    return Uint8List.fromList(txBytes.toList());
  }

  /// Build resolve challenge transaction for Pinocchio program
  /// NOTE: WITNESS must sign (witness is the judge)
  Future<Uint8List> buildResolveChallengeTransaction({
    required String challengeAddress,
    required String initiatorAddress,
    required String witnessAddress,
    required bool initiatorWon,
  }) async {
    log('Building resolve challenge transaction', name: 'MwaWalletProvider');
    log('Challenge: $challengeAddress', name: 'MwaWalletProvider');
    log('Initiator: $initiatorAddress', name: 'MwaWalletProvider');
    log('Witness (signer): $witnessAddress', name: 'MwaWalletProvider');
    log('Initiator won: $initiatorWon', name: 'MwaWalletProvider');

    final challengePubkey = solana.Ed25519HDPublicKey.fromBase58(
      challengeAddress,
    );
    final initiatorPubkey = solana.Ed25519HDPublicKey.fromBase58(
      initiatorAddress,
    );
    final witnessPubkey = solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
    final platformPubkey = solana.Ed25519HDPublicKey.fromBase58(
      PLATFORM_FEE_WALLET,
    );
    final programPubkey = solana.Ed25519HDPublicKey.fromBase58(
      ESCROW_PROGRAM_ID,
    );

    // Build instruction data: discriminator(1) + initiator_won(1) = 2 bytes
    // Program does split_first on discriminator, so data becomes [initiator_won]
    final instructionData = Uint8List(2);
    instructionData[0] = PinocchioInstructions.resolveChallenge;
    instructionData[1] = initiatorWon ? 1 : 0;

    // Accounts order MUST match Pinocchio program (updated for witness-is-judge model):
    // [witness (signer), challenge, initiator, platform_fee_account]
    final instruction = encoder.Instruction(
      programId: programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(
          pubKey: witnessPubkey,
          isSigner: true,
        ), // Witness signs (judge)
        encoder.AccountMeta.writeable(pubKey: challengePubkey, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: initiatorPubkey, isSigner: false),
        encoder.AccountMeta.writeable(pubKey: platformPubkey, isSigner: false),
      ],
      data: encoder.ByteArray(instructionData),
    );

    // Get recent blockhash
    final blockhashResult = await _client.rpcClient.getLatestBlockhash();
    final blockhash = blockhashResult.value.blockhash;

    // Build message (witness is fee payer and signer)
    final message = encoder.Message.only(instruction);
    final compiledMessage = message.compile(
      recentBlockhash: blockhash,
      feePayer: witnessPubkey,
    );

    // Create SignedTx with placeholder signature for MWA
    final placeholderSignature = encoder.Signature(
      List.filled(64, 0),
      publicKey: witnessPubkey, // Witness signs
    );

    final signedTx = encoder.SignedTx(
      compiledMessage: compiledMessage,
      signatures: [placeholderSignature],
    );

    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Build cancel challenge transaction for Pinocchio program
  Future<Uint8List> buildCancelChallengeTransaction({
    required String challengeAddress,
    required String initiatorAddress,
    required String witnessAddress,
  }) async {
    log('Building cancel challenge transaction', name: 'MwaWalletProvider');

    final challengePubkey = solana.Ed25519HDPublicKey.fromBase58(
      challengeAddress,
    );
    final initiatorPubkey = solana.Ed25519HDPublicKey.fromBase58(
      initiatorAddress,
    );
    final witnessPubkey = solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
    final programPubkey = solana.Ed25519HDPublicKey.fromBase58(
      ESCROW_PROGRAM_ID,
    );

    // Build instruction data: discriminator(1) = 1 byte
    final instructionData = Uint8List(1);
    instructionData[0] = PinocchioInstructions.cancelChallenge;

    // Accounts order MUST match Pinocchio program:
    // [initiator (signer), challenge, witness]
    // NOTE: Witness is WRITEABLE because cancel does 50/50 split
    final instruction = encoder.Instruction(
      programId: programPubkey,
      accounts: [
        encoder.AccountMeta.writeable(pubKey: initiatorPubkey, isSigner: true),
        encoder.AccountMeta.writeable(pubKey: challengePubkey, isSigner: false),
        encoder.AccountMeta.writeable(
          pubKey: witnessPubkey,
          isSigner: false,
        ), // Writeable for 50/50 split
      ],
      data: encoder.ByteArray(instructionData),
    );

    // Get recent blockhash
    final blockhashResult = await _client.rpcClient.getLatestBlockhash();
    final blockhash = blockhashResult.value.blockhash;

    // Build message
    final message = encoder.Message.only(instruction);
    final compiledMessage = message.compile(
      recentBlockhash: blockhash,
      feePayer: initiatorPubkey,
    );

    // Create SignedTx with placeholder signature for MWA
    final placeholderSignature = encoder.Signature(
      List.filled(64, 0),
      publicKey: initiatorPubkey,
    );

    final signedTx = encoder.SignedTx(
      compiledMessage: compiledMessage,
      signatures: [placeholderSignature],
    );

    return Uint8List.fromList(signedTx.toByteArray().toList());
  }

  /// Create a new challenge on-chain using MWA
  Future<Challenge?> createChallenge({
    required String friendEmail,
    required String friendAddress,
    required double amount,
    required String challengeDescription,
    required int durationDays,
    required BuildContext context,
    String? witnessDisplayName, // Cached display name for the witness
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      final walletAddress = authProvider.walletAddress!;

      // Resolve .sol domains - simplified for now, can add SNS lookup later
      String witnessAddress = friendAddress.trim();

      // Resolve domain name to wallet address if needed
      final resolvedAddress = await AddressNameResolver.resolveAddress(
        witnessAddress,
      );
      if (resolvedAddress != null) {
        witnessAddress = resolvedAddress;
        log(
          'Resolved $friendAddress to $witnessAddress',
          name: 'MwaWalletProvider',
        );
      }

      // Validate address
      try {
        solana.Ed25519HDPublicKey.fromBase58(witnessAddress);
      } catch (_) {
        throw Exception('Invalid wallet address for friend');
      }

      // Validate minimum stake
      final lamports = (amount * solana.lamportsPerSol).round();
      if (lamports < MIN_STAKE_LAMPORTS) {
        throw Exception('Minimum stake is 0.01 SOL');
      }

      // Generate a unique challenge ID (use timestamp for simplicity)
      final challengeId = DateTime.now().millisecondsSinceEpoch;

      // Derive challenge PDA (not a random keypair)
      final (challengePda, bump) = await deriveChallengeAddress(
        initiatorAddress: walletAddress,
        witnessAddress: witnessAddress,
        challengeId: challengeId,
      );
      log(
        'Derived challenge PDA: ${challengePda.toBase58()} (bump: $bump, id: $challengeId)',
        name: 'MwaWalletProvider',
      );

      // Check if challenge account already exists (PDA collision)
      try {
        final accountInfo = await _client.rpcClient.getAccountInfo(
          challengePda.toBase58(),
        );
        if (accountInfo.value != null) {
          // This should be very rare with timestamp, but possible if user spams
          throw Exception(
            'A challenge with this ID already exists. Please try again.',
          );
        }
      } catch (e) {
        if (e.toString().contains('already exists')) {
          rethrow;
        }
        // Account doesn't exist - this is expected, continue
        log(
          'Challenge account does not exist yet (expected)',
          name: 'MwaWalletProvider',
        );
      }

      // Build the transaction
      final txBytes = await buildCreateChallengeTransaction(
        initiatorAddress: walletAddress,
        witnessAddress: witnessAddress,
        amountSol: amount,
        durationDays: durationDays,
        challengeId: challengeId,
        challengePda: challengePda,
        bump: bump,
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      String txSignature;
      try {
        // Sign and send transaction via MWA
        // Note: MWA signs with user's wallet (initiator)
        // The challenge account is a PDA - no separate signature needed
        // The program will sign for it via invoke_signed

        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        txSignature = base58encode(Uint8List.fromList(result.signatures.first));
        log(
          '✅ Challenge created on-chain: $txSignature',
          name: 'MwaWalletProvider',
        );
        log(
          '🔗 Explorer: ${NetworkConfig.getExplorerUrl(txSignature)}',
          name: 'MwaWalletProvider',
        );
      } finally {
        // CRITICAL: Close MWA session BEFORE making any network calls
        // On Seeker, the app may be in background during MWA which blocks network
        await signingSession.close();
        log('🔒 MWA session closed', name: 'MwaWalletProvider');
      }

      // Small delay to ensure app is fully foregrounded after MWA closes
      await Future.delayed(const Duration(milliseconds: 500));

      // NOW persist challenge in database (after MWA session is closed)
      log('📤 Persisting challenge to database...', name: 'MwaWalletProvider');
      final challengeService = _getOrCreateChallengeService();
      final createdChallenge = await challengeService.createChallenge(
        title: 'Challenge with $friendEmail',
        description: challengeDescription,
        amountInSol: amount,
        creatorWalletAddress: walletAddress,
        member1Address: walletAddress,
        member2Address: witnessAddress,
        expiresAt: DateTime.now().add(Duration(days: durationDays)),
        participantEmail: friendEmail,
        onChainAddress: challengePda.toBase58(),
        witnessDisplayName: witnessDisplayName,
      );

      // Update challenge state provider
      final challengeStateProvider = Provider.of<ChallengeStateProvider>(
        context,
        listen: false,
      );
      challengeStateProvider.addChallenge(createdChallenge);

      // Track analytics for challenge creation (fire-and-forget)
      // Calculate fee: 5% of amount
      final feeSol = amount * 0.05;
      AnalyticsService.trackChallengeCreated(
        challengeId: createdChallenge.id,
        creatorWallet: walletAddress,
        creatorName:
            authProvider.snsDomain ?? authProvider.authResult?.accountLabel,
        witnessWallet: witnessAddress,
        witnessName: witnessDisplayName,
        amountSol: amount,
        feeSol: feeSol,
      ).catchError((e) {
        log('⚠️ Analytics tracking failed: $e', name: 'MwaWalletProvider');
      });

      await refreshBalance(walletAddress);
      return createdChallenge;
    } catch (e, stackTrace) {
      log('❌ Error creating challenge: $e', name: 'MwaWalletProvider');
      log('Stack trace: $stackTrace', name: 'MwaWalletProvider');
      _setError('Failed to create challenge: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Resolve a challenge (witness resolves - "Witness is Judge" model)
  /// NOTE: Only the WITNESS can resolve per updated Pinocchio program design
  Future<String?> resolveChallenge({
    required String challengeAddress,
    required String initiatorAddress,
    required bool initiatorWon,
    required BuildContext context,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      // The connected wallet is the WITNESS (only witness can resolve)
      final witnessAddress = authProvider.walletAddress!;

      log(
        '🔄 Resolving challenge (witness is judge):',
        name: 'MwaWalletProvider',
      );
      log('  Challenge: $challengeAddress', name: 'MwaWalletProvider');
      log('  Initiator: $initiatorAddress', name: 'MwaWalletProvider');
      log('  Witness (signer): $witnessAddress', name: 'MwaWalletProvider');
      log('  Initiator Won: $initiatorWon', name: 'MwaWalletProvider');

      // Build the transaction
      final txBytes = await buildResolveChallengeTransaction(
        challengeAddress: challengeAddress,
        initiatorAddress: initiatorAddress,
        witnessAddress: witnessAddress,
        initiatorWon: initiatorWon,
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      try {
        // Sign and send transaction via MWA
        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        final txSignature = base58encode(
          Uint8List.fromList(result.signatures.first),
        );
        log('✅ Challenge resolved: $txSignature', name: 'MwaWalletProvider');

        await refreshBalance(witnessAddress);
        return txSignature;
      } finally {
        await signingSession.close();
      }
    } catch (e) {
      log('❌ Error resolving challenge: $e', name: 'MwaWalletProvider');
      _setError('Failed to resolve challenge: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Cancel a challenge (initiator only, before deadline)
  Future<String?> cancelChallenge({
    required String challengeAddress,
    required String witnessAddress,
    required BuildContext context,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      final initiatorAddress = authProvider.walletAddress!;

      // Build the transaction
      final txBytes = await buildCancelChallengeTransaction(
        challengeAddress: challengeAddress,
        initiatorAddress: initiatorAddress,
        witnessAddress: witnessAddress,
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      try {
        // Sign and send transaction via MWA
        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        final txSignature = base58encode(
          Uint8List.fromList(result.signatures.first),
        );
        log('✅ Challenge cancelled: $txSignature', name: 'MwaWalletProvider');

        await refreshBalance(initiatorAddress);
        return txSignature;
      } finally {
        await signingSession.close();
      }
    } catch (e) {
      log('❌ Error cancelling challenge: $e', name: 'MwaWalletProvider');
      _setError('Failed to cancel challenge: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Request airdrop for testing on devnet
  Future<bool> requestAirdrop(
    String walletAddress, {
    double amount = 1.0,
  }) async {
    try {
      final lamports = (amount * solana.lamportsPerSol).round();
      final pubkey = solana.Ed25519HDPublicKey.fromBase58(walletAddress);

      await _client.requestAirdrop(address: pubkey, lamports: lamports);

      // Wait a bit for confirmation
      await Future.delayed(const Duration(seconds: 2));
      await refreshBalance(walletAddress);

      log('✅ Airdrop successful: $amount SOL', name: 'MwaWalletProvider');
      return true;
    } catch (e) {
      log('❌ Airdrop failed: $e', name: 'MwaWalletProvider');
      return false;
    }
  }

  /// Transfer SOL to another address using MWA
  Future<String?> transferSol({
    required String destinationAddress,
    required double amount,
    required BuildContext context,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
      if (!authProvider.isAuthenticated) {
        throw Exception('User must be authenticated');
      }

      final senderAddress = authProvider.walletAddress!;
      final lamports = (amount * solana.lamportsPerSol).round();

      // Validate destination address
      solana.Ed25519HDPublicKey destPubkey;
      try {
        destPubkey = solana.Ed25519HDPublicKey.fromBase58(destinationAddress);
      } catch (_) {
        throw Exception('Invalid destination address');
      }

      final senderPubkey = solana.Ed25519HDPublicKey.fromBase58(senderAddress);

      // Build transfer instruction
      final instruction = solana.SystemInstruction.transfer(
        fundingAccount: senderPubkey,
        recipientAccount: destPubkey,
        lamports: lamports,
      );

      // Get recent blockhash
      final blockhashResult = await _client.rpcClient.getLatestBlockhash();
      final blockhash = blockhashResult.value.blockhash;

      // Build message
      final message = solana.Message.only(instruction);
      final compiledMessage = message.compile(
        recentBlockhash: blockhash,
        feePayer: senderPubkey,
      );

      final txBytes = Uint8List.fromList(
        compiledMessage.toByteArray().toList(),
      );

      // Create MWA signing session
      final signingSession = await authProvider.createSigningSession();
      if (signingSession == null) {
        throw Exception('Failed to create signing session');
      }

      try {
        // Sign and send transaction via MWA
        final result = await signingSession.signAndSendTransactions(
          transactions: [txBytes],
        );

        if (result.signatures.isEmpty) {
          throw Exception('Transaction signing failed');
        }

        final txSignature = base58encode(
          Uint8List.fromList(result.signatures.first),
        );
        log(
          '✅ SOL transfer successful: $txSignature',
          name: 'MwaWalletProvider',
        );

        await refreshBalance(senderAddress);
        return txSignature;
      } finally {
        await signingSession.close();
      }
    } catch (e) {
      log('❌ Error transferring SOL: $e', name: 'MwaWalletProvider');
      _setError('Failed to transfer SOL: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Get fee breakdown for a challenge amount
  Map<String, double> getFeeBreakdown(double challengeAmount) {
    if (_challengeService == null) {
      return {
        'challengeAmount': challengeAmount,
        'platformFee': 0.0,
        'winnerAmount': challengeAmount,
        'feePercentage': 0.0,
      };
    }
    return MwaChallengeService.getFeeBreakdown(challengeAmount);
  }
}
