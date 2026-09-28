# Checkpoint — immutable Panta price-at-call evidence

## Outcome

Local Panta free calls now preserve exact independent USDC/share observations
through call, Back/Fade, settlement, persistence, restart and existing receipt
rendering. They never populate probability fields. No app shell/navigation or
account identity changed. Panta-only selection and money-off gates remain.

The debug skill shaped this increment: trace the old probability-only path,
add a separate contract, then test malformed/stale evidence and restart behavior.
See `../contracts/panta-share-price-v1.md` for the additive contract.

## Worktrees/files

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`.

- New `src/prediction/sharePrices.ts` and
  `tests/{pantaSharePrices.test.ts,pantaPrices.postgres.test.ts}`.
- `src/prediction/{PantaVenue,PredictionService,marketSync,runtime,store,supabaseStore}.ts`:
  strict evidence, sync/storage/restart support; deployment gate preserved.
- `src/calls/{CallsService,markets,receipts,runtime,store,supabaseStore,types}.ts`:
  pinned entry prices, immutability and separate historical probability handling.
- `tests/pgrestFake.ts`: transport support for the new table. Real SQL behavior
  is tested on PostgreSQL, not claimed from the fake.

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`.

- `supabase/migrations/20260928210000_panta_share_price_evidence.sql`.
- `lib/features/calls/data/{call_models,calls_repository,calls_bff_payloads}.dart`.
- Existing `market_detail_screen.dart`, `call_card.dart`, `call_composer_sheet.dart`,
  `call_response_sheet.dart`, `calls_format.dart`, `market_picker_sheet.dart`.
- Existing receipt model/card, new `test/panta_share_price_test.dart`, this
  checkpoint and the native-price contract document.

Original dirty checkouts remain untouched. No credentials opened, no keys
logged/copied, no provider calls, pushes, deployment, wallet action or device
installation in this packet.

## Actual verification

API commands use `bun --no-env-file` and explicitly unset all three opt-in test
database URL variables for the ordinary test suite.

- `bun run typecheck`: exit 0, no diagnostics.
- New focused API suite: **19 pass / 0 fail**, 61 assertions.
- Full API: **712 pass / 38 skip / 0 fail**, 2,442 assertions;
  750 tests across 56 files, 999 ms, exit 0.
- New disposable PostgreSQL suite: **9 pass / 0 fail**, 43 assertions,
  343 ms, exit 0. Real prior catalog/resolution/call migrations plus the new
  migration applied. Checks include append-only enforcement, raw/price parity,
  stale/future/cross-market evidence, no client writes/raw reads, public-market
  withdrawal, and two-user followers-only visibility.
- New Flutter suite: **14 passed**.
- Full `flutter test --no-pub --reporter expanded`: **591 passed, 1 skipped,
  0 failed**, 16 seconds, exit 0.
- `flutter analyze --no-pub`: **0 errors, 0 warnings, 275 existing infos**,
  4.2 seconds, exit 1 (unchanged info baseline).
- `git diff --check`: clean in both worktrees.

Failures fixed before the final runs: missing TS import; PostgreSQL test-harness
double-encoded JSON and lazy query execution; widget test initially signed out
and then needed to scroll to the lazy-built refusal message; one new style lint.
No assertions or safety gates were suppressed to get a passing result.

The isolated PostgreSQL 15 cluster was created under
`/private/tmp/chumbucket-panta-prices.Ie3ujO/cluster`, loopback port 56583.
It is stopped (`pg_ctl status`: no server running). Scratch data/logs remain
for reproducibility, including renamed failed-attempt databases. The user's
existing PostgreSQL service was not used or changed. SQL test harness follows
[Bun's SQL API](https://bun.sh/docs/runtime/sql) and was verified on installed
Bun 1.3.14; the first encoding/execute assumptions were caught by real execution.

## Not yet release/device ready

The migration has NOT been applied to production. The durable Panta runtime
gate and default-off local call gate remain; no newly configured APK was
built or installed. Test fixtures prove the contract, not live market availability.
The prior live catalog check found no usable open Panta questions; this packet
made no new catalog request and does not assume that state has changed.

Next: existing-account Settings linking, then approved schema/deployment review
and configured Seeker free-loop validation. Trading stays disabled. Market
creation or funding needs separate, explicitly scoped approval.
