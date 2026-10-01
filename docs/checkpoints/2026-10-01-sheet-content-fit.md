# Content-sized bottom sheets — 2026-10-01

## Scope

Worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`.
Branch: `product/social-calls-v3`, starting at clean `f92b1b6`.
Presentation-only follow-up to the shared-sheet/typography change. No API,
schema, credentials, session logic, trading settings or production deployment.
Original dirty checkouts and recovery files were not touched.

## Reference and changes

Found and visually inspected the three saved Irfan inspiration images in
`assets/images/open_sourced_design_inspiration/irfan/`. The original X post
was not located/verified. The design-system and design-critique skills guided
the reference comparison and component-level correction: purposeful spacing
between groups, then a small inset after the final action, not empty height
reserved by screen percentage. Current fonts, colors and scalloped wave stay.

- `chumbucket_wavy_sheet.dart`: content-sized Column, loose Flexible body,
  available-height constraint. Optional `maxHeight` replaces fixed `height`.
  Safe area, keyboard offset, dismissal guards and one shared close remain.
- Call composer/response, social receipt and rematch: shrink-wrapping scroll
  regions with actions following the actual content.
- Market picker, Panta review/status, private wallet, Add Friend, notifications
  and caller sheets: shrink-wrapped lists/slivers; no screen-fraction height.
- Profile/settings/export notices, send/receive wallet, avatar selection,
  friend selector, witness challenge and challenge receipt: removed forced
  expansion and surplus bottom spacers; normalized key content/action insets.
  The bounded friend wheel follows row count (maximum three), not phone height.
- Challenge descriptions now wrap fully instead of truncating after three lines.
- Added `test/chumbucket_sheet_content_fit_test.dart`; expanded sheet-system
  tests to keyboard + 2x text; fixed a rematch test's ambiguous scroll target.
  Visual harness awaits actual avatar decoding instead of capturing blank tiles.
- Updated `docs/design/sheets-and-type.md` with reference links and usage rules.

## Verification

- `flutter analyze --no-pub`: **No issues found**, exit 0.
- `flutter test --no-pub --concurrency=2`: **1,060 passed / 35 skipped / 0 failed**,
  exit 0, 62 seconds. Previous baseline: 1,039 / 35 / 0.
- New content-fit tests: **10 passed**. Covers three phone heights, ceiling
  semantics, dynamic grow/shrink, last-row scrolling, keyboard-clear actions,
  menu/selection padding and shrinkage after a fake friend submission.
- Added **11** keyboard/2x-text cases for existing sheet variants.
- Focused call/trade/friend/sheet/profile run: **69 passed**.
- Opt-in real-font captures: **24 passed**, including 390dp/1x and 320dp/2x.
  These are the same 24 opt-in skips in the normal suite; no extra skip introduced.
- First full run: 1,059 passed / 35 skipped / 1 failed. The rematch test matched
  both outer-list and editable-text Scrollables after shrink wrapping. Narrowed
  its target to the outer list and added a hit-testability assertion; all 19
  rematch tests and the subsequent full run passed. No assertion was removed.
- Android debug APK **1.0.16 (16)** built successfully and installed in place
  on the Seeker. No uninstall/data clear. Existing Gradle/Kotlin migration
  warnings remain; no dependency/toolchain upgrade is part of this change.
- APK path inventory contains no `.env`, `env.local.json`, Firebase Admin /
  service-account JSON or keypair JSON. Existing public-define allowlist reused.

APK SHA-256:
`e072dd7ec26802414a55c042e9f3d4a521b17afeb8a6c82985f0b49da520b7c5`

Signer certificate SHA-256 (unchanged):
`95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`

## Evidence and boundaries

Private logs/device captures:
`/private/tmp/chumbucket-sheet-fit-20261001.W2J7C9/`.
Reproducible fixture captures: `/tmp/chum-sheet-*.png`.
Build log: `/private/tmp/chumbucket-ui-seeker-20261001.rljrp6/build-code16.log`.
Actual device screenshots remain outside git because they contain account UI.

Device check: existing profile/friends survived. Add Friend has no long empty
tail; with the real keyboard open its content and action remain above it and
below the status bar. Account & Support also ends just below Sign Out rather
than leaving a screen-height spacer. No friend request, profile save, signature or trade was
submitted. Account linking/public call record remains in its pre-existing
unconnected state; authenticated call/receipt/trading states were verified by
fixtures, not by creating live data.

Next checkpoint: review remaining screen-level spacing against the same saved
references. This checkpoint does not claim full production/backend readiness.
