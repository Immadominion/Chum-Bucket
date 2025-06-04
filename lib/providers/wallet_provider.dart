import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:solana/solana.dart' as solana;
import 'package:privy_flutter/privy_flutter.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/base_change_notifier.dart';

class WalletProvider extends BaseChangeNotifier {
  final solana.SolanaClient _client = solana.SolanaClient(
    rpcUrl: Uri.parse('https://api.devnet.solana.com'),
    websocketUrl: Uri.parse('wss://api.devnet.solana.com'),
  );

  String? _walletAddress;
  double _balance = 0.0;
  bool _isInitialized = false;
  EmbeddedSolanaWallet? _embeddedWallet;

  String? get walletAddress => _walletAddress;
  double get balance => _balance;
  bool get isInitialized => _isInitialized;
  EmbeddedSolanaWallet? get embeddedWallet => _embeddedWallet;

  WalletProvider() {
    // Initialization will be triggered when needed
  }

  /// Initializes the wallet by fetching the Privy embedded wallet for the current user.
  Future<void> initializeWallet(BuildContext context) async {
    if (_isInitialized) {
      log('WalletProvider already initialized, skipping...');
      return;
    }

    return runAsync(() async {
      try {
        // First check for internet connection
        if (!await hasInternetConnection()) {
          log('No internet connection available, cannot initialize wallet');
          setError(
            "No internet connection. Please check your network and try again.",
          );
          return;
        }

        final authProvider = Provider.of<AuthProvider>(context, listen: false);

        // Make sure auth provider is fully initialized
        if (!authProvider.isInitialized) {
          log('AuthProvider not initialized yet, initializing it first');
          await authProvider.initialize();
        }

        final privyUser = authProvider.currentUser;

        if (privyUser == null) {
          log('No authenticated user found, cannot initialize wallet');
          return;
        }

        // Get embedded Solana wallets from the user
        final embeddedSolanaWallets = privyUser.embeddedSolanaWallets;

        if (embeddedSolanaWallets.isNotEmpty) {
          // Use the first Solana wallet
          _embeddedWallet = embeddedSolanaWallets.first;

          _walletAddress = _embeddedWallet!.address;
          log('Fetched embedded Solana wallet address: $_walletAddress');

          await _fetchBalance();
          _isInitialized = true;
        } else {
          log('No embedded Solana wallet found for user ${privyUser.id}');
          // Try to create/access wallet through Privy's wallet methods
          await _tryAccessPrivyWallet(authProvider);
        }
      } catch (e) {
        log('Error initializing wallet: $e');
        rethrow;
      }
    }, resetToIdle: false);
  }

  /// Attempts to access Privy wallet through the SDK
  Future<void> _tryAccessPrivyWallet(AuthProvider authProvider) async {
    try {
      // Access the Privy instance to get wallet info
      final privyUser = authProvider.currentUser;
      if (privyUser != null) {
        // No Solana wallet found, attempt to create one
        log('No embedded Solana wallet found, attempting to create one');

        // Create a new Solana wallet using Privy SDK
        final result = await privyUser.createSolanaWallet();

        // Check the result type and handle accordingly
        if (result is Success<EmbeddedSolanaWallet>) {
          _embeddedWallet = result.value;
          _walletAddress = _embeddedWallet!.address;
          log('Created new embedded Solana wallet: $_walletAddress');
          await _fetchBalance();
          _isInitialized = true;
        } else if (result is Failure) {
          log('Failed to create Solana wallet');
        }
      }
    } catch (e) {
      log('Error accessing Privy wallet: $e');
    }
  }

  /// Fetches the balance for the wallet address.
  Future<void> _fetchBalance() async {
    if (_walletAddress != null) {
      try {
        // Check for internet connection first
        if (!await hasInternetConnection()) {
          log('No internet connection available, cannot fetch balance');
          // Don't update balance if we can't connect
          return;
        }

        final response = await _client.rpcClient.getBalance(_walletAddress!);
        // Convert lamports to SOL (1 SOL = 1,000,000,000 lamports)
        _balance = response.value / solana.lamportsPerSol;
        log('Fetched balance: $_balance SOL');
        notifyListeners();
      } catch (e) {
        log('Error fetching balance: $e');
        // Set balance to 0 if there's an error (might be a new wallet)
        _balance = 0.0;
        notifyListeners();
      }
    }
  }

  /// Signs a message using the embedded wallet (if supported)
  Future<String?> signMessage(String message) async {
    if (_embeddedWallet == null) {
      log('No embedded wallet available for signing');
      return null;
    }

    try {
      // Use the correct method from Privy SDK to sign a message with Solana wallet
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

  /// Creates a Solana transaction (placeholder implementation)
  Future<bool> createChallenge({
    required String friendAddress,
    required double amount,
    required String challengeDescription,
    required int durationDays,
  }) async {
    if (_walletAddress == null) {
      log('No wallet address available for creating challenge');
      return false;
    }

    return runAsync(() async {
      try {
        // First check for internet connection
        if (!await hasInternetConnection()) {
          log('No internet connection available, cannot create challenge');
          setError(
            "No internet connection. Please check your network and try again.",
          );
          return false;
        }

        log('Creating challenge with: $friendAddress for $amount SOL');
        log('Challenge: $challengeDescription for $durationDays days');

        // Placeholder for Solana program interaction
        // You'll need to implement the actual Solana program calls here

        // Example steps:
        // 1. Create a PDA for the challenge
        // 2. Build transaction
        // 3. Sign with embedded wallet
        // 4. Send transaction

        // For now, simulate success
        await Future.delayed(const Duration(seconds: 1));
        return true;
      } catch (e) {
        log('Error creating challenge: $e');
        return false;
      }
    }, resetToIdle: true);
  }

  /// Request an airdrop of SOL to the wallet (only works on devnet/testnet)
  Future<bool> requestAirdrop({double amount = 1.0}) async {
    if (_walletAddress == null) {
      log('No wallet address available for airdrop');
      return false;
    }

    return runAsync(() async {
      try {
        setLoading();

        // Check for internet connection first
        if (!await hasInternetConnection()) {
          log('No internet connection available, cannot request airdrop');
          setError(
            "No internet connection. Please check your network and try again.",
          );
          return false;
        }

        // Convert SOL to lamports (1 SOL = 1,000,000,000 lamports)
        final lamports = (amount * solana.lamportsPerSol).toInt();

        log('Requesting airdrop of $amount SOL to $_walletAddress');

        try {
          // Create a public key from the wallet address
          final publicKey = solana.Ed25519HDPublicKey.fromBase58(
            _walletAddress!,
          );

          // Request the airdrop
          final result = await _client.rpcClient.requestAirdrop(
            publicKey.toBase58(), // Convert back to string format for the API
            lamports,
          );

          log('Airdrop requested with signature: ${result.toString()}');

          // Wait a moment for the transaction to be confirmed
          await Future.delayed(const Duration(seconds: 5));

          // Refresh balance after airdrop
          await _fetchBalance();

          setSuccess();
          return true;
        } catch (specificError) {
          log('Specific airdrop error: $specificError');
          throw specificError;
        }
      } catch (e) {
        log('Error requesting airdrop: $e');
        setError("Failed to request airdrop: ${e.toString()}");
        return false;
      }
    }, resetToIdle: true);
  }

  /// Public method to fetch balance
  Future<void> refreshBalance() async {
    if (_isInitialized) {
      await _fetchBalance();
    } else {
      log('Wallet not initialized, cannot refresh balance');
    }
  }

  /// Clears wallet data on logout.
  @override
  Future<void> clearUserData() async {
    _embeddedWallet = null;
    _walletAddress = null;
    _balance = 0.0;
    _isInitialized = false;
    await super.clearUserData();
  }

  /// Ensures the user has a wallet after authentication
  /// Can be called directly after login/signup
  Future<void> ensureWalletExists(AuthProvider authProvider) async {
    if (_isInitialized) return;

    try {
      // First check for internet connection
      if (!await hasInternetConnection()) {
        log('No internet connection available, cannot initialize wallet');
        return;
      }

      final privyUser = authProvider.currentUser;
      if (privyUser == null) {
        log('No authenticated user found, cannot initialize wallet');
        return;
      }

      // First try to get existing wallets
      if (privyUser.embeddedSolanaWallets.isNotEmpty) {
        // Use the first Solana wallet
        _embeddedWallet = privyUser.embeddedSolanaWallets.first;
        _walletAddress = _embeddedWallet!.address;
        log('Found existing embedded Solana wallet: $_walletAddress');
      } else {
        // No Solana wallet found, create one
        log('No embedded Solana wallet found, creating one');
        final result = await privyUser.createSolanaWallet();

        if (result is Success<EmbeddedSolanaWallet>) {
          _embeddedWallet = result.value;
          _walletAddress = _embeddedWallet!.address;
          log('Created new embedded Solana wallet: $_walletAddress');
        } else if (result is Failure) {
          log('Failed to create Solana wallet: ${result.toString()}');
          return;
        }
      }

      // Fetch initial balance
      await _fetchBalance();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      log('Error ensuring wallet exists: $e');
    }
  }

  /// Returns a shortened version of the wallet address for display
  String get displayAddress {
    if (_walletAddress == null) return 'Loading...';
    if (_walletAddress!.length <= 12) return _walletAddress!;

    return '${_walletAddress!.substring(0, 6)}...${_walletAddress!.substring(_walletAddress!.length - 6)}';
  }
}
