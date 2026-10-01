# Compact market rows and public-catalog census — 2026-10-01

## Scope

Worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`, branch `product/social-calls-v3`.

The user asked to make the market widget smaller, remove repeated provider/unit copy, and establish whether Panta really has only six current markets. This checkpoint changes presentation only. No API deployment, database migration, credential change, account mutation, wallet approval, or trade is involved. Original dirty checkouts remain untouched.

## Design change

The design-critique and mobile checks led to reducing repeated decoration rather than truncating settlement questions or reducing tap targets:

- One legible `Powered by Panta · Prices in USDC/share` legend per catalog surface (Markets, picker, and the existing alternate Home market list), not per row.
- Remove the identical decorative pie icon; let each full question use the row width.
- Question 18 → 16 logical pixels, vertical row padding 16 → 12, question/date spacing 6 → 4, price spacing 12 → 8, chip vertical padding 8 → 6.
- Keep full questions, original font families/colors, independent exact decimal strings, missing-price states, stale warnings, and detailed attribution/units on market detail. Screen-reader price text retains units and indicative status.
- No market filters or provider selection changed. All categories/dates remain the default.

Panta's [API Terms of Use, §6](https://docs.panta.market/guides/terms-of-use) require the exact attribution wording and permit placement at the relevant market module or integration screen. They do not specify repetition on every catalog row. We retain the wording at module level, rather than remove or obscure attribution.

## Catalog evidence

Read-only checks used the existing server-held live key in memory. No credential values, raw environment output, or opaque cursors were logged. Requests were paced, without category, phase, or `createdBy=me` restrictions.

At **2026-10-01 01:06:22 UTC**, following `nextCursor` through both pages returned:

| Observation | Count |
| --- | ---: |
| First page / second page | 50 / 36 |
| Unique registry market IDs | 86 |
| Closing time in the past | 80 |
| Unknown closing time | 0 |
| Not yet closed | 6 |

At **01:06:38 UTC**, Chumbucket's `predictions.catalog` returned 13 cached normalized rows (no further cursor). Six were both `OPEN` and not past close. Their ID set **exactly matched** the six upstream candidates: zero missing, zero extra. One other cached `OPEN` row had already passed close and is correctly excluded by the mobile discovery filter.

The six current questions concern Brent oil, Steelers/Browns, the $JUMP token sale, Big Brother Naija, GTA 6, and BTC at $100,000. Thus six is not an artificial six-row cap or the old crypto/date restriction.

Important limits:

- Panta documents this endpoint as a [public USDC registry, not a full-chain scan](https://docs.panta.market/api-reference/markets/list). This is a count of the current exposed registry, not a claim about every market anywhere on Panta or Solana.
- Detail hydration is inconsistent. On the first pass, five of six detail responses lacked title/rules/on-chain state; on the second, two lacked them. The affected IDs varied. The BFF retains previously obtained complete metadata. No fabricated question, rule, price, or resolution was substituted.
- Registry phase labels also differed between reads. The census uses explicit closing timestamps; it does not treat a catalog phase as authoritative settlement evidence or proof that a trade will fill.
- This check did not quote, build, sign, submit, or claim a position.

Private read-only census evidence: `/private/tmp/chumbucket-compact-catalog-20261001.mxUSqM/census-summary.jsonl`.

## Verification

- `flutter analyze --no-pub`: exit 0, **No issues found**, 18.8 seconds.
- Initial focused run: **35 passed / 1 failed**. The new density regression exposed the row stretching to its parent's available height outside a list; fixed with `mainAxisSize: MainAxisSize.min`.
- Final `flutter test --no-pub`: exit 0, **1,004 passed / 11 skipped / 0 failed**, 3m14s. Four new tests cover one attribution per catalog/picker, row density and semantics, and an untruncated long question at 320dp/2× text. Existing skips remain; this is not a claim that skipped checks ran.
- Opt-in `ui_market_layout_visual_test.dart`: **4 passed / 0 failed**, 6 seconds. Reviewed real-font 390dp/1× and 320dp/2× captures. Small-screen/large-text content remains scrollable.
- `dart format --output=none --set-exit-if-changed` (five Dart files): exit 0, no changes. `git diff --check`: exit 0.
- Debug APK build: exit 0, Gradle step 125.4 seconds. Existing Gradle/AGP/Kotlin future-support warnings remain; no dependency upgrade was mixed into this task.
- APK package `dev.cleva.chumbucket`, **1.0.14 (14)**. SHA-256 `4a3d7a9ff97cf2e5d00e8c03db9a3a1553e7384757bd5f674dfa5e3a22913c70`. Signing certificate SHA-256 `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`, unchanged from the installed build. Packaged-file inventory: **0 forbidden secret filenames**; no secret contents opened or logged.
- Seeker `SM02G40619141343`: `adb install -r` succeeded, package manager confirmed code 14 at **02:11:39 Africa/Lagos**. No uninstall/data clearing. Other connected device untouched.
- Physical checks at normal font scale: Markets shows the compact full questions and independent price chips; all six questions are reachable by scrolling; opening Brent leads to its original full detail/rules/attribution surface; Back returns to the catalog. No call or trading action submitted. Left on Markets with All dates and Crypto only off.
- Private screenshots/logs: `/private/tmp/chumbucket-compact-catalog-20261001.mxUSqM/`. Screenshots are not committed.

Files changed: `call_market_card.dart`, `call_markets_screen.dart`, `market_picker_sheet.dart`, `predictions_home_tab.dart`, `test/ui_market_layout_discovery_test.dart`, and this checkpoint.

Remaining risk/next work: provider detail hydration reliability is a separate backend concern. The unchanged market-detail view still wraps long decimal prices in its large number tiles; a subsequent detail-density pass should address that without rounding away execution-relevant values. This catalog presentation change does not establish funded-trading readiness or resolve the existing identity/portfolio/inbox gaps documented in earlier checkpoints.
