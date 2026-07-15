import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized network configuration for devnet/mainnet separation
/// This ensures consistent network handling across the app
class NetworkConfig {
  NetworkConfig._();

  /// Available Solana networks
  static const String devnet = 'devnet';
  static const String mainnetBeta = 'mainnet-beta';

  /// Get the current network from environment
  /// Defaults to devnet for development safety
  static String get currentNetwork {
    final network = dotenv.env['SOLANA_NETWORK']?.toLowerCase();
    if (network == 'mainnet-beta' || network == 'mainnet') {
      return mainnetBeta;
    }
    return devnet; // Default to devnet for safety
  }

  /// Check if we're on mainnet
  static bool get isMainnet => currentNetwork == mainnetBeta;

  /// Check if we're on devnet
  static bool get isDevnet => currentNetwork == devnet;

  /// Get the RPC URL for the current network
  static String get rpcUrl {
    // First try network-specific URL from env
    if (isMainnet) {
      final mainnetUrl = dotenv.env['SOLANA_MAINNET_RPC_URL'];
      if (mainnetUrl != null && mainnetUrl.isNotEmpty) {
        return mainnetUrl;
      }
    } else {
      final devnetUrl = dotenv.env['SOLANA_DEVNET_RPC_URL'];
      if (devnetUrl != null && devnetUrl.isNotEmpty) {
        return devnetUrl;
      }
    }

    // Fall back to generic SOLANA_RPC_URL
    final genericUrl = dotenv.env['SOLANA_RPC_URL'];
    if (genericUrl != null && genericUrl.isNotEmpty) {
      return genericUrl;
    }

    // Default URLs
    return isMainnet
        ? 'https://api.mainnet-beta.solana.com'
        : 'https://api.devnet.solana.com';
  }

  /// Get the Solana Explorer URL for a transaction
  static String getExplorerUrl(String signature) {
    final cluster = isMainnet ? '' : '?cluster=devnet';
    return 'https://explorer.solana.com/tx/$signature$cluster';
  }

  /// Get the Solana Explorer URL for an account
  static String getAccountExplorerUrl(String address) {
    final cluster = isMainnet ? '' : '?cluster=devnet';
    return 'https://explorer.solana.com/address/$address$cluster';
  }
}
