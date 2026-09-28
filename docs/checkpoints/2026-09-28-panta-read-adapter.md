# Repair checkpoint 4 — real Panta reads, not a tester-ready release

28 September 2026. No production changes, no money movement, no device install.

## Worktrees

- API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
  branch `product/social-calls-api`, started at `7256164`.
- Documentation only: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
  branch `product/social-calls-v3`, started at `e377374`.
- Original dirty checkouts, recovery archives, mobile executable code,
  dependency/lockfiles, database schemas and Railway settings were not changed.

## Implemented

`PantaVenue` implements the existing `PredictionVenue` read seam. It reads the
official live API through a server-held live key. Requests are GET-only, paced,
timed out, retried with Retry-After/backoff, circuit-broken, coalesced and cached.
The origin is pinned and redirects are forbidden so credentials cannot follow
an arbitrary endpoint. Neither provider error bodies nor request causes escape.
Missing/test keys fail closed; a sandbox response cannot become a live market.

Market normalization preserves venue address, exact title, on-chain rule text,
seconds-to-milliseconds timestamps, raw status, source URL and versioned raw
evidence. Untitled rows and rows lacking actual resolution rules are omitted,
not supplied with invented text. An empty filtered page retains its cursor.

Native prices have their own additive optional capability and tRPC read:
`predictions.indicativePrices({venueMarketId})`. They are decimal strings in
USDC **per share**, independently nullable, can exceed one, and are explicitly
non-executable. The response includes `Powered by Panta`. No complementary NO
price, orderbook depth or `MarketSnapshot.yesProbability` is manufactured.

The market-detail response contains more than the documented catalog example.
Its venue-reported `onChain` fields carry final-result evidence. A YES/NO result
requires mutually consistent resolved flags, a boolean `yesWins`, no pending
review, and elapsed resolution, claimable and review times. Cancellation needs
explicit chain cancellation evidence. Status alone, price 1/0, and an oracle
proposal cannot settle a call. This is **Panta-reported chain state**, not a new
independent Solana RPC verifier. Missing/unknown finality evidence stays pending.

`PREDICTION_VENUE=panta` now constructs this adapter in local read-only testing;
`PANTA_API_KEY` and `PANTA_TIMEOUT_MS` are server-only. The funding flag is forced
off for Panta, and every execution/portfolio method independently refuses.

## Deliberate integration boundary

This is not a completed Panta free-call or funded-trading flow:

- Calls currently pin a probability snapshot and their SQL expects that model.
  Panta share prices do not fit it. Panta create/back/fade writes are therefore
  disabled; price-aware immutable call/receipt records remain to be integrated.
- No Panta SQL/client migration was applied or written in this increment. The
  runtime refuses selecting Panta with a configured durable backend rather than
  silently downgrading it to a volatile mirror. Explicit in-memory test overrides
  remain available. Existing Polymarket/Jupiter/fixture behavior still passes.
- Mobile does not yet accept/render the Panta vocabulary. No new navigation,
  duplicate profile flow, wallet gate or replacement home screen was added.
- The latest existing-account bootstrap remains default-off and not connected
  to Settings. Credential-remediation and whole-app release gates remain open.

## Live evidence, bounded and read-only

Used the existing Railway service `chumbucket-calls-bff` in project
`chumbucket-arena`, production environment, to read configuration into process
memory. No key value or raw configuration was displayed or saved. No variable
was changed, key minted/rotated, account registered, quote requested, market
created, order submitted, transaction signed or provider contacted for support.

The Railway skill guided explicit service/environment selection and read-only
CLI use. The installed CLI is 4.66.0; no tool upgrade/setup was performed.

Two raw live catalog pages: **85 rows**, six nonblank titles, seven nonblank
descriptions; statuses: primary 5, secondary 2, resolved 78. All six titled rows
were resolved. This is a current sample, not a promise about future availability.
One sandbox read confirmed the fixture disclaimer and ISO timestamps; the live
adapter refuses that mode.

Then ran the actual new adapter with the live key and crypto category:

```text
pages: 1
normalizedMarkets: 6
openMarkets: 0
resolvedMarkets: 6
publishedResolutions: 6
more: false
priceUnit: per_share
currency: USDC
executable: false
demo: false
tradingEnabled: false
```

These are historical markets, including provider test content; no Chumbucket
call was created against them. The live check does not prove a new call→receipt
cycle, complete catalog quality, funded execution, eligibility or compliance.

## Verification

The debugging skill drove schema/failure tests and a live read through the same
adapter under test. The initial test failed because the adapter did not exist.
Intermediate typechecks caught an untyped base58 import and a test wallet's
missing brand; both were corrected without new dependencies or weakened checks.

- New adapter tests: **45 passing**, 153 assertions, exit 0.
- `bun --no-env-file test`: **691 pass, 27 skip, 0 fail**, 2363 assertions,
  718 tests across 54 files, 905 ms, exit 0. Compared with 646 passing before
  this increment. The same opt-in database checks remain skipped; no DB ran.
- `bun --no-env-file run typecheck`: exit 0, no diagnostics.
- `git diff --check`: exit 0. No Flutter tests/build/install this increment;
  mobile executable code is unchanged.

Both database test URL variables were unset and automatic `.env` loading was
disabled for unit/typecheck commands. Test payloads and keys are synthetic.
Live data was read only during the separate bounded read checks above.

## Changed files

API-relative: new `src/prediction/PantaVenue.ts`, `tests/pantaVenue.test.ts`;
updated `src/prediction/{types,PredictionVenue,PredictionService,config,runtime,index}.ts`,
`src/config.ts`, `src/api/predictions.ts`, `src/calls/{CallsService,markets}.ts`,
and the expanded config fixture in `tests/supabasePersistence.test.ts`.

Mobile-relative docs: this checkpoint and a historical-status notice in
`docs/contracts/panta-venue-findings.md`.

## Next packet / remaining blocker

Add a tagged native-price snapshot/call/receipt contract, compatible additive
storage, and Panta attribution within the existing mobile components. Wire
existing-account proof through the existing Settings action. Then build a
configured Seeker candidate and verify the full free loop on-device.

A live Panta-only open-call test also needs a complete, open, appropriately
dated Panta market. None was available in this read. Market creation would
require separate approval of exact terms and a fresh fee quote; historical fee
figures are not spending authorization. Do not silently substitute Polymarket
or present a sandbox market as live to get around this missing input.

## Primary documentation checked

- [Catalog list](https://docs.panta.market/api-reference/markets/list.md)
- [Market detail](https://docs.panta.market/api-reference/markets/get.md)
- [Positions and price units](https://docs.panta.market/api-reference/positions.md)
- [Authentication](https://docs.panta.market/guides/authentication.md)
- [Errors/rate limits](https://docs.panta.market/guides/errors.md)
- [API attribution and terms](https://docs.panta.market/guides/terms-of-use.md)

The detailed finality fields were observed in live responses; they are not
invented additions to the sparse documented response example. A future shape
change requires adapter review, not guessing a settlement.
