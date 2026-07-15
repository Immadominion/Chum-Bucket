# Phase 2: Flutter App Migration to MWA

## Overview

This document describes the migration from Privy-based authentication to Mobile Wallet Adapter (MWA) for Solana Mobile compatibility.

## Migration Status

- [x] Added `solana_mobile_client` dependency (replaces `privy_flutter`)
- [x] Created `MwaAuthProvider` for wallet-based authentication
- [x] Created `MwaWalletProvider` for transaction signing
- [x] Created `PinocchioEscrowService` for on-chain data parsing
- [x] Created `MwaChallengeService` with wallet-based identity
- [x] Created database migration for `wallet_address` support
- [x] Updated program ID to Pinocchio: `D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1`

## Architecture

### Before (Privy)

```
User → Email OTP → Privy → Embedded Wallet → Sign Transaction
                    ↓
              privy_id (user identifier)
```

### After (MWA)

```
User → Wallet App → MWA Protocol → Sign Transaction
                      ↓
              wallet_address (user identifier)
```

## New Files

| File | Description |
|------|-------------|
| `lib/features/authentication/providers/mwa_auth_provider.dart` | MWA authentication and session management |
| `lib/features/wallet/providers/mwa_wallet_provider.dart` | Transaction building and MWA signing |
| `lib/shared/services/pinocchio_escrow_service.dart` | Parse on-chain challenge data |
| `lib/features/challenges/data/mwa_challenge_service.dart` | Challenge service using wallet_address |
| `database_migrations/002_mwa_wallet_auth.sql` | Database schema updates |
| `lib/mwa.dart` | Exports and documentation |

## Pinocchio Program Integration

The app now integrates directly with the Pinocchio program (Phase 1):

**Program ID:** `D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1`

### Instructions

| Discriminator | Instruction | Description |
|---------------|-------------|-------------|
| `0x01` | `create_challenge` | Create new challenge escrow |
| `0x02` | `resolve_challenge` | Witness resolves challenge |
| `0x03` | `cancel_challenge` | Initiator cancels before deadline |

### Challenge Account Layout (146 bytes)

```
[0-8]     discriminator ("CHALL001")
[8-40]    initiator (Pubkey)
[40-72]   witness (Pubkey)
[72-104]  platform (Pubkey)
[104-112] amount (u64)
[112-120] original_amount (u64)
[120-128] platform_fee (u64)
[128-136] deadline (i64)
[136]     is_resolved (bool)
[137]     is_success (bool)
[138]     is_cancelled (bool)
[139-146] padding
```

## Usage

### 1. Initialize Providers

```dart
// In your app initialization
final authProvider = MwaAuthProvider();
await authProvider.initialize();

final walletProvider = MwaWalletProvider();
if (authProvider.isAuthenticated) {
  await walletProvider.initializeFromAuth(authProvider);
}
```

### 2. Connect Wallet

```dart
// Check availability and authorize
if (await authProvider.isWalletAvailable()) {
  final success = await authProvider.authorize();
  // Wallet app opens for user approval
  if (success) {
    print('Connected: ${authProvider.walletAddress}');
  }
}
```

### 3. Create Challenge

```dart
final challenge = await walletProvider.createChallenge(
  friendEmail: 'friend@example.com',
  friendAddress: 'FriendWallet...',
  amount: 1.0,
  challengeDescription: 'Run 5km every day',
  durationDays: 30,
  context: context,
);
```

### 4. Resolve Challenge (Witness)

```dart
final signature = await walletProvider.resolveChallenge(
  challengeAddress: challenge.escrowAddress,
  initiatorAddress: challenge.member1Address,
  success: true, // User completed the challenge
  context: context,
);
```

## Database Migration

Run the SQL migration to add wallet-based authentication:

```bash
psql -d your_database -f database_migrations/002_mwa_wallet_auth.sql
```

Or via Supabase dashboard:

1. Go to SQL Editor
2. Paste contents of `002_mwa_wallet_auth.sql`
3. Run

## Testing

### On Android Emulator

1. Install a MWA-compatible wallet (Phantom, Solflare)
2. Create/import a wallet
3. Run the app
4. Test wallet connection flow

### On Solana Mobile Device (Saga/Seeker)

The app should automatically detect the device wallet.

## Remaining Tasks

- [x] Update UI screens to use MwaAuthProvider
- [x] Update challenge list to use MwaChallengeService
- [x] Add wallet connection button to login screen
- [ ] Test full flow on Android device
- [ ] Add iOS fallback (deep link or web3auth)
- [ ] Execute database migration on Supabase
- [ ] Clean up legacy Privy code after testing

## Completed UI Updates

| Screen | Changes |
|--------|---------|
| `main.dart` | Uses MwaAuthProvider and MwaWalletProvider |
| `mwa_splash_screen.dart` | New splash with MWA auth check |
| `mwa_login_screen.dart` | New wallet-based login screen |
| `mwa_connect_button.dart` | New wallet connect button widget |
| `onboarding_buttons.dart` | Navigates to MwaLoginScreen |
| `profile_screen.dart` | Uses MwaAuthProvider |
| `profile_header.dart` | Uses MwaAuthProvider |
| `profile_wallet_card.dart` | Uses MwaWalletProvider |
| `settings_bottom_sheet.dart` | Disconnect wallet, uses MWA providers |
| `wallet_modal.dart` | Uses MwaWalletProvider |
| `send_sol_sheet.dart` | Uses MwaWalletProvider |
| `edit_profile_screen.dart` | Uses MwaAuthProvider |
| `create_challenge_screens.dart` | Uses MwaWalletProvider |

## Compatibility Notes

### MWA Limitations

- **Android only** - MWA is not available on iOS
- **Chrome on Android** - Works with wallet adapter react (web)
- **Requires wallet app** - User must have Phantom/Solflare/etc installed

### Fallback Options for iOS

1. **WalletConnect** - Cross-platform wallet connection
2. **Web3Auth** - Social login with MPC wallets
3. **Deep Links** - Direct wallet app integration

## References

- [Solana Mobile Stack](https://docs.solanamobile.com/)
- [solana_mobile_client](https://github.com/nicksanchezdev/solana_mobile_client) (Espresso Cash)
- [Pinocchio Program](../chumbucket-pinocchio/README.md)
