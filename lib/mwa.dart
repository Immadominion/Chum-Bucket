/// Chumbucket MWA (Mobile Wallet Adapter) Integration
///
/// This module replaces Privy authentication with native Solana Mobile Wallet Adapter
/// for compatibility with Solana Mobile devices (Saga, Seeker) and MWA-compatible wallets.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │                        Chumbucket App                                │
/// ├─────────────────────────────────────────────────────────────────────┤
/// │  ┌──────────────────┐    ┌──────────────────┐    ┌───────────────┐  │
/// │  │  MwaAuthProvider │───▶│ MwaWalletProvider│───▶│ PinocchioTx   │  │
/// │  │  (Auth + Session)│    │ (Sign + Send)    │    │ (Build Ix)    │  │
/// │  └────────┬─────────┘    └────────┬─────────┘    └───────────────┘  │
/// │           │                       │                                  │
/// │           ▼                       ▼                                  │
/// │  ┌──────────────────────────────────────────────────────────────┐   │
/// │  │               solana_mobile_client (MWA SDK)                  │   │
/// │  └──────────────────────────────────────────────────────────────┘   │
/// │                              │                                       │
/// └──────────────────────────────┼───────────────────────────────────────┘
///                                ▼
/// ┌──────────────────────────────────────────────────────────────────────┐
/// │                    MWA-Compatible Wallet App                          │
/// │              (Phantom, Solflare, Backpack, etc.)                      │
/// └──────────────────────────────────────────────────────────────────────┘
///                                │
///                                ▼
/// ┌──────────────────────────────────────────────────────────────────────┐
/// │                      Solana Network (Devnet/Mainnet)                  │
/// │  ┌─────────────────────────────────────────────────────────────────┐ │
/// │  │ Pinocchio Escrow Program: D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2  │ │
/// │  └─────────────────────────────────────────────────────────────────┘ │
/// └──────────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ### 1. Initialize Auth Provider
/// ```dart
/// final authProvider = MwaAuthProvider();
/// await authProvider.initialize();
/// ```
///
/// ### 2. Connect Wallet
/// ```dart
/// // Check if wallet is available
/// if (await authProvider.isWalletAvailable()) {
///   // Authorize - opens wallet app for user approval
///   final success = await authProvider.authorize();
///   if (success) {
///     print('Connected: ${authProvider.walletAddress}');
///   }
/// }
/// ```
///
/// ### 3. Create Challenge
/// ```dart
/// final walletProvider = MwaWalletProvider();
/// await walletProvider.initializeFromAuth(authProvider);
///
/// final challenge = await walletProvider.createChallenge(
///   friendEmail: 'friend@example.com',
///   friendAddress: 'FriendWalletAddress...',
///   amount: 1.0, // 1 SOL
///   challengeDescription: 'Complete 10 pushups',
///   durationDays: 30,
///   context: context,
/// );
/// ```
///
/// ### 4. Sign Transactions
/// ```dart
/// // MWA handles all signing through the wallet app
/// // User approves each transaction in their wallet
/// final signingSession = await authProvider.createSigningSession();
/// try {
///   final result = await signingSession.signAndSendTransactions(
///     transactions: [txBytes],
///   );
///   print('Signature: ${result.signatures.first}');
/// } finally {
///   await signingSession.close();
/// }
/// ```
///
/// ## Key Differences from Privy
///
/// | Privy | MWA |
/// |-------|-----|
/// | Email-based auth | Wallet-based auth |
/// | Embedded wallet | External wallet app |
/// | privy_id as user ID | wallet_address as user ID |
/// | Server-side key custody | User controls keys |
/// | Works everywhere | Android only (currently) |
///
/// ## Files
///
/// - `mwa_auth_provider.dart` - Authentication and session management
/// - `mwa_wallet_provider.dart` - Transaction building and signing
/// - `pinocchio_escrow_service.dart` - On-chain data parsing
/// - `mwa_challenge_service.dart` - Database operations with wallet-based identity

library chumbucket_mwa;

// Auth
export 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';

// Wallet
export 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';

// Escrow
export 'package:chumbucket/shared/services/pinocchio_escrow_service.dart';

// Challenge Service
export 'package:chumbucket/features/challenges/data/mwa_challenge_service.dart';
