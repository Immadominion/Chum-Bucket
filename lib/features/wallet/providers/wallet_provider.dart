import 'dart:convert';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:solana/solana.dart' as solana;
import 'package:coral_xyz/coral_xyz_anchor.dart';
import 'package:coral_xyz/src/types/transaction.dart' as coral_types;
import 'package:privy_flutter/privy_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart';
import 'package:chumbucket/features/challenges/data/challenge_service.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:chumbucket/shared/services/address_name_resolver.dart';
import 'package:chumbucket/features/wallet/data/privy_wallet.dart';

class WalletProvider extends BaseChangeNotifier {
  // Create solana client for network operations
  late final solana.SolanaClient _client = solana.SolanaClient(
    rpcUrl: Uri.parse(
      dotenv.env['SOLANA_RPC_URL'] ?? 'https://api.devnet.solana.com',
    ),
    websocketUrl: Uri.parse(
      (dotenv.env['SOLANA_RPC_URL'] ?? 'https://api.devnet.solana.com')
          .replaceFirst('http', 'ws'),
    ),
  );

  String? _walletAddress;
  double _balance = 0.0;
  bool _isInitialized = false;
  EmbeddedSolanaWallet? _embeddedWallet;
  ChallengeService? _challengeService;

  // Chumbucket Escrow Program ID (deployed)
  static const String ESCROW_PROGRAM_ID =
      'Es4Z5VVh54APWZ2LFy1FRebbHwPpSpA8W47oAfPrA4bV';
  static const String PLATFORM_WALLET =
      '3yHQosvdAhoFZHs66iFcdfRuT2aApAu6Yst2yoeDNjZm';

  String? get walletAddress => _walletAddress;
  double get balance => _balance;
  bool get isInitialized => _isInitialized;
  EmbeddedSolanaWallet? get embeddedWallet => _embeddedWallet;
  ChallengeService? get challengeService => _challengeService;
  solana.SolanaClient get solanaClient => _client;

  /// Get formatted display address (first 4 + last 4 characters)
  String? get displayAddress {
    if (_walletAddress == null) return null;
    if (_walletAddress!.length <= 8) return _walletAddress;
    return '${_walletAddress!.substring(0, 4)}...${_walletAddress!.substring(_walletAddress!.length - 4)}';
  }

  WalletProvider() {
    // Initialize the challenge service with dart-coral-xyz automation
    _challengeService = ChallengeService(supabase: Supabase.instance.client);
  }

  /// Signs and sends a transaction using Privy wallet message signing
  Future<String?> signAndSendTransaction(List<int> transactionBytes) async {
    if (_embeddedWallet == null) {
      AppLogger.debug(
        'No embedded wallet available for signing and sending transaction',
        tag: 'WalletProvider',
      );
      return null;
    }

    if (_walletAddress == null) {
      AppLogger.debug(
        'No wallet address available for transaction signing',
        tag: 'WalletProvider',
      );
      return null;
    }

    try {
      AppLogger.debug(
        '🔑 Signing and sending transaction with Privy wallet',
        tag: 'WalletProvider',
      );
      AppLogger.debug(
        'Transaction size: ${transactionBytes.length} bytes',
        tag: 'WalletProvider',
      );

      // Convert transaction bytes to Uint8List for processing
      final txBytes = Uint8List.fromList(transactionBytes);

      // Extract the number of required signatures from the message header (legacy format)
      // Message header layout: [numRequiredSignatures, numReadonlySigned, numReadonlyUnsigned, ...]
      if (txBytes.isEmpty) {
        AppLogger.debug('❌ Transaction bytes are empty', tag: 'WalletProvider');
        return null;
      }
      final numRequiredSignatures = txBytes[0];
      AppLogger.debug(
        'Message header indicates $numRequiredSignatures required signature(s)',
      );

      if (numRequiredSignatures == 0) {
        AppLogger.debug(
          '❌ Invalid message: requires 0 signatures',
          tag: 'WalletProvider',
        );
        return null;
      }

      // Step 1: Use Privy to sign the transaction message (compiled message bytes)
      AppLogger.debug(
        '📝 Signing transaction message with Privy wallet...',
        tag: 'WalletProvider',
      );

      final transactionBase64 = base64Encode(txBytes);
      final signatureResult = await _embeddedWallet!.provider.signMessage(
        transactionBase64,
      );

      if (signatureResult is Success<String>) {
        final signatureBase64 = signatureResult.value;
        Uint8List signatureBytes;
        try {
          signatureBytes = base64Decode(signatureBase64);
        } catch (e) {
          AppLogger.debug(
            '❌ Could not decode signature from base64: $e',
            tag: 'WalletProvider',
          );
          return null;
        }

        AppLogger.debug(
          '✅ Message signed. Signature length: ${signatureBytes.length} bytes',
        );

        if (signatureBytes.length != 64) {
          AppLogger.debug(
            '❌ Invalid signature length: ${signatureBytes.length}. Expected 64 bytes',
          );
          return null;
        }

        if (numRequiredSignatures > 1) {
          // Transaction requires multiple signatures, but only one is available
          AppLogger.debug(
            '❌ Message requires $numRequiredSignatures signatures, but only one signature is available',
          );
          AppLogger.debug(
            '   This transaction cannot be sent without all required signatures',
          );
          return null;
        }

        // Step 2: Construct the legacy transaction wire format:
        // tx = shortvec(num signatures) || signatures (each 64 bytes) || compiled message bytes
        AppLogger.debug(
          '🔧 Constructing signed transaction bytes (legacy wire format)...',
          tag: 'WalletProvider',
        );

        final builder = BytesBuilder();
        builder.add(_shortVecEncode(1)); // one signature
        builder.add(signatureBytes);
        builder.add(txBytes);

        final signedTxBytes = builder.toBytes();
        final signedTxBase64 = base64Encode(signedTxBytes);
        AppLogger.debug(
          'Constructed signed tx length: ${signedTxBytes.length} bytes',
          tag: 'WalletProvider',
        );

        // Step 3: Send the signed transaction to Solana network
        AppLogger.debug(
          '📡 Sending signed transaction to Solana network...',
          tag: 'WalletProvider',
        );
        AppLogger.debug(
          '🔍 RPC URL: ${_client.rpcClient}',
          tag: 'WalletProvider',
        );
        AppLogger.debug(
          '🔍 Transaction base64 preview: ${signedTxBase64.substring(0, 50)}...',
        );

        try {
          final txSignature = await _client.rpcClient.sendTransaction(
            signedTxBase64,
            preflightCommitment: solana.Commitment.confirmed,
          );

          AppLogger.debug(
            '🎉 Transaction sent: $txSignature',
            tag: 'WalletProvider',
          );
          AppLogger.debug(
            '🔗 Explorer: https://explorer.solana.com/tx/$txSignature?cluster=devnet',
          );
          return txSignature;
        } catch (sendError) {
          AppLogger.debug(
            '❌ Failed to send signed transaction: $sendError',
            tag: 'WalletProvider',
          );
          AppLogger.debug(
            '❌ Error type: ${sendError.runtimeType}',
            tag: 'WalletProvider',
          );
          AppLogger.debug(
            '❌ Stack trace: ${sendError.toString()}',
            tag: 'WalletProvider',
          );
          AppLogger.debug(
            '❌ Signed transaction base64 (first 100 chars): ${signedTxBase64.substring(0, 100)}',
          );
          AppLogger.debug(
            '❌ Original transaction bytes: ${txBytes.length} bytes',
            tag: 'WalletProvider',
          );

          // Check for specific Solana errors
          final errorStr = sendError.toString().toLowerCase();
          if (errorStr.contains('failed host lookup') ||
              errorStr.contains('connection refused') ||
              errorStr.contains('network error') ||
              errorStr.contains('socketerror') ||
              errorStr.contains('connection timed out')) {
            AppLogger.debug(
              '❌ Network connectivity issue detected',
              tag: 'WalletProvider',
            );
            throw Exception(
              'Network error: Cannot connect to Solana devnet. Please check your internet connection.',
            );
          } else if (errorStr.contains('invalid transaction') ||
              errorStr.contains('transaction signature verification failure') ||
              errorStr.contains('blockhash not found')) {
            AppLogger.debug(
              '❌ Transaction validation error detected',
              tag: 'WalletProvider',
            );
            throw Exception('Transaction validation failed: $sendError');
          } else {
            AppLogger.debug(
              '❌ Unknown error type - rethrowing',
              tag: 'WalletProvider',
            );
            throw Exception('Transaction send failed: $sendError');
          }
        }
      } else if (signatureResult is Failure) {
        AppLogger.debug(
          '❌ Failed to sign message with Privy: ${signatureResult.toString()}',
        );
        return null;
      }

      AppLogger.debug(
        '❌ Unknown response type from signMessage',
        tag: 'WalletProvider',
      );
      return null;
    } catch (e) {
      AppLogger.debug(
        '❌ Error in signAndSendTransaction: $e',
        tag: 'WalletProvider',
      );
      AppLogger.debug(
        '❌ This error should be handled more specifically above',
        tag: 'WalletProvider',
      );
      rethrow; // Don't swallow the exception - let it bubble up
    }
  }

  /// Signs and sends a transaction with cosigners: Privy wallet first, then local cosigners
  Future<String?> signAndSendTransactionWithCosigners({
    required List<int> transactionBytes,
    required List<solana.Ed25519HDKeyPair> cosigners,
  }) async {
    if (_embeddedWallet == null) {
      AppLogger.debug(
        'No embedded wallet available for signing and sending transaction',
        tag: 'WalletProvider',
      );
      return null;
    }

    try {
      final txBytes = Uint8List.fromList(transactionBytes);
      if (txBytes.isEmpty) return null;
      final numRequiredSignatures = txBytes[0];
      AppLogger.debug(
        'Message requires $numRequiredSignatures signatures. Cosigners provided: ${cosigners.length}',
      );

      // First signature from Privy embedded wallet (fee payer)
      final transactionBase64 = base64Encode(txBytes);
      // Fee-payer signature from Privy
      final signatureResult = await _embeddedWallet!.provider.signMessage(
        transactionBase64,
      );
      // Check for failure or unexpected type
      if (signatureResult is Failure) {
        AppLogger.debug(
          '❌ Privy signing failed: $signatureResult',
          tag: 'WalletProvider',
        );
        return null;
      }
      // Extract and validate signature value
      final dynamic sigValue = (signatureResult as Success).value;
      if (sigValue is! String) {
        AppLogger.debug(
          '❌ Invalid signature value type: ${sigValue.runtimeType}',
          tag: 'WalletProvider',
        );
        return null;
      }
      final feePayerSig = base64Decode(sigValue);
      if (feePayerSig.length != 64) {
        AppLogger.debug(
          '❌ Invalid fee payer signature length',
          tag: 'WalletProvider',
        );
        return null;
      }

      // Cosigner signatures (local, deterministic createKey etc.)
      final coSigs = <Uint8List>[];
      for (final kp in cosigners) {
        final sig = await kp.sign(txBytes);
        coSigs.add(Uint8List.fromList(sig.bytes));
      }

      if (1 + coSigs.length < numRequiredSignatures) {
        AppLogger.debug(
          '❌ Not enough signatures. Needed: $numRequiredSignatures, have: ${1 + coSigs.length}',
        );
        return null;
      }

      // Construct signed transaction: shortvec(count) || sigs || message
      final builder = BytesBuilder();
      final sigCount = numRequiredSignatures;

      // Add signature count
      builder.add(_shortVecEncode(sigCount));

      // Add fee payer signature first
      builder.add(feePayerSig);

      // Add cosigner signatures
      for (var i = 0; i < sigCount - 1; i++) {
        builder.add(coSigs[i]);
      }

      // Add the raw transaction message WITHOUT the signature count header
      // The txBytes format is: [numRequiredSignatures] + [message_body]
      // For the final signed transaction, we need: [sigCount] + [signatures] + [message_body]
      // So we skip the first byte (numRequiredSignatures) from txBytes
      final messageBody = txBytes.sublist(
        1,
      ); // Skip the first byte (signature count)
      builder.add(messageBody);

      AppLogger.debug(
        '🔧 Built signed transaction with ${sigCount} signatures, message body: ${messageBody.length} bytes',
      );

      final signedTx = base64Encode(builder.toBytes());

      AppLogger.debug(
        '📡 Sending transaction to Solana...',
        tag: 'WalletProvider',
      );
      final txSignature = await _client.rpcClient.sendTransaction(
        signedTx,
        preflightCommitment: solana.Commitment.confirmed,
      );
      AppLogger.debug(
        '🎉 Transaction sent: $txSignature',
        tag: 'WalletProvider',
      );
      return txSignature;
    } catch (e) {
      AppLogger.debug(
        '❌ Error in signAndSendTransactionWithCosigners: $e',
        tag: 'WalletProvider',
      );
      return null;
    }
  }

  // Encodes an integer using Solana's shortvec format (compact-u16)
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

  /// Initialize wallet for the authenticated user
  Future<void> initializeWallet(BuildContext context) async {
    if (_isInitialized) {
      AppLogger.debug('Wallet already initialized', tag: 'WalletProvider');
      return;
    }

    try {
      setLoading();

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.currentUser == null) {
        throw Exception('User must be authenticated to initialize wallet');
      }

      // Get embedded wallet from auth provider
      await ensureWalletExists(authProvider);

      // Refresh balance
      await refreshBalance();

      _isInitialized = true;
      setSuccess();
      AppLogger.debug('Wallet initialized successfully', tag: 'WalletProvider');
    } catch (e) {
      AppLogger.debug('Error initializing wallet: $e', tag: 'WalletProvider');
      setError('Failed to initialize wallet: $e');
      rethrow;
    }
  }

  /// Ensure wallet exists and is properly configured
  Future<void> ensureWalletExists(AuthProvider authProvider) async {
    try {
      final user = authProvider.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated');
      }

      AppLogger.debug(
        'Setting up wallet for user: ${user.id}',
        tag: 'WalletProvider',
      );

      // Get embedded Solana wallets directly from the user object (new API)
      if (user.embeddedSolanaWallets.isNotEmpty) {
        final embeddedWallet = user.embeddedSolanaWallets.first;
        _embeddedWallet = embeddedWallet;
        _walletAddress = embeddedWallet.address;

        AppLogger.debug(
          '✅ Found embedded Solana wallet: ${embeddedWallet.address}',
          tag: 'WalletProvider',
        );
        AppLogger.debug(
          '✅ Embedded wallet configured for signing',
          tag: 'WalletProvider',
        );
      } else {
        AppLogger.debug(
          '❌ No embedded Solana wallets found on user',
          tag: 'WalletProvider',
        );

        // Try to create a new embedded wallet if none exists
        AppLogger.debug(
          '🔄 Attempting to create new embedded Solana wallet...',
          tag: 'WalletProvider',
        );
        final createResult = await user.createSolanaWallet();

        if (createResult is Success<EmbeddedSolanaWallet>) {
          _embeddedWallet = createResult.value;
          _walletAddress = createResult.value.address;
          AppLogger.debug(
            '✅ Created new embedded Solana wallet: ${_walletAddress}',
            tag: 'WalletProvider',
          );
        } else if (createResult is Failure) {
          AppLogger.debug(
            '❌ Failed to create embedded Solana wallet: ${createResult.toString()}',
          );

          // Fallback to extracting from linked accounts if available
          final solanaWallets = user.linkedAccounts.where(
            (account) => account.type == 'solanaWallet',
          );

          if (solanaWallets.isNotEmpty) {
            final solanaWallet = solanaWallets.first;
            AppLogger.debug(
              'Found Solana wallet in linked accounts: ${solanaWallet.runtimeType}',
            );

            // Try to extract address from linked account
            if (solanaWallet is EmbeddedSolanaWalletAccount) {
              _walletAddress = solanaWallet.address;
              AppLogger.debug(
                '✅ Extracted address from linked account: $_walletAddress',
                tag: 'WalletProvider',
              );
            }
          }
        }
      }

      if (_walletAddress == null) {
        AppLogger.debug(
          '⚠️  Could not extract Solana wallet address',
          tag: 'WalletProvider',
        );
        throw Exception('No Solana wallet found in user account');
      }

      AppLogger.debug(
        'Wallet configured: $_walletAddress',
        tag: 'WalletProvider',
      );
      AppLogger.debug(
        'Embedded wallet available: ${_embeddedWallet != null}',
        tag: 'WalletProvider',
      );

      if (_embeddedWallet == null) {
        AppLogger.debug(
          '⚠️  WARNING: No embedded wallet found - transaction signing will fail',
        );
        AppLogger.debug(
          '   This means Privy wallet integration needs to be completed',
          tag: 'WalletProvider',
        );
      }

      // Initialize EscrowService to use dart-coral-xyz with PrivyWallet
      await _challengeService!.initializeEscrow(
        embeddedWallet: _embeddedWallet!,
        walletAddress: _walletAddress!,
      );
      AppLogger.debug(
        '✅ EscrowService initialized with PrivyWallet',
        tag: 'WalletProvider',
      );
    } catch (e) {
      AppLogger.debug(
        'Error ensuring wallet exists: $e',
        tag: 'WalletProvider',
      );
      rethrow;
    }
  }

  /// Refresh wallet balance
  Future<void> refreshBalance() async {
    if (_walletAddress == null) {
      AppLogger.debug(
        'No wallet address available to refresh balance',
        tag: 'WalletProvider',
      );
      return;
    }

    try {
      final publicKey = solana.Ed25519HDPublicKey.fromBase58(_walletAddress!);
      final balanceResponse = await _client.rpcClient.getBalance(
        publicKey.toBase58(),
      );
      _balance = balanceResponse.value / solana.lamportsPerSol;

      notifyListeners();
      AppLogger.debug(
        'Balance refreshed: $_balance SOL',
        tag: 'WalletProvider',
      );
    } catch (e) {
      AppLogger.debug('Error refreshing balance: $e', tag: 'WalletProvider');
    }
  }

  /// Create a new challenge using EscrowService directly
  Future<Challenge?> createChallenge({
    required String friendEmail,
    required String friendAddress,
    required double amount,
    required String challengeDescription,
    required int durationDays,
    required BuildContext context,
  }) async {
    setLoading();
    try {
      // Ensure we always pass a valid base58 witness address
      String witness = friendAddress.trim();
      if (witness.isEmpty) {
        throw Exception('Friend address is empty');
      }
      // Resolve .sol domains to wallet addresses
      if (witness.toLowerCase().endsWith('.sol')) {
        final resolved = await AddressNameResolver.resolveAddress(witness);
        if (resolved == null) {
          throw Exception('Could not resolve $witness to a wallet address');
        }
        witness = resolved;
      }
      // Validate address format by attempting to parse as a public key
      try {
        // Throws if invalid
        solana.Ed25519HDPublicKey.fromBase58(witness);
      } catch (_) {
        throw Exception('Invalid wallet address provided for friend');
      }

      // Call on-chain via EscrowService (dart-coral-xyz)
      final signature = await _challengeService!.escrowService.createChallenge(
        initiatorAddress: _walletAddress!,
        witnessAddress: witness,
        amountSol: amount,
        durationDays: durationDays,
        description: challengeDescription, // Pass the description
      );
      // Persist challenge in database
      final createdChallenge = await _challengeService!.createChallenge(
        title: 'Challenge with $friendEmail',
        description: challengeDescription,
        amountInSol: amount,
        creatorId:
            Provider.of<AuthProvider>(context, listen: false).currentUser!.id,
        member1Address: _walletAddress!,
        member2Address: witness,
        expiresAt: DateTime.now().add(Duration(days: durationDays)),
        participantEmail: friendEmail,
        transactionSigner: null, // already signed on-chain
      );
      AppLogger.debug(
        '✅ Challenge created on-chain: $signature',
        tag: 'WalletProvider',
      );
      setSuccess();
      await refreshBalance();
      return createdChallenge;
    } catch (e) {
      setError('Failed to create challenge: $e');
      return null;
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
    return ChallengeService.getFeeBreakdown(challengeAmount);
  }

  /// Request airdrop for testing on devnet
  Future<bool> requestAirdrop({double amount = 1.0}) async {
    if (_walletAddress == null) {
      AppLogger.debug(
        'No wallet address available for airdrop',
        tag: 'WalletProvider',
      );
      return false;
    }

    try {
      setLoading();

      final publicKey = solana.Ed25519HDPublicKey.fromBase58(_walletAddress!);
      final lamports = (amount * solana.lamportsPerSol).round();

      // Request airdrop from devnet
      final signature = await _client.rpcClient.requestAirdrop(
        publicKey.toBase58(),
        lamports,
      );

      AppLogger.debug('✅ Airdrop requested: $signature', tag: 'WalletProvider');
      AppLogger.debug('Amount: $amount SOL', tag: 'WalletProvider');

      // Wait a moment then refresh balance
      await Future.delayed(const Duration(seconds: 2));
      await refreshBalance();

      setSuccess();
      return true;
    } catch (e) {
      AppLogger.debug('❌ Error requesting airdrop: $e', tag: 'WalletProvider');
      setError('Failed to request airdrop: $e');
      return false;
    }
  }

  /// Signs a message using the embedded wallet (if supported)
  Future<String?> signMessage(String message) async {
    if (_embeddedWallet == null) {
      AppLogger.debug(
        'No embedded wallet available for signing',
        tag: 'WalletProvider',
      );
      return null;
    }

    try {
      final signatureResult = await _embeddedWallet!.provider.signMessage(
        message,
      );

      if (signatureResult is Success<String>) {
        AppLogger.debug('Message signed successfully', tag: 'WalletProvider');
        return signatureResult.value;
      } else if (signatureResult is Failure) {
        AppLogger.debug(
          'Failed to sign message: ${signatureResult.toString()}',
          tag: 'WalletProvider',
        );
        return null;
      }

      return null;
    } catch (e) {
      AppLogger.debug('Error signing message: $e', tag: 'WalletProvider');
      return null;
    }
  }

  /// Mark challenge as completed with simplified on-chain resolution
  /// Since the user chooses the winner, we just need to transfer funds accordingly
  Future<bool> markChallengeCompleted({
    required String challengeId,
    required bool userWon, // Whether the current user won or the friend won
    required BuildContext context,
  }) async {
    AppLogger.info(
      'WalletProvider.markChallengeCompleted called for challengeId=$challengeId, userWon=$userWon',
    );
    if (_challengeService == null) {
      AppLogger.info(
        'WalletProvider: ChallengeService not initialized',
        tag: 'WalletProvider',
      );
      setError('Challenge service not available');
      return false;
    }

    try {
      AppLogger.info('WalletProvider: setLoading', tag: 'WalletProvider');
      setLoading();

      // Check if wallet is initialized first
      if (_walletAddress == null) {
        AppLogger.info(
          'WalletProvider: Wallet not initialized, attempting to initialize...',
        );

        // Try to initialize wallet first
        try {
          await initializeWallet(context);
        } catch (e) {
          AppLogger.info(
            'WalletProvider: Failed to initialize wallet: $e',
            tag: 'WalletProvider',
          );
          setError('Wallet not available: $e');
          return false;
        }

        if (_walletAddress == null) {
          AppLogger.info(
            'WalletProvider: Wallet still not available after initialization attempt',
          );
          setError('Wallet initialization failed');
          return false;
        }
      }

      // Get current user ID from AuthProvider
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      AppLogger.info(
        'WalletProvider: currentUser = $currentUser',
        tag: 'WalletProvider',
      );

      if (currentUser == null) {
        AppLogger.info(
          'WalletProvider: No authenticated user',
          tag: 'WalletProvider',
        );
        setError('User not authenticated');
        return false;
      }

      // Get the challenge to determine the details
      final challenge = await _challengeService!.getChallengeById(challengeId);
      AppLogger.info(
        'WalletProvider: fetched challenge = $challenge',
        tag: 'WalletProvider',
      );
      if (challenge == null) {
        AppLogger.info(
          'WalletProvider: Challenge not found',
          tag: 'WalletProvider',
        );
        setError('Challenge not found');
        return false;
      }

      // Determine winner ID
      String winnerId;
      if (userWon) {
        winnerId = currentUser.id; // Current user won
      } else {
        // Friend won - use participant ID or email as identifier
        winnerId =
            challenge.participantId ?? challenge.participantEmail ?? 'friend';
      }

      AppLogger.info(
        'WalletProvider: marking challenge as completed (simplified)',
        tag: 'WalletProvider',
      );
      AppLogger.debug('- Challenge ID: $challengeId', tag: 'WalletProvider');
      AppLogger.debug(
        '- Winner: ${userWon ? 'User' : 'Friend'} ($winnerId)',
        tag: 'WalletProvider',
      );
      AppLogger.debug(
        '- Amount: ${challenge.amount} SOL',
        tag: 'WalletProvider',
      );
      AppLogger.debug(
        '- Winner gets: ${challenge.winnerAmount} SOL',
        tag: 'WalletProvider',
      );
      AppLogger.debug(
        '- Platform fee: ${challenge.platformFee} SOL',
        tag: 'WalletProvider',
      );

      // Build and execute the actual on-chain resolution transaction
      AppLogger.info(
        'WalletProvider: building on-chain resolution transaction',
        tag: 'WalletProvider',
      );

      try {
        // Validate required data before proceeding
        if (challenge.escrowAddress == null) {
          throw Exception('Challenge escrow address is null');
        }
        if (_walletAddress == null) {
          throw Exception('Wallet address is null');
        }
        if (challenge.participantEmail == null) {
          throw Exception('Challenge participant email is null');
        }

        AppLogger.info(
          'WalletProvider: All required data available:',
          tag: 'WalletProvider',
        );
        AppLogger.info(
          '  - Challenge escrow address: ${challenge.escrowAddress}',
          tag: 'WalletProvider',
        );
        AppLogger.info(
          '  - Wallet address: $_walletAddress',
          tag: 'WalletProvider',
        );
        AppLogger.info(
          '  - Participant email: ${challenge.participantEmail}',
          tag: 'WalletProvider',
        );

        // Get the escrow service to get challenge info
        final escrowService = _challengeService!.escrowService;

        AppLogger.info(
          'WalletProvider: escrowService found, calling resolveChallenge...',
        );

        // Get challenge address from the escrow service
        final resolveInfo = await escrowService.resolveChallenge(
          challengeAddress: challenge.escrowAddress!,
          initiatorAddress: _walletAddress!,
          witnessAddress: challenge.participantEmail!,
          success: userWon, // use actual outcome
        );

        AppLogger.info(
          'WalletProvider: resolve info = $resolveInfo',
          tag: 'WalletProvider',
        );

        // Resolution sent on-chain; proceed to update database
        // (Removed redundant second on-chain call)

        // Now update the database with the completion
        final dbSuccess = await _challengeService!.updateChallengeStatus(
          challengeId: challengeId,
          status: ChallengeStatus.completed,
        );

        if (dbSuccess) {
          AppLogger.info(
            'WalletProvider: Challenge completed on-chain and in database',
            tag: 'WalletProvider',
          );
          setSuccess();
          await refreshBalance();
          return true;
        } else {
          AppLogger.info(
            'WalletProvider: On-chain success but database update failed',
            tag: 'WalletProvider',
          );
          setError('Challenge completed on-chain but database sync failed');
          return false;
        }
      } catch (onChainError) {
        AppLogger.info(
          'WalletProvider: On-chain resolution failed: $onChainError',
          tag: 'WalletProvider',
        );
        setError('Failed to complete challenge on-chain: $onChainError');
        return false;
      }
    } catch (e) {
      AppLogger.debug(
        '❌ Error marking challenge completed: $e',
        tag: 'WalletProvider',
      );
      setError('Failed to mark challenge completed: $e');
      return false;
    }
  }

  /// Transfer SOL to another wallet address
  Future<String?> transferSol({
    required String destinationAddress,
    required double amount,
    required BuildContext context,
  }) async {
    if (_walletAddress == null || _embeddedWallet == null) {
      AppLogger.debug(
        '❌ Wallet not initialized for transfer',
        tag: 'WalletProvider',
      );
      setError('Wallet not initialized');
      return null;
    }

    try {
      setLoading();
      AppLogger.debug(
        '💸 Starting SOL transfer: ${amount} SOL to $destinationAddress',
        tag: 'WalletProvider',
      );

      // Validate destination address
      try {
        solana.Ed25519HDPublicKey.fromBase58(destinationAddress);
      } catch (_) {
        throw Exception('Invalid destination wallet address');
      }

      // Check if user has enough balance (including transaction fees)
      if (amount >= _balance) {
        throw Exception('Insufficient balance for transfer');
      }

      // Convert amount to lamports using the proper constant
      final lamports = (amount * solana.lamportsPerSol).round();

      AppLogger.debug(
        '💰 Creating SOL transfer: $lamports lamports to $destinationAddress',
        tag: 'WalletProvider',
      );

      // Create actual Solana transaction
      final transactionSignature = await _createAndSendSolanaTransaction(
        destinationAddress: destinationAddress,
        lamports: lamports,
      );

      if (transactionSignature != null) {
        AppLogger.debug(
          '✅ SOL transfer completed successfully with signature: $transactionSignature',
          tag: 'WalletProvider',
        );

        // Update local balance (subtract the transferred amount)
        _balance = (_balance - amount).clamp(0.0, double.infinity);

        // Refresh balance from blockchain
        await refreshBalance();

        notifyListeners();
        setSuccess();
        return transactionSignature;
      } else {
        throw Exception('Transfer failed');
      }
    } catch (e) {
      AppLogger.debug('❌ Error in SOL transfer: $e', tag: 'WalletProvider');
      setError('Transfer failed: $e');
      return null;
    }
  }

  /// Create and send an actual Solana transaction for SOL transfer
  Future<String?> _createAndSendSolanaTransaction({
    required String destinationAddress,
    required int lamports,
  }) async {
    try {
      AppLogger.debug(
        '🔨 Building Solana transaction: $lamports lamports to $destinationAddress',
        tag: 'WalletProvider',
      );

      // Parse source and destination public keys using coral_xyz
      final sourcePublicKey = PublicKey.fromBase58(_walletAddress!);
      final destinationPublicKey = PublicKey.fromBase58(destinationAddress);

      AppLogger.debug('📡 Fetching latest blockhash...', tag: 'WalletProvider');

      // Get latest blockhash using solana client
      final blockhashResponse = await _client.rpcClient.getLatestBlockhash();
      final blockhash = blockhashResponse.value.blockhash;

      AppLogger.debug('✅ Got blockhash: $blockhash', tag: 'WalletProvider');

      // Create transfer instruction using coral_xyz SystemProgram
      final transferInstruction = SystemProgram.transfer(
        fromPubkey: sourcePublicKey,
        toPubkey: destinationPublicKey,
        lamports: lamports,
      );

      // Create the transaction using coral_xyz Transaction
      final transaction = coral_types.Transaction(
        feePayer: sourcePublicKey,
        recentBlockhash: blockhash,
        instructions: [transferInstruction],
      );

      AppLogger.debug(
        '🔐 Signing transaction with Privy wallet...',
        tag: 'WalletProvider',
      );

      // Create PrivyWallet instance for signing
      final privyWallet = PrivyWallet(
        walletAddress: _walletAddress!,
        embeddedWallet: _embeddedWallet!,
      );

      // Sign the transaction
      final signedTransaction = await privyWallet.signTransaction(transaction);

      AppLogger.debug(
        '📡 Broadcasting transaction to network...',
        tag: 'WalletProvider',
      );

      // Serialize the signed transaction
      final serializedTransaction = signedTransaction.serialize();

      // Convert to base64 for RPC client
      final transactionBase64 = base64Encode(serializedTransaction);

      // Send the signed transaction to the network using solana client
      final signature = await _client.rpcClient.sendTransaction(
        transactionBase64,
        preflightCommitment: solana.Commitment.confirmed,
      );

      AppLogger.debug(
        '✅ Transaction sent successfully! Signature: $signature',
        tag: 'WalletProvider',
      );

      // Wait for confirmation
      AppLogger.debug(
        '⏳ Waiting for transaction confirmation...',
        tag: 'WalletProvider',
      );

      // Poll for transaction confirmation
      var confirmed = false;
      var attempts = 0;
      const maxAttempts = 30; // 30 seconds timeout

      while (!confirmed && attempts < maxAttempts) {
        try {
          final statusResponse = await _client.rpcClient.getSignatureStatuses([
            signature,
          ]);
          final status = statusResponse.value.first;

          if (status != null) {
            if (status.err != null) {
              throw Exception('Transaction failed: ${status.err}');
            }

            if (status.confirmationStatus.name == 'confirmed' ||
                status.confirmationStatus.name == 'finalized') {
              confirmed = true;
              break;
            }
          }
        } catch (e) {
          AppLogger.debug(
            'Error checking transaction status: $e',
            tag: 'WalletProvider',
          );
        }

        attempts++;
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!confirmed) {
        AppLogger.debug(
          '⚠️ Transaction timeout, but signature was sent: $signature',
          tag: 'WalletProvider',
        );
        // Return signature even if we couldn't confirm - user can check explorer
      } else {
        AppLogger.debug('🎉 Transaction confirmed!', tag: 'WalletProvider');
      }

      return signature;
    } catch (e) {
      AppLogger.debug(
        '❌ Error creating/sending transaction: $e',
        tag: 'WalletProvider',
      );
      rethrow;
    }
  }

  // Removed _callResolveChallenge helper as resolution is handled directly via EscrowService
}
