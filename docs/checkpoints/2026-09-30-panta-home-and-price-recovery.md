# Panta Home and price recovery — 30 September 2026

## Outcome / worktrees

The enabled call-receipt experience now uses Panta discovery in the existing
Home tab instead of loading football Matchday. This does not replace the
four-tab shell, existing person/profile/settings, Friends, challenges or old
bet/history access. Mobile code commit `e346747` is on `product/social-calls-v3`
at `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`.

The dedicated BFF has a separate price-recovery correction, API commit
`894ece166a57e9c5de94f55ded1edd58382820dc` on `product/social-calls-api`
at `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`.
No original dirty checkout was changed, no Git push occurred, and no credential,
production identity, venue result or wallet transaction was edited.

## Files / behavior changed

- `lib/shared/screens/home/home.dart` and `widgets/predictions_home_tab.dart`:
  pass the existing experience flag into Home; load the calls catalog instead
  of football; show shared header, market preview, refresh/error/empty states,
  existing claims if present and existing challenges. Old behavior remains
  available when the experience flag is disabled.
- New `lib/features/calls/presentation/widgets/call_market_card.dart`, reused
  by `screens/call_markets_screen.dart`: shared Chumbucket styling/Basil icons,
  exact venue question, attribution and close time. No invented quote or crowd
  probability. Empty copy says no markets are **ready for calls**, since an
  open venue market can still lack usable prices.
- `screens/call_feed_screen.dart`, `screens/call_person_screen.dart`,
  `screens/market_detail_screen.dart`, `widgets/call_card.dart` and
  `widgets/market_picker_sheet.dart`: opening a call reaches its exact detail;
  creating one from Home/market/picker opens that new immutable call. Its
  optional Panta funding action is reachable, with no automatic trade request.
- `test/call_home_screen_test.dart`: seven additional cases cover the real
  BFF repository with a synthetic transport, Home/Calls exact-call navigation,
  no Matchday request, retry/cached/empty states and large text. Existing
  Profile/Settings/history tests also run with the experience enabled.
- API `src/prediction/marketSync.ts`, `tests/pantaVenue.test.ts` and
  `docs/panta-price-recovery.md`: retry missing Panta side prices after one
  minute on a subsequent bounded pass; refresh complete prices at five minutes
  before their unchanged ten-minute validity deadline. Five new tests retain
  fail-closed behavior, exact evidence and separate free/funded provenance.

## Actual verification

- Full Flutter: **885 pass / 7 skip / 0 fail**, exit 0. After the final empty-copy
  adjustment, Home/feed/market targeted suite: **46 pass / 0 fail**, exit 0.
- Final full `flutter analyze --no-pub`: **274 info / 0 warnings / 0 errors**,
  exit 1, matching the prior baseline. Do not call that analyzer exit 0.
- Full API: **997 pass / 103 skip / 0 fail**, 3,372 assertions, 1,100 tests
  across 65 files, exit 0. Optional database tests remain skipped. No migration
  is included in this increment. `bun --no-env-file run typecheck`: exit 0.
- Focused Panta adapter/share-price/persistence suite: **98 pass / 0 fail**,
  407 assertions, exit 0. `git diff --check` passed in both worktrees.

## Production observation and deployment

Initial public production smoke failed at crypto discovery: HTTP 200, zero
call-ready markets. Read-only public-market/aggregate SQL showed three OPEN
Panta crypto markets, no resolution on them, future close times and **null YES
and NO prices** in all three latest captured observations. Allowlisted worker
logs showed successful sync passes. A fresh public indicative-price read then
returned actual prices for ETH; the eight-check smoke passed with one eligible
market. The query warmed venue evidence, not a call/order. This is intermittent
price availability, not proof of a provider-wide outage. See API recovery notes
for the verified local ten-minute retry defect and the unproved upstream cause.

The dedicated Railway project/environment/service were checked by ID before
upload. Deployment `ef7fc3d1-cb6f-4ed3-9903-a7e023d54110` was submitted from a
committed, allowlisted source export at
`/private/tmp/chumbucket-calls-bff-price-recovery.fMLPbZ` (runtime source,
package/lockfile, Dockerfile and Railway configuration only; no local `.env`).
That first export mistakenly omitted the shared server's `vendor/` imports.
The deployment crashed before startup; this was the implementation agent's
packaging error. Filtered logs identified the missing `txoracle.json`, and a
local Bun import-graph check reproduced all three missing-import failures.
The corrected committed export at
`/private/tmp/chumbucket-calls-bff-complete-export.MeCQKr` included vendor IDLs
and `tsconfig.json`; its 113-module import graph passed before upload.
Replacement deployment **`3eac1d25-ebfc-464e-9e5f-f8707952d73b` reached SUCCESS**.
API `scripts/prepare-calls-deploy.ts` now performs the allowlisted export and
import validation before any future upload. No production credential was
copied into either artifact. The original Arena service remained HTTP 200;
runtime variables and database schema are unchanged.

Read-only canonical-follow verification returned 212 people; zero legacy
follows, calls, call results and native trade sessions; all nine schema/grant
checks true. This is a scoped aggregate check, not a full legacy-asset audit.

After replacement SUCCESS, the production smoke returned **8/8 pass**, one
call-ready Panta crypto market, `fundedPositions=true` and native readiness on;
anonymous/forged/private-order/old-trading refusals all passed. No signing,
broadcast or fill occurred. API export-validation tooling is separately
committed as `a504c07`; the deployed runtime source is `894ece1`.

## APK / handset boundary

- Built **1.0.8 / code 8**, normal `lib/main.dart`, with public allowlisted
  configuration, `CALLS_BACKEND=bff`, `CALL_RECEIPT_EXPERIENCE=true`,
  `CHUMBUCKET_EXISTING_PROFILE_ONLY=true`, old social namespace `devnet` and
  separate native Panta mainnet signing behavior unchanged.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- SHA-256: `3ee0351c896ada80e1f0b90c5ec8bc86be09628a8e0a6a6b4b4b430bf2e76155`.
- Signer SHA-256: `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`,
  matching the previously installed candidate. Filename scan found no `.env`,
  local config JSON, Admin SDK, keypair or keystore asset; not a full binary
  security audit. Build succeeded with existing Gradle/AGP/Kotlin/NDK warnings.
- **Seeker absent from ADB throughout this increment. Code 8 has not been
  installed or visually/device-tested. Last witnessed installed version remains
  1.0.7/code 7.** Do not describe emulator/widget tests as handset proof.

## Next checkpoint / risks

Connect/unlock Seeker `SM02G40619141343`, accept the USB-debugging prompt if
shown, verify installed signer/version, then update in place without data clear.
Inspect Home/Calls/Profile/Settings/history and continue one founder-selected
original-wallet connection. Code 7's Solflare secure-session issue is not yet
proven resolved. Do not create another profile or seed a trusted claim from a
mutable wallet mapping. Production canonical account-claim rollout and real
SIWS/Google continuity remain unfinished.

Panta-only native funding is enabled, but no real funded order was signed,
broadcast or verified filled. Real-account follow/call/result/receipt, physical
wallet approval/recovery, sell/claim, notification/record and HTTPS-link/release
work remain. A funded test needs an explicitly chosen market/side/amount and
user wallet approval; no funding is needed merely to install or inspect Home.
