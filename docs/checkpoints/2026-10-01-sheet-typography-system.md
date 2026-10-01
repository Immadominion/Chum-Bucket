# Shared bottom sheets and coherent typography — 2026-10-01

## Scope and branch

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
`product/social-calls-v3`, based on `73962df` for this increment.
API and original dirty checkouts were not modified. No deployment, production
mutation, sign-in approval, trade, fund transfer, profile save or friend write.

## Changes

- Added common page/question/sheet typography roles in `app_text_styles.dart`.
  Market rows and prediction-feed questions now share the same 18dp display
  style; the shared tab header uses 28dp. Kept PP Neue Machina/Montserrat.
- Rebuilt `chumbucket_wavy_sheet.dart`, added `chumbucket_sheet_header.dart`,
  and fixed `wave_clipper.dart`. The scalloped edge now has visible depth;
  one component owns header text, close target, frame, backdrop and insets.
- Migrated all app-owned bottom-sheet entry points, including the older
  settings/wallet/friends/avatar/receipt/notification/caller/challenge surfaces.
  Removed duplicated modal frames and private header-height hacks.
- Preserved the originating wallet provider and missing-address refresh path.
  Close/back/backdrop guards respect busy state. Drag-pop is disabled because
  that Flutter route path bypasses `PopScope`.
- Fixed friend-picker enlarged-text overflow and fixed-height avatar actions.
  Challenge receipt data grows without the old 550dp clipping ceiling.
- Device testing caught and fixed top safe-area loss with an open keyboard.
  The modal route now preserves the status-bar inset before the shared frame
  applies its own clearance.
- Added regression/visual tests, updated the reviewed Home golden, and made
  existing large-text interaction tests scroll to hit-testable targets.

Component API, reference files and surface inventory:
[`docs/design/sheets-and-type.md`](../design/sheets-and-type.md).
The local design kit informed the shared floating frame and wave, not a
replacement of current brand fonts with its older font specification.

## Verification

- `flutter analyze --no-pub`: **No issues found**, exit 0.
- `flutter test --no-pub --concurrency=2`: **1,039 passed, 35 skipped, 0 failed**,
  exit 0 (`full-suite-final-insets.log`). Baseline was 1,004 passed / 11 skipped.
- New sheet-system regressions: **35 tests**. Coverage includes real modal
  navigation, status-bar/keyboard clearance, busy dismissal, wallet-provider
  continuity, wave geometry and 11 existing sheets at normal/2x text sizes.
- Focused final route/trade/call/friend/continuity run: **69 passed**, exit 0.
- Opt-in real-font sheet captures: **24 passed**, exit 0. These 24 captures
  account for the additional skips in the ordinary suite; they were run
  separately and reviewed. No screenshot data is a live result or trade.
- Android debug APK built successfully as **1.0.15 (15)**, installed with
  `adb install -r` on Seeker `SM02G40619141343`. No uninstall or data clearing.
- APK filename scan found no `.env`, `env.local.json`, Admin/service-account
  JSON, private-key or keypair file. Defines use the existing explicit public
  allowlist, not an environment-file spread.

Final APK SHA-256:
`809da1b1d6a1c65d4f00d9baaac9bd819ee7061f402243eb39c1cdd82828bd2c`

Signer certificate SHA-256 (matches previous installed test build):
`95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`

## Device checks and evidence

Opened Home, Markets, Friends, Add Friend (including keyboard), Profile, Account &
Support, My wallet and the receive-address/QR sheet. Existing profile and
friends survived the in-place update. No form was submitted. Verified the
keyboard-raised sheet stays below the status bar and above the keyboard.
The device was left on Markets with its real Panta catalog visible.

Private local evidence/logs:
`/private/tmp/chumbucket-sheet-system-20261001.CmRR9z/`.
Real-font fixture captures: `/tmp/chum-sheet-*.png`.
Build helper/log: `/private/tmp/chumbucket-ui-seeker-20261001.rljrp6/`.
Actual device screenshots stay outside git because they include account UI.

An initial full test attempt hit temporary disk exhaustion. It was interrupted
and repeated successfully with two workers. No source/recovery backup was
deleted; generated failed-golden images were moved into the private evidence
directory. Build emitted existing Gradle/AGP/Kotlin migration warnings; no
toolchain/dependency upgrade was included in this presentation change.

## Boundaries / next checkpoint

This verifies the UI refactor, not readiness of funded trading or every live
backend state. The device's existing social-call identity was not connected,
so call record availability and authenticated composer/receipt states were
tested through fixtures, not by creating a new account or placing a live call.
The next checkpoint is visual review on this Seeker build; account/BFF work
remains separate from this scoped change.
