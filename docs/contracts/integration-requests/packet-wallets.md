# Integration request — Packet Wallets (every money path, both wallet kinds)

**Raised:** 3 October 2026 · **Packet:** fleet/wallets (mobile from `13f7344`,
API from `205490a`) · **Owner to apply:** integration

Every money path now works for a wallet app (Mobile Wallet Adapter) **and**
for the wallet that lives on the phone, with one rule everywhere: a connected
wallet app first, else the account's linked on-phone wallet
(`choosePantaSigner`'s order). A card-only person can reach a first trade:
Add funds (USDC) → "Get SOL for fees" (a gasless Jupiter swap of about $1 of
their own USDC) → trade.

Research, rules and owner actions for the swap: API repo
`docs/gasless-sol-topup.md`.

## 1. What changed in the app

| Area | Change |
| --- | --- |
| Add funds | `depositWalletSourceOf` returns a `DeviceDepositWalletSource` for the linked on-phone wallet (packet-deposits §2). The on-phone wallet sheet has **Add funds**, its mainnet USDC/SOL and **SOL for fees**. |
| Trades | Unchanged route: `call_detail_screen` already used `choosePantaSigner` (the only trade entry point). A tap with no wallet at all now says so instead of doing nothing. The trade review's funds check offers **Get SOL for fees** when the wallet's SOL can't pay for a trade (server's count), else the old "send SOL" path where swaps are off. |
| Publishing a market | `publishWalletOf` (new default resolver for `ProposalDetailScreen` / `MyMarketsScreen`): wallet app, else `PantaEmbeddedCreateWallet`, which signs only a create shaped as the BFF checks it (`panta-create/docs-v1`) for the reviewed market address. The fee sheet says "Sign and publish" / "no second screen" for the on-phone wallet. |
| Profile → My wallet | Mainnet USDC + SOL from `deposits.balance` (server, genesis-pinned) on the card for both wallet kinds, and in the wallet-app sheet. The legacy `MwaWalletProvider.balance` (devnet RPC) is no longer shown anywhere. |
| SOL for fees | New `lib/features/sol_topup/`: client for `solTopUp.*`, the phone's own swap checker (`domain/gasless_swap_check.dart`), signers for both wallet kinds, controller, sheet and inline prompt. Shows up after an Add funds delivery, in the trade review and in both wallet sheets. |
| Copy (M11) | The stale "link Google in Profile → Settings" funding copy was already gone; the remaining "existing account" wording in Panta errors/recovery is replaced. |

## 2. Integration-owned files

- **Mobile:** none. No `main.dart`, `pubspec.yaml` or lockfile change. New
  code resolves everything from providers that already exist
  (`ChumbucketSession`, `MwaAuthProvider`, `EmbeddedWalletController`).
- **API:** `src/api/router.ts` — one import and one key (`solTopUp:
  solTopUpRouter`) with a 3-line comment. Nothing else.

## 3. Server (API branch `fleet/wallets`)

`solTopUp.status | plan | order | execute` (POST mutations, Supabase session).
Off unless `SOL_TOPUP_ENABLED=true` **and** `JUPITER_API_KEY` is set; until
then `status` says "Swapping USDC for SOL isn't set up yet" and the app keeps
the "send SOL yourself" path. No migration: pending swaps live in memory for
60 seconds (single replica, as the rest of the calls BFF).

## 4. Owner actions

1. Accept Jupiter's API licence/terms; create a Swap-only API key at
   <https://developers.jup.ag/portal> (Free plan to start).
2. On `chumbucket-calls-bff`: set `JUPITER_API_KEY`, then
   `SOL_TOPUP_ENABLED=true` (optional `SOL_TOPUP_TARGET_USDC`,
   `SOL_TOPUP_MAX_USDC`, `JUPITER_MIN_INTERVAL_MS`). Make sure
   `SOLANA_RPC_URL` is a mainnet RPC that allows `simulateTransaction` and
   `getAddressLookupTable`.
3. Deploy the API branch, then build the app.
4. On a device, once with a wallet app and once with the on-phone wallet:
   ~$2 USDC and 0 SOL → Profile → My wallet → Get SOL for fees → sign →
   SOL arrives → place a small Panta trade. Publish a market from the
   on-phone wallet once (it pays Panta's real creation fee).

## 5. Tests

`test/sol_topup_check_test.dart` (15, real mainnet transaction shapes),
`test/sol_topup_flow_test.dart` (16, fake transport), 
`test/wallets_wiring_test.dart` (4), `test/wallets_embedded_publish_test.dart`
(3), opt-in captures `test/sol_topup_visual_capture_test.dart`. Updated:
`deposits_wiring_test`, `market_creation_screens_test`,
`ui_people_layout_continuity_test` (the devnet balance is gone by design).
API: `tests/solTopUp.test.ts` (42).

## 6. Review (fleet/wallets-review, 3 October 2026)

Independent review of this packet against the merged tree (mobile `09aaff0`,
API `6ed8a4a`). What changed:

- **Claims from the wallet on this phone** (deferred here by the money
  packet). `profilePantaSigners(auth, onPhone)` now returns
  `PantaEmbeddedClaimWallet` for the linked phone wallet's own positions (a
  wallet app still comes first). It signs only the reviewed
  `claim_win_usdc`: one v0 signer = the intent's owner, bounded ComputeBudget,
  the owner's own USDC create-idempotent, ONE claim whose data is the
  discriminator + the owner and whose accounts are Panta's mainnet layout
  (read from real `ClaimWinUsdc` transactions: owner, config, **the reviewed
  market**, vault authority, vault, position, win-claim, **the owner's USDC
  account**, USDC, Token, ATA, System), an optional owner-signed text memo,
  and nothing else. The review itself must be a YES/NO win of positive
  shares. Tested against claims compiled by the BFF's own
  `PantaClaimExecution` (`test/wallets_embedded_claim_test.dart`).
- **Publishing from the phone wallet** (`PantaEmbeddedCreateWallet`): every
  Panta instruction must be a USDC market create (`create_event_usdc` or
  `create_breaking_event_usdc`; mainnet makes markets with
  `CreateBreakingEventUsdc`), so the key can't be steered into signing a buy
  or a claim dressed as a create; USDC accounts may be made only for the
  creator or an account the create names (the BFF's `derived` rule); and the
  ComputeBudget price is read as an unsigned u64 (a top-bit price used to wrap
  negative in a Dart `int` and pass the ceiling). If Panta's live create turns
  out to use another instruction, the phone refuses before signing (owner
  action 4 above exercises it).
- **SOL for fees**: the server bounds the rent repayment by today's live
  165-byte rent and refuses it when the person already had a WSOL account
  (API `docs/gasless-sol-topup.md` rule 8). On the phone, anything it can't
  decode now ends in "didn't pass this phone's checks — nothing was signed"
  instead of a spinner that never stops; after signing, an unreadable or 5xx
  reply is "unknown — check your balance", never "nothing was signed"; "landed"
  says "at least" when Jupiter didn't report the exact amount; "send SOL
  yourself" keeps the wallet's address when swaps are off; the sheet's
  subtitle fits one line at 390dp.
- **Attestation**: the funded-trading attestation does **not** gate the swap;
  it stays on `pantaTrading.prepare`, where a stake is placed (reasons in the
  API doc).

Integration-owned files: none changed.
