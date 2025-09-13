import 'dart:async';
import 'package:flutter/material.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/core/utils/base_change_notifier.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:solana/solana.dart' as solana;
import 'package:privy_flutter/privy_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

/// Optimized wallet provider that prevents multiple initializations
/// and provides efficient wallet management
class OptimizedWalletProvider extends BaseChangeNotifier {
  static OptimizedWalletProvider? _instance;
  static OptimizedWalletProvider get instance =>
      _instance ??= OptimizedWalletProvider._();

  OptimizedWalletProvider._();

  // Initialization state
  bool _isInitialized = false;
  bool _isInitializing = false;
  Completer<void>? _initCompleter;

  // Wallet state
  String? _walletAddress;
  double _balance = 0.0;
  EmbeddedSolanaWallet? _embeddedWallet;

  // Solana client (lazy initialized)
  solana.SolanaClient? _client;

  // Balance refresh state
  Timer? _balanceTimer;
  static const Duration _balanceRefreshInterval = Duration(minutes: 2);

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get walletAddress => _walletAddress;
  double get balance => _balance;
  EmbeddedSolanaWallet? get embeddedWallet => _embeddedWallet;

  String? get displayAddress {
    if (_walletAddress == null) return null;
    if (_walletAddress!.length <= 8) return _walletAddress;
    return '${_walletAddress!.substring(0, 4)}...${_walletAddress!.substring(_walletAddress!.length - 4)}';
  }

  solana.SolanaClient get solanaClient {
    _client ??= solana.SolanaClient(
      rpcUrl: Uri.parse(
        dotenv.env['SOLANA_RPC_URL'] ?? 'https://api.devnet.solana.com',
      ),
      websocketUrl: Uri.parse(
        (dotenv.env['SOLANA_RPC_URL'] ?? 'https://api.devnet.solana.com')
            .replaceFirst('http', 'ws'),
      ),
    );
    return _client!;
  }

  /// Initialize wallet (with deduplication)
  Future<void> initializeWallet(BuildContext? context) async {
    // If already initialized, return immediately
    if (_isInitialized) {
      AppLogger.debug('Wallet already initialized');
      return;
    }

    // If initialization is in progress, wait for it
    if (_isInitializing && _initCompleter != null) {
      AppLogger.debug('Wallet initialization in progress, waiting...');
      return await _initCompleter!.future;
    }

    // Start initialization
    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      AppLogger.info('Starting wallet initialization');

      // Get auth provider from context if available
      AuthProvider? authProvider;
      if (context != null) {
        authProvider = Provider.of<AuthProvider>(context, listen: false);
      }

      // Get user from auth provider if available
      PrivyUser? user = authProvider?.currentUser;
      if (user == null) {
        throw Exception('No authenticated user available');
      }

      AppLogger.debug('Setting up wallet for user: ${user.id}');

      // Look for embedded Solana wallet
      EmbeddedSolanaWallet? solanaWallet;
      for (final account in user.linkedAccounts) {
        if (account is EmbeddedSolanaWallet) {
          solanaWallet = account;
          break;
        }
      }

      if (solanaWallet == null) {
        throw Exception('No embedded Solana wallet found');
      }

      // Store wallet info
      _embeddedWallet = solanaWallet;
      _walletAddress = solanaWallet.address;

      AppLogger.info('✅ Found embedded Solana wallet: $_walletAddress');

      // Initial balance fetch (don't wait for it)
      _refreshBalanceAsync();

      // Start periodic balance updates
      _startBalanceUpdates();

      _isInitialized = true;
      AppLogger.info('✅ Wallet initialized successfully');

      _initCompleter!.complete();
      notifyListeners();
    } catch (e) {
      AppLogger.error('Failed to initialize wallet: $e');
      _initCompleter!.completeError(e);
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  /// Refresh balance without blocking
  void _refreshBalanceAsync() {
    if (_walletAddress == null) return;

    // Don't await this - let it happen in background
    _fetchBalance()
        .then((newBalance) {
          if (newBalance != _balance) {
            _balance = newBalance;
            AppLogger.debug('Balance updated: $newBalance SOL');
            notifyListeners();
          }
        })
        .catchError((e) {
          AppLogger.error('Failed to fetch balance: $e');
        });
  }

  /// Fetch balance from network
  Future<double> _fetchBalance() async {
    try {
      if (_walletAddress == null) return 0.0;

      final balanceResult = await solanaClient.rpcClient.getBalance(
        _walletAddress!,
      );
      final lamports = balanceResult.value;
      return lamports / solana.lamportsPerSol;
    } catch (e) {
      AppLogger.error('Error fetching balance: $e');
      return _balance; // Return current balance on error
    }
  }

  /// Start periodic balance updates
  void _startBalanceUpdates() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(_balanceRefreshInterval, (_) {
      _refreshBalanceAsync();
    });
  }

  /// Stop periodic balance updates
  void _stopBalanceUpdates() {
    _balanceTimer?.cancel();
    _balanceTimer = null;
  }

  /// Reset wallet state (for logout)
  void reset() {
    _stopBalanceUpdates();
    _isInitialized = false;
    _isInitializing = false;
    _initCompleter = null;
    _walletAddress = null;
    _balance = 0.0;
    _embeddedWallet = null;
    _client = null;

    AppLogger.info('Wallet provider reset');
    notifyListeners();
  }

  @override
  void dispose() {
    _stopBalanceUpdates();
    super.dispose();
  }
}
