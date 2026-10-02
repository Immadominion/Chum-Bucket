import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized network configuration for devnet/mainnet separation
/// This ensures consistent network handling across the app
class NetworkConfig {
  NetworkConfig._();

  /// Available Solana networks
  static const String devnet = 'devnet';
  static const String mainnetBeta = 'mainnet-beta';

  /// The network for a `SOLANA_NETWORK` value.
  ///
  /// An explicit value always wins. With none, a **release** build is on
  /// mainnet: that is where the product's money moves (Panta positions settle
  /// in mainnet USDC), and a release that silently showed a devnet balance next
  /// to a mainnet trade is exactly the B10 defect. Debug and profile builds
  /// with no value stay on devnet, so a developer never touches mainnet by
  /// accident. `scripts/build_release.sh` additionally refuses any release
  /// whose configuration does not name mainnet.
  static String resolve(String? raw, {bool releaseMode = kReleaseMode}) {
    final network = raw?.trim().toLowerCase();
    if (network == 'mainnet-beta' || network == 'mainnet') {
      return mainnetBeta;
    }
    if (network == devnet) return devnet;
    return releaseMode ? mainnetBeta : devnet;
  }

  /// The current network, from `SOLANA_NETWORK` (see [resolve]).
  static String get currentNetwork {
    final raw = dotenv.isInitialized ? dotenv.env['SOLANA_NETWORK'] : null;
    return resolve(raw);
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
