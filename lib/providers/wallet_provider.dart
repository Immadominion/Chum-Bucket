import 'package:flutter/material.dart';
import 'package:solana/solana.dart' as solana;
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WalletProvider extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  solana.SolanaClient? _client;
  solana.Ed25519HDKeyPair? _keyPair;
  String? _walletAddress;
  double _balance = 0.0;
  bool _isInitialized = false;

  String? get walletAddress => _walletAddress;
  double get balance => _balance;
  bool get isInitialized => _isInitialized;

  WalletProvider() {
    _initializeWallet();
  }

  Future<void> _initializeWallet() async {
    try {
      // Connect to Solana devnet
      _client = solana.SolanaClient(
        rpcUrl: Uri.parse('https://api.devnet.solana.com'),
        websocketUrl: Uri.parse('wss://api.devnet.solana.com'),
      );

      // Check if wallet exists
      String? mnemonic = await _storage.read(key: 'wallet_mnemonic');

      if (mnemonic == null) {
        // Generate new wallet
        await _createWallet();
      } else {
        // Restore wallet
        await _restoreWallet(mnemonic);
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing wallet: $e');
    }
  }

  Future<void> _createWallet() async {
    final mnemonic = bip39.generateMnemonic();
    await _storage.write(key: 'wallet_mnemonic', value: mnemonic);
    await _restoreWallet(mnemonic);
  }

  Future<void> _restoreWallet(String mnemonic) async {
    _keyPair = await solana.Ed25519HDKeyPair.fromMnemonic(mnemonic);
    _walletAddress = _keyPair!.address;
    await _fetchBalance();
  }

  Future<void> _fetchBalance() async {
    if (_client != null && _walletAddress != null) {
      try {
        final response = await _client!.rpcClient.getBalance(_walletAddress!);
        // Convert lamports to SOL (1 SOL = 1,000,000,000 lamports)
        _balance = response.value / solana.lamportsPerSol;
        notifyListeners();
      } catch (e) {
        debugPrint('Error fetching balance: $e');
      }
    }
  }

  Future<bool> createChallenge({
    required String friendAddress,
    required double amount,
    required String challengeDescription,
    required int durationDays,
  }) async {
    try {
      // In a real implementation, you would create a Solana program transaction
      // This is a placeholder for the actual implementation
      debugPrint('Creating challenge with: $friendAddress for $amount SOL');
      debugPrint('Challenge: $challengeDescription for $durationDays days');

      // Example implementation would involve:
      // 1. Creating a program-derived address (PDA) for the challenge
      // 2. Building a transaction to transfer funds to the PDA
      // 3. Adding challenge metadata to the transaction
      // 4. Signing and sending the transaction

      // For demo purposes, we'll just update UI
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error creating challenge: $e');
      return false;
    }
  }

  Future<void> refreshBalance() async {
    await _fetchBalance();
  }
}
