# Native UI checkpoint — approved Chumbucket layout

Implemented in the existing Flutter app, not a parallel app. [Open the actual-widget screen gallery](index.html).

**1 October follow-up:** the analyzer is now clean (zero findings), and the suite passes **960 tests, 11 skipped, 0 failed**. See the [lint cleanup and regression-test record](lint-follow-up-2026-10-01.md). The original UI verification below is retained as historical evidence.

**Latest device checkpoint:** **1.0.12** is installed on the Seeker with the existing account preserved. Profile-edit routing, system-bar contrast and large-text navigation were corrected; **972 tests pass, 11 skipped, analyzer clean**. See the [device evidence, artifact hashes and remaining authorization/Panta blockers](../checkpoints/2026-10-01-seeker-ui-continuity.md). This does not establish funded-trading readiness.

## Workspace and scope

- Worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`
- Branch: `product/social-calls-v3`
- Starting commit: `7754c3c550cf8feaf9e8fd118f2b33b3f7303482`
- Implementation commit: `6b41f4e` (`feat(ui): implement people-first Chumbucket layout in existing shell`).
- Design reference: `/Users/mac/Documents/codes/projects/chum/docs/design/2026-09-30-chumbucket-layout/README.md`
- API, models, repositories, authentication/wallet implementations, database migrations, dependencies and production configuration were not changed.
- Original dirty checkouts were not edited. No push, deployment, production call, wallet approval or device installation was performed.

The existing `CALL_RECEIPT_EXPERIENCE=true` build flag selects Home/Markets/Friends/Profile. The rollback shell remains behind the existing false setting; this pass does not silently change release bootstrap. The repository factory/configuration is unchanged.

## Implemented

| Surface | Changes |
| --- | --- |
| Shell | Home is the call feed; Markets is the second tab. Friends/Profile retain their indices. Visible labels, selected-state semantics, preserved history/deep-link routes. |
| Home | Quiet header, Following/Global, compact Call action, person-first cards, equal Back/Fade actions, immutable entry stamp, contextual real receipt. Following-empty leads to Global. |
| Call journey | Author and follow state, full thesis, exact lock timestamp, separate Back/Fade review, explicit YES/NO, audience, draft/error preservation and duplicate-submit protection. Successful responses open the resulting own call. |
| Markets | Search and Ending soon/This week filters; objective crypto window of 4 hours–7 days; independent USDC/share prices; Panta attribution and freshness. Missing, stale, paused and expired states stay explicit. |
| Market detail | Full question, closing time, expandable exact rules/source, gated community opinion, separate call/trade affordances. No invented charts or rule summaries. |
| Receipt | Pink wave, original person/side/question/thesis/evidence; correct/incorrect/void/pending copy. Demo marking is inside the export. Followers-only image export requires an explicit disclosure decision; unknown visibility permits only a link. |
| Profile | Joined existing identity/record panel, edit/settings continuity, private My wallet row, Calls/Positions/Challenges. Wallet balance and Add SOL remain in the existing private flows. No returning-user Create Profile prompt. |
| Friends | Original illustrated grid and friend actions, Friends/Following separation, contextual free invitations. No PnL leaderboard. Following view says it comes from recent followed calls, not a complete directory. |
| Trade review | Existing controller and guards, clearer private review, exact economics supplied by the quote, expiry, wallet/chain, submitted/partial/confirmed states and reconciliation actions. |
| Shared components | Existing coral, PP Neue Machina/Montserrat, Basil icons and wave sheets. Asset-backed avatars, readable status colors, 48dp actions and scrollable large-text empty states. |

## Actual verification

Baseline, before edits:

- `flutter test --reporter compact`: **888 passed, 7 skipped, 0 failed**, exit 0.
- `flutter analyze`: **274 info-level issues**, 0 errors/warnings, exit 1.

Final integrated source:

- `flutter test --no-pub --reporter expanded`: **947 passed, 11 skipped, 0 failed**, exit 0. The extra four skips are opt-in market visual captures; all four were run separately and passed. The seven pre-existing skips remain.
- `flutter analyze --no-pub`: **255 info-level issues**, 0 errors/warnings, exit 1. Analysis is not lint-clean; it has 19 fewer existing-style issues than baseline.
- `git diff --check`: clean.
- Android debug compile with `CALL_RECEIPT_EXPERIENCE=true` and `CALLS_BACKEND=mock`: successful. This is a compile-smoke artifact, not a configured production/test-account build. No `.env` asset was found in its APK file inventory. Existing Kotlin/Gradle plugin migration warnings remain.
- Real-widget captures reviewed for Home, Markets, market detail, call detail, composer, receipt and Profile. Synthetic fixtures only; no captured real account content.
- Narrow-layout coverage includes 320/390/430dp where applicable, 2× text, keyboard insets, feed→Fade→own call, rules, price provenance, follow errors, private sharing, settings/edit, connected wallet→Add SOL, old histories and sign-in hand-off.

Relevant test additions: `ui_home_layout_test.dart`, `ui_call_journey_layout_test.dart`, `ui_market_layout_{discovery,trade,visual}_test.dart`, `ui_people_layout_{profile,friends,continuity,visual}_test.dart`. Existing flow, receipt, notifications, analytics and Panta tests were updated to use the new controls while retaining their behavioral assertions.

The screen gallery is not a Seeker run or TalkBack audit. Physical-device layout, accessibility, wallet return and live-account/backend reconciliation remain unverified in this UI pass. No successful trade is claimed.

## Deferred contract work — deliberately not faked

1. **Standalone trade entry:** the existing trading API requires an owned call. Market detail explains that limitation; an owned Panta call opens its existing private review. A new direct trade route needs backend work.
2. **Positions:** Profile explicitly says the Panta positions view is unavailable. Confirmed holdings, pending orders, sell/close/claim lifecycle and authoritative balances are not simulated.
3. **Activity:** the header preserves the existing working inbox route. A unified new-call/order inbox and durable unread receipt tracking need reconciliation. Home's receipt nudge references an actual returned resolved call; it does not invent “new” or unread status.
4. **Saved markets / directories:** Saved is omitted. Following lists people represented in returned followed calls, not an asserted complete graph. Complete directories and saved-market persistence need contracts.
5. **Records / invitations:** shown public-call record uses available entries with correct/decided/pending/void scope; no invented lifetime stats. Invitation accept/decline/expiry is not represented as working.
6. **Trade economics:** missing max-total-spend and SOL fee estimates are named as missing, not calculated from fictional assumptions. Rules use exact supplied text; no fabricated summary or resolution.
7. **Release gates:** production auth recovery, data/visibility enforcement, provider eligibility, full trade lifecycle, device validation and the previously documented exposed-credential remediation remain separate work.

## Capture reproduction

```sh
flutter test --no-pub test/ui_home_layout_test.dart
flutter test --no-pub --dart-define=UI_CALL_JOURNEY_CAPTURE=true test/ui_call_journey_layout_test.dart
flutter test --no-pub --dart-define=CHUM_PEOPLE_CAPTURE=true test/ui_people_layout_visual_test.dart
```

The design-taste and mobile-build checks kept the work tied to the existing brand/components and to explicit mobile/error/privacy states. They did not expand this task into backend or auth changes.
