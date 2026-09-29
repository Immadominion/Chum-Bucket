# Panta production funding — 29 September 2026

## Shipped checkpoint

The dedicated production calls BFF now serves **Panta only**, with native funded
buys enabled. The reviewed wallet-signing flow is mounted; legacy wallet-string
trading stays refused. The normal Chumbucket app was updated in place on the
Seeker to 1.0.3 / version code 3, retaining the existing package and signer.
There was no uninstall, data clear, replacement profile or app-store submission.
The original Arena production endpoint remains configured and healthy.

No real wallet was signed, no transaction was broadcast, no user funds were
spent and no filled position is claimed. A live native crypto-market quote/build
for 2 USDC on NO compiled to a validated 706-byte **unsigned** transaction.

## Worktrees / files / commits

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`, starting `3bdf25c`.

- `74280c4`: `PantaExecution.ts`, `PantaHttp.ts`, `PantaChain.ts`, execution
  regressions and Docker secret-file exclusions. Native instruction/side/deposit,
  owner ATA, single signer, exact message and partner Memo validation.
- `a584f97`: new private trading router/runtime/store/service and PostgreSQL
  runner/tests; existing config/router, Panta discovery, durable hydration and
  call-write acknowledgement integration. Safe native funded flag, independent
  mainnet confirmation, cold recovery, concurrency and duplicate-buy guards.
- `a93619f`: provider-scoped market-sync cursor, failing-then-passing cursor
  regression, public zero-spend production smoke runner.
- Detailed protocol/rollback notes: API `docs/panta-native-trading.md`.

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`, starting `4155994`.

- `737ba05`: `lib/features/panta_trading/**`,
  `lib/features/authentication/session/panta_mwa_wallet.dart`,
  existing `mwa_auth_provider.dart` and `call_detail_screen.dart`, five new test
  files, plus compatible signing-method signatures in the existing account-proof
  and local-device tests. The existing call gets an optional funding sheet;
  no main.dart, pubspec, lockfile or global navigation rewrite.
- `supabase/migrations/20260929120000_panta_trade_sessions.sql`: additive private
  ledger with immutable reviewed approvals, evidence/state guards and a partial
  unique index for one active/filled approval per person/call/wallet.
- `scripts/apply-panta-production.ts`: exact-project, explicit opt-in,
  hash-pinned two-migration transaction and aggregate preservation checks.
- This checkpoint. All git commits are local; no push occurred.

## Exact verification

| Check | Actual result |
| --- | --- |
| API typecheck | `tsc --noEmit`, exit 0 |
| Final full API tests | 979 pass / 102 skip / 0 fail; 3234 assertions; 1081 tests across 62 files; 1217ms; exit 0 |
| Fresh PostgreSQL 15 ledger tests | 62 pass / 0 fail; 437 assertions; 3.22s; exit 0 |
| Populated local DB safety fence | Second opt-in refused before writes |
| Full Flutter tests | `00:17 +857 ~7: All tests passed!`, exit 0 |
| Full Flutter analyzer | 0 errors / 0 warnings / 275 existing info; 4.6s; exit 1 |
| Targeted changed native UI/wallet tests analysis | No issues found; 2.6s; exit 0 |
| Live Panta quote/build | Crypto ETH September-30 market, NO, 2 USDC; 706 unsigned bytes; exact partner Memo; no signing/broadcast/fill |
| Production HTTP smoke | 8 checks pass; Panta-only, funded enabled, native ready, live crypto discovery, anon/forged/private-order refusals, old trading route refused |
| Original Arena health | HTTP 200 / healthy |
| Seeker in-place update | Install success; code 3; same signer and first-install time; no uninstall/data clear |
| APK forbidden asset filenames | No `.env`, local env JSON, Admin SDK or keypair asset |

The default API suite skips optional live-database tests, including the new
ledger checks; those 62 ran separately on actual fresh PostgreSQL. Flutter's
seven pre-existing opt-in/disabled tests stay skipped. Six native Flutter/BFF
contract tests run through the real mounted tRPC adapter but synthetic external
identity, ledger, venue and chain boundaries; they are not physical MWA evidence.

The PostgreSQL runner shut down its own cluster. Its owner-only synthetic
artifacts remain at `/private/tmp/chumbucket-panta-trading.SAlQS3t9`;
`pg_ctl status` exit 3 and absent postmaster.pid prove shutdown. The normal
PostgreSQL service was untouched.

## Production writes and preservation

Explicit user approval: “I HATE that funded trading is off. please build on prod.”
Target Supabase: `odxsineiqquxqiuhxgfq`.
Only these reviewed migrations were applied, in one transaction with migration
history bookkeeping and PostgREST schema reload—not a bulk db push:

- `20260928210000_panta_share_price_evidence.sql`:
  SHA-256 `472d2681b6411405c6621a92468a88876aca88b9a98845fdd1d94b943b304f7d`.
- `20260929120000_panta_trade_sessions.sql`:
  SHA-256 `20389e8fd29e01aab441dfd2e5a8c944f0a040c0d7a57f83f36ee3c93c551ec3`.

Before/after migration: 212 people, 14,868 historical markets, 655 resolution
records, zero prediction calls and zero linked Google people: **unchanged**.
Verified ledger RLS, zero client policies, anon/authenticated denial, both ledger
guards and immutable native-price pin columns. No account anchor was approved,
no existing person mapped to a Google subject and no legacy table rewritten.
The empty trusted account-claim registry remains a separate reviewed rollout.

Railway project `77e62285-a06d-4f5b-87b7-9de24fd02e2e`, production environment
`16dd9edb-fd0d-40d1-841a-08b6a3a0be35`, service
`63424c97-c8bc-4f67-bb1c-46aac5baf9cc` (`chumbucket-calls-bff`).
Current deployment: `17ace837-f9b4-4662-9f68-ba00449e06f8`, source `a93619f`,
verified SUCCESS. Public endpoint:
`https://chumbucket-calls-bff-production.up.railway.app`.

Public native flags/program/partner attribution/schema readiness and per-approval
limit were configured; provider and Supabase credentials stayed server-held.
`FUNDED_POSITIONS=true`; `PREDICTION_VENUE=panta`; mainnet public RPC for native
execution; unrelated keeper/reconciler off on this **dedicated** service.
The social `SOLANA_NETWORK=devnet` namespace remains unchanged. Panta verifies
mainnet RPC genesis and obtains a mainnet wallet grant separately, preserving
legacy profile/follow/history network behavior. Original Arena service:
`https://chumbucket-arena-production.up.railway.app` — not deployed or changed.

After venue sync, production has eight Panta market rows and two native price
observations alongside the unchanged 655 old resolutions. Zero calls / trade
sessions / linked people at the final aggregate check. Public discovery exposes
two priced crypto markets; the ETH market is the short-horizon test candidate.
The longer-dated BTC market still needs the initial 4-hour–7-day discovery policy
review; no market rule or resolution was invented to make it eligible.

## Defects caught during verification

1. Native Memo identifies the API key's `usr_` partner, not a Chumbucket person
   UUID. The binding now pins that partner separately and keeps canonical app
   identity private. Cross-partner replay is refused.
2. Panta `startTime` is event start, not trading-open time. Native buys can be
   built before that event. It is retained in raw evidence; no invented opening
   time blocks a valid market.
3. Blank list titles have real detail metadata. Plausible live rows are hydrated;
   incomplete/stale rows are not made up. Duplicate rows are coalesced.
4. Eight SQL guard gaps found by real PG tests were fixed before production
   apply: early evidence/signatures, non-object prepared data, contradictory
   binding/order/review attribution and unbound confirmed fill fields.
5. The first production build (`5d082688-d27b-4a03-a830-1aa6ed8ed438`) reused the
   old Polymarket cursor and produced `Invalid Panta market address`. A local
   regression first failed 0 pass / 1 fail, then passed after provider scoping.
   The corrective build uses `venue_markets:sync:panta`; the original
   `venue_markets:sync` cursor (page 50) is retained unchanged. Discovery/sync
   now pass; no production cursor was deleted/reset by an operator.
6. Risk disclosure caused offscreen input/status in large-text tests. The input
   remains first; phase changes bring status/review back into view. Final widget
   and full-suite runs pass.

An earlier BBNaija unsigned build was refused with `INVALID_MARKET_PARAMS`.
That refusal was not rounded away, fabricated into a fill or substituted for the
user's chosen market. The later ETH crypto quote/build passed the real guard.

## Seeker artifact and remaining gate

Normal `lib/main.dart`, package `dev.cleva.chumbucket`, version 1.0.3 / code 3.
Production calls BFF and original production Arena URL are separate build
settings. No private provider key or complete `.env` is bundled.

APK: `build/app/outputs/flutter-apk/app-debug.apk`.
SHA-256: `ba4a2a7c62641254a01b425e0e503dfd124085247d2ef14564dd3ddc7b9a37d2`.
Installed/candidate certificate SHA-256:
`95BA33D57D40875C15B67320C5D460C90AFFDEFEC22698B93C4A5927C5A47B26`.
This is a same-signer **debug Seeker test candidate using production services**,
not the public dApp-store release: the published release has a different signer.
No release-signing credential was opened/exported or casually rotated.

Physical check: the updated app opens the original “Connect Wallet” onboarding,
not a synthetic device-test harness or replacement “Create my profile” screen.
It is currently signed out. Wallet connection, Google linkage, an authenticated
call and wallet approval are **not** proven by this screenshot or test suites.

The founder was asked which existing profile to preserve. Next packet:
connect the same existing wallet and leave Profile open, approve the exact
existing-person claim evidence/cohort, then verify Google + SIWS linkage and the
free loop on this handset. Only afterward choose an explicitly approved small
trade and inspect independent fill/receipt evidence. Do not fund the public
synthetic test wallet or use the exposed deploy keypair.

In-app selling/claiming is not available in this increment and is explicitly
disclosed before approval. Eligibility/compliance and store-release checks remain
outstanding; no broad public release or completed trading E2E is claimed.
The credential-remediation actions in workspace `docs/recovery-manifest.md`
remain founder/admin work; no external rotation was performed this turn.

## Rollback / original work

Prior dedicated BFF: `dc76cade-6395-43d9-ba1b-cc9d65079da7`.
Before any new Panta call/order, restore its original image/config if needed.
After one exists, pause prepare/submit with `FUNDED_POSITIONS=false` and keep
native order/recovery reads available while rolling forward a corrected image.
Keep additive tables/evidence; never drop approved or confirmed history.

Stop on false funded state, private order access, wrong venue, missing person /
history, failed hydration or mainnet mismatch. The public smoke runner performs
no signing/broadcast and validates private authorization refusals.

Read-only final audit confirms original checkouts unchanged:
canonical mobile 20 dirty entries at `cc8acaa`; reference mobile 138 at
`4ef31ae`; original API one lockfile entry at `ccac2c4`.
No clean/reset/checkout/stash/pull/rebase or secret-file contents were used.
