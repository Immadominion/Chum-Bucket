import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:solana/solana.dart' as solana;
import 'package:solana/base58.dart';
import 'package:privy_flutter/privy_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/base_change_notifier.dart';
import 'package:chumbucket/services/challenge_service.dart';
import 'package:chumbucket/services/multisig_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class WalletProvider extends BaseChangeNotifier
    implements WalletSigningInterface {
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

  WalletProvider() {
    // Initialize ChallengeService
    _challengeService = ChallengeService(
      supabase: Supabase.instance.client,
      solanaClient: _client,
      walletProvider: this,
    );
  }

  /// Signs and sends a transaction using Privy wallet message signing
  @override
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

      // Step 1: Use Privy to sign the transaction message
      // In Solana, transactions are messages that need to be signed
      log('📝 Signing transaction message with Privy wallet...');

      // Convert transaction bytes to base64 string for message signing
      final transactionBase64 = base64Encode(txBytes);

      final signatureResult = await _embeddedWallet!.provider.signMessage(
        transactionBase64,
      );

      if (signatureResult is Success<String>) {
        final signature = signatureResult.value;
        log(
          '✅ Transaction signed successfully with signature: ${signature.substring(0, 8)}...',
        );

        // Step 2: Send the transaction to Solana network
        log('📡 Sending transaction to Solana network...');

        try {
          // Use SolanaClient to send the transaction
          final txSignature = await _client.rpcClient.sendTransaction(
            base64Encode(txBytes),
            preflightCommitment: solana.Commitment.confirmed,
          );

          log('🎉 Transaction sent successfully to network: $txSignature');
          return txSignature;
        } catch (sendError) {
          log('❌ Failed to send transaction to network: $sendError');
          // Return the Privy signature for debugging purposes
          return signature;
        }
      } else if (signatureResult is Failure) {
        log('❌ Failed to sign transaction: ${signatureResult.toString()}');
        return null;
      }

      log('❌ Unknown response type from signMessage');
      return null;
    } catch (e) {
      log('❌ Error in signAndSendTransaction: $e');
      return null;
    }
  }

  // Add other methods here as needed...

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
