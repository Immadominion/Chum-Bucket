# Screens aligned to the layout prototype — 2026-10-01

## Scope

Markets, market detail, the Home call card, the shared content tabs and the
Profile account prompt, set against Codex's approved layout prototype
(`chum/docs/design/2026-09-30-chumbucket-layout`, frames 01–03 and 07 plus the
interactive Market detail scene). Values were taken from the prototype's
`style.css`/`readability.css`, not estimated from screenshots.

## Changes

| Surface | Change |
| --- | --- |
| Market rows | 36dp tinted glyph (₿ / Ξ / S, `$TICKER` initial, or a category icon), question at the prototype's 16/800 (`AppTextStyles.marketRowQuestion`), 18/15dp row padding, 14dp to aligned YES/NO cells with 14sp figures. |
| Prices | Rows and detail figures read at two decimals (`CallsFormat.displayPrice`), rounded half-up on the decimal string, never through a double; a positive sub-cent price reads `<0.01`. Market and call detail add the exact venue string whenever rounding changed a figure. Quotes, trade review and the receipt keep full precision. |
| Markets header | Borderless search, outline chips (6dp apart), a "Make your next call" heading with a compact `Crypto only` toggle, one Panta/units legend. Default stays All dates. |
| Market detail | Glyph · category · status head (open green, waiting amber, settled neutral), one price caption with freshness, a stated resolution line with the venue's raw source inside the expanded rules, the community-split gate as a grey lock note. |
| Call card | Person → side pill · close · free-call badge → question (20/800) → reason → one lock-stamp line → equal Back / Fade outline actions. Demo, followers-only, outcome and funding badges are unchanged in meaning. |
| Tabs | `ChumbucketTabs`: Machina 14, muted inactive, 800 active, underline spanning the word; every tab still ≥48dp. |
| Profile | The record explanation shows only when there is a record; "Connect your existing account" appears once, in the Calls tab, instead of above the tabs and again inside them. |
| Nav | Markets uses the pie icon and Friends the people-chat icon, as in the prototype. |
| Call detail | Follow beside the name; green side pill with "Free call · locked"; 14sp reason; a right-aligned evidence list with readable UTC times and the entry price rounded beside its exact venue string; "View market & rules" as a text link; share in the app bar; your own call opens on a green "You're on record" banner. |
| Receipt | The sheet has one brand header: the receipt's own centred hero ("Called it.") meets the sheet's corners, so the shared image is exactly what is on screen. Readable facts first; a "Proof" section keeps every exact field (ISO timestamp, exact prices, price record, resolution reference). The title stays the sheet's accessible heading. |
| Choices | A chosen YES is green with a check, NO slate; Back/Fade take the side they lock; other choices select in ink. Pink is left to the call to action. |

## Deliberate departures from the prototype

- Metadata and chip labels stay at 12sp, not the board's 11px (rule 1 of
  `docs/design-audit-2026-10-01.md`); search text is 13sp.
- One Panta attribution legend per list rather than a caption under every row.
- Audit rule 3 ("preserve exact price strings") is kept by placing the exact
  venue strings on market and call detail; list rows round for reading only.

## Verification

- `flutter analyze`: no issues. `flutter test --concurrency=4`: 1,090 passed,
  40 skipped (opt-in captures), 0 failed. New: `calls_format_price_test.dart`.
  Updated tests keep their intent (rendered ≥48dp touch targets, exact prices
  asserted on detail, named question roles); `goldens/ui_home.png` re-baselined
  after checking the diff was only the redesigned card, tabs and nav icons.
- Opt-in side-by-side captures: `ui_markets_reference_capture_test.dart`
  (`CAPTURE_MARKETS_REFERENCE`) and `ui_feed_reference_capture_test.dart`
  (`CAPTURE_FEED_REFERENCE`), written to `/tmp`.
- Call detail and receipt verified from renders against frames 04 and 06; the
  device account has no calls, and none was created to look at one. Debug
  1.0.25 is installed; the shared sheet (Link Google) was opened and dismissed
  without continuing.
- Seeker, debug 1.0.24 built with `--dart-define-from-file=env.local.json`
  (people-first shell, devnet, BFF); no env file in the APK. Checked Markets,
  a live Panta market's detail, Friends and Profile on the existing account.
  No call, friend request, signature or trade was submitted.

## Observed, not changed

Live Panta prices on the BFF were ~14 minutes old at 18:29 UTC, so rows and
detail correctly showed "stale or incomplete" (10-minute usability window).
Whether the price refresh cadence is as intended is a backend question.

## Open decision

Coral buttons keep white labels (sheet reference comp, ~3.6:1 on #FF3355); the
prototype uses dark ink for contrast. Not changed without a decision.
