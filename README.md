# Chumbucket

**Follow the call. Challenge a friend. Let the match settle it.**

Chumbucket is a social prediction product on Solana. It began as a mobile app
for creating challenges with friends and locking SOL until the challenge was
resolved. Arena expands that idea into social football predictions: follow
callers, copy a prediction, challenge a friend, and settle the result from
TxLINE proofs instead of trusting an operator.

The Flutter app connects through Solana Mobile Wallet Adapter and is the native
companion to the [Chumbucket Arena](https://github.com/Immadominion/chumbucket-arena)
web and settlement stack.

## Product

- Create direct challenges with friends and lock SOL in the original mainnet
  Pinocchio escrow.
- Browse TxLINE football fixtures and call HOME, DRAW, or AWAY in Arena.
- Follow people, copy calls, challenge friends, and track settled positions.
- Connect and sign with an MWA-compatible Solana wallet; Chumbucket never
  custodies a user's wallet key.
- Keep profiles, friendships, feeds, notifications, and challenge records in a
  Supabase social read model.
- Resolve Arena pots through Chumbucket's Solana program only after its CPI to
  TxLINE `validate_stat` returns a true result.

The existing friend-challenge protocol is on Solana mainnet. The TxLINE Arena
program and its test USDC-like asset are currently on Solana devnet.

## Verified Usage

Verified on July 18, 2026:

- `185` production profiles, `183` linked wallets, `160` push-notification
  tokens, `48` friend relationships, and `49` challenge records.
- The public mainnet escrow confirms `15` funded challenge creations locking
  `0.19 SOL`, `13` successful resolutions, and `0.00325 SOL` in protocol fees.

Database profiles and funded on-chain challenges are separate measurements; a
profile is not presented as an on-chain bettor.

## Architecture

```text
Flutter app
  |-- Solana Mobile Wallet Adapter: authentication and transaction signatures
  |-- Supabase: profiles, friends, realtime updates, and push notifications
  |-- Pinocchio escrow: original SOL friend challenges on mainnet
  `-- Arena API + Anchor program: TxLINE-settled prediction pots on devnet
```

- Original friend-challenge program:
  [`D6mj...9sF1`](https://explorer.solana.com/address/D6mjMGW1fX8oH3UcwZDh3teWcHEWvghUqaR2aeWD9sF1)
- Arena program:
  [`AMFp...K9CG`](https://explorer.solana.com/address/AMFpYiYPCUwiVbYMkhnaCmnSDv226yew17QXLhVWk9CG?cluster=devnet)
- Verified TxLINE settlement:
  [Argentina 3-2 Egypt](https://explorer.solana.com/tx/553CkpvcpddtBzEmPPxvMJHzJXFS73f2aJ79J5BtrrdAUBrhnrLfKQKikUZcDxzRZwz39JR2FxsJFZzUfAVJrAB8?cluster=devnet)

## Run On Android

Requirements:

- Flutter 3.x with Dart 3.7 or newer
- Android device with an MWA-compatible wallet
- Supabase and Solana RPC configuration

```bash
cp .env.example .env
flutter pub get
flutter run
```

The environment template documents the required Solana, Helius, Arena API, and
Supabase keys. Do not commit the populated `.env` file.

Run the focused test suite with:

```bash
flutter test
```

## Related Work

- Arena backend, web client, keeper, proof receipt, and Solana program:
  [Immadominion/chumbucket-arena](https://github.com/Immadominion/chumbucket-arena)
- Original Pinocchio escrow:
  [ubadineke/chumbucket-escrow](https://github.com/ubadineke/chumbucket-escrow)
- Founder: [@HeIsJoel0x](https://x.com/HeIsJoel0x)

## License

See [LICENSE](LICENSE).
