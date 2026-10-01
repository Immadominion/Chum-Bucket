# Panta catalog, smarter Add Friend, complete design audit

## Outcome

**1.0.13 / code 13** is installed on the Seeker with the existing account and
friend graph retained. The approved calls-BFF catalog fix is deployed. This is
not a claim that account recovery, positions or the complete trade lifecycle
are finished. See the [whole-app design audit](../design-audit-2026-10-01.md).

## Worktrees and scoped commits

- Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
  `product/social-calls-v3`; `19546c5` smart friend entry, `5bef21d` catalog/UI,
  `ed186ca` final sheet-density correction. APK built from `ed186ca` runtime.
- API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
  `product/social-calls-api`; `fe23f67` catalog repair.
- Original dirty checkouts were not changed, reset, cleaned or stashed. No push.

## Files changed

- Friend UI: `lib/shared/screens/home/widgets/add_friend_sheet.dart`; new
  `shared/models/friend_identifier.dart` and `shared/services/friend_connection_service.dart`.
  Uses the existing database friend action and existing wallet-signed X proof.
  One identifier field accepts a validated wallet, X handle/profile link or
  supported domain. Nickname is optional. Pending handles do not promise a
  notification. Domain lookup races, self-add, account changes and retry are guarded.
- Catalog UI/data: `features/calls/data/{calls_repository,bff_calls_repository}.dart`,
  `providers/calls_provider.dart`, `presentation/screens/call_markets_screen.dart`,
  `presentation/widgets/{call_market_card,market_picker_sheet,call_composer_sheet}.dart`.
  All open Panta categories/dates by default; Crypto/time filters optional;
  independent price chips replace tall nested price cards. No provider key on-device.
- Tests: new `friend_identifier_test`, `add_friend_sheet_test`, `bff_catalog_test`;
  updated `call_home_screen_test`, `calls_catalog_regression_test`,
  `ui_market_layout_discovery_test` to exercise the new catalog contract.
- API: `src/prediction/{PantaVenue,runtime}.ts`, `src/api/predictions.ts`;
  `tests/pantaCatalogDiscovery.test.ts`, cursor-isolation/venue regressions and
  `docs/panta-catalog-recovery-2026-10-01.md`.

## Actual Panta failure and repair

1. The upstream catalog returned an opaque **134-character cursor**. The adapter
   required a Solana address, so `predictions.listEvents` returned HTTP 500 before
   accepting the page. A redacted shape-only probe confirmed this; no key/body log.
2. `markets.open` is intentionally call-ready: missing/stale prices remove a row.
   That was incorrectly used for browsing. Panta list prices are null by design.
3. The phone imposed another crypto-only / 4-hour–7-day restriction. The user
   explicitly chose all Panta markets with optional filters on this turn.

The new `predictions.catalog` is a paginated normalized durable read, independent
of prices. The worker now walks every category on a separate cursor. Call-lock
freshness, resolution evidence, wallet proof and trade validation remain intact.

## Verified results

- Final `flutter analyze --no-pub`: **No issues found**, exit 0.
- Final `flutter test --no-pub --reporter expanded`: **1000 pass, 11 skip,
  0 fail**, exit 0 (75 seconds while build work was also running). Earlier full
  run before the final two-line density correction: same counts, 28 seconds.
- Focused friend tests: **8 pass**, including 320dp / 2× / keyboard and stale
  domain response protection. Identifier parser contributes 16 further tests.
- Opt-in real-widget market/detail captures: **4 pass** at 390dp/1× and
  320dp/2×; visually inspected. These are labelled synthetic captures, not live evidence.
- API typecheck: exit 0. Full suite: **1005 pass, 103 skip, 0 fail**,
  3387 assertions / 66 files, exit 0. Skipped tests include database-dependent
  suites; no database migration was changed or run.
- Android debug build: exit 0. Kotlin/Gradle migration warnings remain.
- `git diff --check`: clean. Scoped source commits made; no remote push.

## Approved deployment

- Only service `chumbucket-calls-bff` (`63424c97-c8bc-4f67-bb1c-46aac5baf9cc`)
  in project `77e62285-a06d-4f5b-87b7-9de24fd02e2e`, production.
- Deployment **`a89828f3-564c-4e8b-b425-985e140d17c3`**, Railway status SUCCESS.
- Exported 145 committed runtime files, including required vendor IDLs; local
  Bun import-graph validation passed before upload. Export archive SHA-256:
  `f56ac16607a61d022a22c911d7f388848afaf059ebf8d092e7e016c629523784`.
- New catalog and `predictions.listEvents`: HTTP 200 after rollout (was 500).
- At **00:53:55 UTC**, catalog contained 13 normalized markets across crypto,
  gaming, pop-culture, sports and commodities; **6 open** with future close times.
  Counts are observations, not a promise of future provider availability.
- Both calls-BFF and original Arena health: HTTP 200. Original Arena deployment
  stayed `3842b0d5-8793-431e-b330-f8ab292f60df`.
- `predictions.config`: `venue=panta`, `demo=false`, `fundedPositions=true`.
  `pantaTrading.status`: HTTP 200, enabled true, Powered by Panta. **No trading
  setting was disabled or changed.** This is not a successful funded-trade test.
- Bounded post-deploy worker samples showed successful catalog syncs and zero
  failure markers in the observed sample. No raw request/auth logs were printed.
- No credential, schema or trading-setting changes were made; no friend/call/order
  mutation was submitted. Normal existing catalog-worker persistence continued
  for the newly included categories.

## Device / artifact

- Device: Seeker `SM02G40619141343` only; the attached Infinix was not operated.
- Package: `dev.cleva.chumbucket`; version **1.0.13 / 13**. Final device update
  time: `2026-10-01 01:53:05` local.
- Final APK SHA-256:
  `fb915defbb3dac3b5d124ba1bb6e9e3053e8acaa00abc5babdb1805f3d6171ed`.
- Signer SHA-256 matches the installed app:
  `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`.
- APK inventory: no `.env`, keypair, Firebase Admin/service-account, PEM, key,
  keystore or JKS filenames. Build defines were explicitly public-allowlisted,
  not a copied environment. No secret values displayed or committed.
- Installed with `adb install -r`; no uninstall, app-data clearing or session extraction.
- On-device: real Panta markets rendered, including $JUMP, GTA 6 and Bitcoin;
  after refresh, oil and sports predictions also appeared with actual side prices;
  original Friends and Profile remained; Add Friend detected a synthetic X handle
  and a public test address; keyboard and cancellation exercised without submission.
  Settings and the currently wired Inbox were visually inspected without activating
  account, support, read-state, friend or money-changing actions.
- Font scale was 1.0 before and after this pass. 2× was exercised in widget tests;
  this checkpoint does not claim a new full TalkBack/device 2× audit.
- Private screenshots/logs: `/private/tmp/chumbucket-design-audit-20261001.A0N4vy`.
  They are not committed because some contain real profile/friend information.

## Remaining / next packet

The audit covers the entire app's design and routing, but the whole-app cleanup
is **not finished**. Next: compress Profile/account-recovery hierarchy; standardise
secondary sheets and headers; reconcile the two inbox sources/targets. Then finish
existing-person auth, complete following/invitation semantics and the real positions/
sell/claim lifecycle. Do not remove old user history or paint missing holdings.

No production friend/call/order was submitted, no wallet message/transaction
approved, and no external share or credential rotation performed in this pass.
