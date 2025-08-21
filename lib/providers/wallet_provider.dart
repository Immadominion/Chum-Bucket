import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:solana/solana.dart' as solana;
import 'package:privy_flutter/privy_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/base_change_notifier.dart';
import 'package:chumbucket/services/challenge_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WalletProvider extends BaseChangeNotifier {
  final solana.SolanaClient _client = solana.SolanaClient(
    rpcUrl: Uri.parse(
      dotenv.env['SOLANA_RPC_URL'] ?? 'https://api.devnet.solana.com',
    ),
    websocketUrl: Uri.parse(
      dotenv.env['SOLANA_WS_URL'] ?? 'wss://api.devnet.solana.com',
    ),
  );

  String? _walletAddress;
  double _balance = 0.0;
  bool _isInitialized = false;
  EmbeddedSolanaWallet? _embeddedWallet;
  ChallengeService? _challengeService;

  String? get walletAddress => _walletAddress;
  double get balance => _balance;
  bool get isInitialized => _isInitialized;
  EmbeddedSolanaWallet? get embeddedWallet => _embeddedWallet;
  ChallengeService? get challengeService => _challengeService;

  /// Get formatted display address (first 4 + last 4 characters)
  String? get displayAddress {
    if (_walletAddress == null) return null;
    if (_walletAddress!.length <= 8) return _walletAddress;
    return '${_walletAddress!.substring(0, 4)}...${_walletAddress!.substring(_walletAddress!.length - 4)}';
  }

  WalletProvider() {
    // Initialize ChallengeService
    _challengeService = ChallengeService(
      supabase: Supabase.instance.client,
      solanaClient: _client,
    );
  }

  /// Signs and sends a transaction using Privy wallet message signing
  Future<String?> signAndSendTransaction(List<int> transactionBytes) async {
    if (_embeddedWallet == null) {
      log('No embedded wallet available for signing and sending transaction');
      return null;
    }

    if (_walletAddress == null) {
      log('No wallet address available for transaction signing');
      return null;
    }

    try {
      log('🔑 Signing and sending transaction with Privy wallet');
      log('Transaction size: ${transactionBytes.length} bytes');

      // Convert transaction bytes to Uint8List for processing
      final txBytes = Uint8List.fromList(transactionBytes);

      // Extract the number of required signatures from the message header (legacy format)
      // Message header layout: [numRequiredSignatures, numReadonlySigned, numReadonlyUnsigned, ...]
      if (txBytes.isEmpty) {
        log('❌ Transaction bytes are empty');
        return null;
      }
      final numRequiredSignatures = txBytes[0];
      log(
        'Message header indicates $numRequiredSignatures required signature(s)',
      );

      if (numRequiredSignatures == 0) {
        log('❌ Invalid message: requires 0 signatures');
        return null;
      }

      // Step 1: Use Privy to sign the transaction message (compiled message bytes)
      log('📝 Signing transaction message with Privy wallet...');

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
          log('❌ Could not decode signature from base64: $e');
          return null;
        }

        log(
          '✅ Message signed. Signature length: ${signatureBytes.length} bytes',
        );

        if (signatureBytes.length != 64) {
          log(
            '❌ Invalid signature length: ${signatureBytes.length}. Expected 64 bytes',
          );
          return null;
        }

        if (numRequiredSignatures > 1) {
          // Transaction requires multiple signatures, but only one is available
          log(
            '❌ Message requires $numRequiredSignatures signatures, but only one signature is available',
          );
          log(
            '   This transaction cannot be sent without all required signatures',
          );
          return null;
        }

        // Step 2: Construct the legacy transaction wire format:
        // tx = shortvec(num signatures) || signatures (each 64 bytes) || compiled message bytes
        log('🔧 Constructing signed transaction bytes (legacy wire format)...');

        final builder = BytesBuilder();
        builder.add(_shortVecEncode(1)); // one signature
        builder.add(signatureBytes);
        builder.add(txBytes);

        final signedTxBytes = builder.toBytes();
        final signedTxBase64 = base64Encode(signedTxBytes);
        log('Constructed signed tx length: ${signedTxBytes.length} bytes');

        // Step 3: Send the signed transaction to Solana network
        log('📡 Sending signed transaction to Solana network...');
        try {
          final txSignature = await _client.rpcClient.sendTransaction(
            signedTxBase64,
            preflightCommitment: solana.Commitment.confirmed,
          );

          log('🎉 Transaction sent: $txSignature');
          log(
            '🔗 Explorer: https://explorer.solana.com/tx/$txSignature?cluster=devnet',
          );
          return txSignature;
        } catch (sendError) {
          log('❌ Failed to send signed transaction: $sendError');
          return null;
        }
      } else if (signatureResult is Failure) {
        log(
          '❌ Failed to sign message with Privy: ${signatureResult.toString()}',
        );
        return null;
      }

      log('❌ Unknown response type from signMessage');
      return null;
    } catch (e) {
      log('❌ Error in signAndSendTransaction: $e');
      return null;
    }
  }

  /// Signs and sends a transaction with cosigners: Privy wallet first, then local cosigners
  Future<String?> signAndSendTransactionWithCosigners({
    required List<int> transactionBytes,
    required List<solana.Ed25519HDKeyPair> cosigners,
  }) async {
    if (_embeddedWallet == null) {
      log('No embedded wallet available for signing and sending transaction');
      return null;
    }

    try {
      final txBytes = Uint8List.fromList(transactionBytes);
      if (txBytes.isEmpty) return null;
      final numRequiredSignatures = txBytes[0];
      log(
        'Message requires $numRequiredSignatures signatures. Cosigners provided: ${cosigners.length}',
      );

      // First signature from Privy embedded wallet (fee payer)
      final transactionBase64 = base64Encode(txBytes);
      final signatureResult = await _embeddedWallet!.provider.signMessage(
        transactionBase64,
      );
      if (signatureResult is! Success<String>) {
        log('❌ Privy signing failed');
        return null;
      }
      final feePayerSig = base64Decode(signatureResult.value);
      if (feePayerSig.length != 64) {
        log('❌ Invalid fee payer signature length');
        return null;
      }

      // Cosigner signatures (local, deterministic createKey etc.)
      final coSigs = <Uint8List>[];
      for (final kp in cosigners) {
        final sig = await kp.sign(txBytes);
        coSigs.add(Uint8List.fromList(sig.bytes));
      }

      if (1 + coSigs.length < numRequiredSignatures) {
        log(
          '❌ Not enough signatures. Needed: $numRequiredSignatures, have: ${1 + coSigs.length}',
        );
        return null;
      }

      // Construct signed transaction: shortvec(count) || sigs (fee payer first) || message
      final builder = BytesBuilder();
      final sigCount = numRequiredSignatures; // send exactly the required count
      builder.add(_shortVecEncode(sigCount));
      builder.add(feePayerSig);

      for (var i = 0; i < sigCount - 1; i++) {
        builder.add(coSigs[i]);
      }

      builder.add(txBytes);

      final signedTx = base64Encode(builder.toBytes());
      final txSignature = await _client.rpcClient.sendTransaction(
        signedTx,
        preflightCommitment: solana.Commitment.confirmed,
      );
      log('🎉 Transaction sent: $txSignature');
      return txSignature;
    } catch (e) {
      log('❌ Error in signAndSendTransactionWithCosigners: $e');
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

  // Add other methods here as needed...

  /// Initialize wallet for the authenticated user
  Future<void> initializeWallet(BuildContext context) async {
    if (_isInitialized) {
      log('Wallet already initialized');
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
      log('Wallet initialized successfully');
    } catch (e) {
      log('Error initializing wallet: $e');
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

      log('Setting up wallet for user: ${user.id}');

      // Get embedded Solana wallets directly from the user object (new API)
      if (user.embeddedSolanaWallets.isNotEmpty) {
        final embeddedWallet = user.embeddedSolanaWallets.first;
        _embeddedWallet = embeddedWallet;
        _walletAddress = embeddedWallet.address;

        log('✅ Found embedded Solana wallet: ${embeddedWallet.address}');
        log('✅ Embedded wallet configured for signing');
      } else {
        log('❌ No embedded Solana wallets found on user');

        // Try to create a new embedded wallet if none exists
        log('🔄 Attempting to create new embedded Solana wallet...');
        final createResult = await user.createSolanaWallet();

        if (createResult is Success<EmbeddedSolanaWallet>) {
          _embeddedWallet = createResult.value;
          _walletAddress = createResult.value.address;
          log('✅ Created new embedded Solana wallet: ${_walletAddress}');
        } else if (createResult is Failure) {
          log(
            '❌ Failed to create embedded Solana wallet: ${createResult.toString()}',
          );

          // Fallback to extracting from linked accounts if available
          final solanaWallets = user.linkedAccounts.where(
            (account) => account.type == 'solanaWallet',
          );

          if (solanaWallets.isNotEmpty) {
            final solanaWallet = solanaWallets.first;
            log(
              'Found Solana wallet in linked accounts: ${solanaWallet.runtimeType}',
            );

            // Try to extract address from linked account
            if (solanaWallet is EmbeddedSolanaWalletAccount) {
              _walletAddress = solanaWallet.address;
              log('✅ Extracted address from linked account: $_walletAddress');
            }
          }
        }
      }

      if (_walletAddress == null) {
        log('⚠️  Could not extract Solana wallet address');
        throw Exception('No Solana wallet found in user account');
      }

      log('Wallet configured: $_walletAddress');
      log('Embedded wallet available: ${_embeddedWallet != null}');

      if (_embeddedWallet == null) {
        log(
          '⚠️  WARNING: No embedded wallet found - transaction signing will fail',
        );
        log('   This means Privy wallet integration needs to be completed');
      }
    } catch (e) {
      log('Error ensuring wallet exists: $e');
      rethrow;
    }
  }

  /// Refresh wallet balance
  Future<void> refreshBalance() async {
    if (_walletAddress == null) {
      log('No wallet address available to refresh balance');
      return;
    }

    try {
      final publicKey = solana.Ed25519HDPublicKey.fromBase58(_walletAddress!);
      final balanceResponse = await _client.rpcClient.getBalance(
        publicKey.toBase58(),
      );
      _balance = balanceResponse.value / solana.lamportsPerSol;

      notifyListeners();
      log('Balance refreshed: $_balance SOL');
    } catch (e) {
      log('Error refreshing balance: $e');
    }
  }

  /// Create a new challenge
  Future<bool> createChallenge({
    required String friendEmail,
    required String friendAddress,
    required double amount,
    required String challengeDescription,
    required int durationDays,
  }) async {
    if (_challengeService == null) {
      log('Challenge service not initialized');
      setError('Challenge service not available');
      return false;
    }

    if (_walletAddress == null) {
      log('Wallet not initialized for challenge creation');
      setError('Wallet not initialized');
      return false;
    }

    try {
      setLoading();

      log('Creating challenge:');
      log('- Friend: $friendEmail');
      log('- Amount: $amount SOL');
      log('- Description: $challengeDescription');
      log('- Duration: $durationDays days');

      final challenge = await _challengeService!.createChallenge(
        title: 'Challenge with $friendEmail',
        description: challengeDescription,
        amountInSol: amount,
        creatorId:
            _walletAddress!, // Using wallet address as creator ID for now
        member1Address: _walletAddress!,
        member2Address: friendAddress,
        expiresAt: DateTime.now().add(Duration(days: durationDays)),
        participantEmail: friendEmail,
        transactionSigner: (transactionBytes, challengeKeypair) async {
          // Sign and send the transaction using the embedded wallet with cosigners
          log(
            '🔑 Wallet provider signing challenge transaction with cosigners...',
          );
          final signature = await signAndSendTransactionWithCosigners(
            transactionBytes: transactionBytes,
            cosigners: [challengeKeypair],
          );
          if (signature == null) {
            throw Exception('Failed to sign and send challenge transaction');
          }
          log('✅ Transaction signed and sent: $signature');
          return signature;
        },
      );

      setSuccess();
      log('✅ Challenge created successfully: ${challenge.id}');
      log('- Escrow Address: ${challenge.multisigAddress}');
      log('- Vault: ${challenge.vaultAddress}');
      log('- Platform Fee: ${challenge.platformFee} SOL');
      log('- Winner Amount: ${challenge.winnerAmount} SOL');

      return true;
    } catch (e) {
      log('❌ Error creating challenge: $e');
      setError('Failed to create challenge: $e');
      return false;
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
      log('No wallet address available for airdrop');
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

      log('✅ Airdrop requested: $signature');
      log('Amount: $amount SOL');

      // Wait a moment then refresh balance
      await Future.delayed(const Duration(seconds: 2));
      await refreshBalance();

      setSuccess();
      return true;
    } catch (e) {
      log('❌ Error requesting airdrop: $e');
      setError('Failed to request airdrop: $e');
      return false;
    }
  }

  /// Signs a message using the embedded wallet (if supported)
  Future<String?> signMessage(String message) async {
    if (_embeddedWallet == null) {
      log('No embedded wallet available for signing');
      return null;
    }

    try {
      final signatureResult = await _embeddedWallet!.provider.signMessage(
        message,
      );

      if (signatureResult is Success<String>) {
        log('Message signed successfully');
        return signatureResult.value;
      } else if (signatureResult is Failure) {
        log('Failed to sign message: ${signatureResult.toString()}');
        return null;
      }

      return null;
    } catch (e) {
      log('Error signing message: $e');
      return null;
    }
  }
}
