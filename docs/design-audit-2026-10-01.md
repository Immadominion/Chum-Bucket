# Whole-app design audit — Chumbucket

## Verdict

The web draft is cleaner because it has a consistent density and reading order.
The native build reused the brand, but not that discipline everywhere: repeated
headings, large wave headers, nested price boxes and implementation-status prose
consume the space the predictions and people should occupy. The prototype also
uses populated fixtures; the phone has real empty/error/unlinked-account states.
Those states must be designed properly, not disguised with invented activity.

Keep the coral, PP Neue Machina headings, Montserrat body, illustrated avatars,
wave motif and four destinations. The icon library is not the root problem.
Existing Basil icons already match the approved draft. Icons8 is permitted, but
no new icon pack was imported in this pass; any future asset needs compatible
licensing/attribution and a consistent stroke/size family.

## Evidence and limits

- Compared the approved `chum/docs/design/2026-09-30-chumbucket-layout` prototype
  with real Flutter captures in `docs/ui-review-2026-09-30`, current widget code,
  navigation wiring and regression tests.
- Reviewed all primary destinations and their secondary journeys below, not
  merely Home. Distinguish a reachable route from a finished backend capability.
- Physical Seeker verification for this increment is recorded in the linked
  checkpoint. Previous build 1.0.12 evidence remains historical, not proof of 1.0.13.
  The [1.0.13 checkpoint](checkpoints/2026-10-01-panta-catalog-and-friends.md)
  records actual catalog, friend input, account continuity, Settings and Inbox checks.
- Signed-in call creation, actual trading, first-run OAuth, destructive account
  actions and external sharing were not executed against the live account for
  this audit. Fixture tests cannot substitute for those device approvals.

## Findings by complete journey

| Journey / evidence | Finding and severity | Disposition |
| --- | --- | --- |
| Entry / existing wallet / Google linking (`mwa_login_screen`, `call_sign_in`, `identity_link_sheet`) | **Blocker:** wallet identity and call-session readiness remain separate. The link sheet still has a tall older header; generic “no wallet needed” copy conflicts with recovery of an existing wallet profile. The current production link capability was disabled at the prior checkpoint. | Preserve the existing profile; never insert Create Profile into recovery. Capability/copy must be reconciled before claiming the free loop works for this account. No auth bypass in this pass. |
| Root shell / back / deep link | Four stable destinations and visible labels are appropriate. Previously fixed nested Home navigation and 2× label clipping should not return. | Retain routing and selected-tab continuity. Full regression suite includes these guards. |
| Home / Following / Global / empty/error | **Major:** repeated free-call/provenance/status rows compete with the question; empty and unlinked states dominate real sessions. Draft hierarchy is person → question/side → reason → actions. | Keep honest provenance but consolidate metadata; don't fill empty live feeds with fixtures. Current pass does not pretend to have finished this further density work. |
| Markets / search / filters (`call_market_card`, `call_markets_screen`, BFF) | **Blocker:** discoverability was coupled to fresh price availability, then restricted again to crypto and 4 hours–7 days. **Major:** tall nested YES/NO boxes and redundant hero copy reduced visible questions. | **Fixed in this increment:** separate cached catalog, all categories/dates by default, optional Crypto/Ending soon/This week, compact price chips, remove redundant hero. Missing prices stay explicit; unsupported live venues remain excluded. Default list shows open predictions, not historical settled rows. |
| Market detail / rules / source | **Major:** full question is right, but expanded price blocks, generic rule-introduction text and a raw source URL overfill the first screen. Exact rules must remain available. | Next: compact summary hierarchy and a source disclosure; do not invent a rules summary or hide settlement terms. No fake chart. |
| Make call / market picker / keyboard | **Major:** two headings plus lengthy explanation push the action down; picker previously repeated the restricted discovery windows. | Picker now starts with all dates and all categories, retaining per-market composer validation. New friend sheet demonstrates smaller hierarchy; migrate other sheets deliberately, with keyboard/large-text tests. |
| Call detail / Back / Fade / Challenge | **Major:** author/follow wrap, raw timestamp and stacked metadata make a simple opinion feel administrative. Preserve immutable side/reason and the resulting-own-call route. | Keep exact time available, prefer compact visible time with a detail disclosure. Challenge must remain an invitation, not hidden escrow. Covered with fixture journey tests; no live call submitted here. |
| Receipt / private disclosure / share export | **Major:** sheet wave plus receipt wave doubles chrome; required provenance crowds the result. Existing demo/private safeguards are essential. | Make the exported receipt the visual focal point; reduce surrounding chrome, not evidence. No real private receipt was shared during audit. |
| Friends / Following / invitations | **Major:** Friends and Following represent different data, but Following is only people represented in returned followed calls, not a complete directory. Invitations have unfinished accept/decline semantics. | Retain the original friend graph. Do not relabel a feed sample as a complete following list; complete that contract separately. |
| Add Friend / wallet / X / domain | **Major:** asking the user to choose Wallet/X duplicates information already in the input. Required nickname and large header add friction. Domain resolution could race; old pending-handle success copy overpromised notifications. | **Fixed:** one detecting field, optional nickname, supported names/profile URLs, stale-resolution guard, existing signed X proof, self/account-change/duplicate-submit guards, retryable errors and honest pending confirmation. No production friend was added for testing. |
| Profile / record / Calls / Positions / Challenges | **Major:** identity, wallet row, record panel and long explanation push calls below the fold. **Blocker:** Positions is explicitly unavailable rather than an implemented portfolio. | Keep name/avatar/history and Edit route. Next reduce top-card height, compress record copy, and expose account-repair status as a concise row. A new portfolio needs real holdings/order/claim contracts, not a painted balance. |
| Edit Profile / avatar / cancel | Original flow continuity is more important than a new form. Recent cancel/save-pop and draft protections are already fixed. | Preserve; rerun full continuity tests. Do not replace existing identity or restart onboarding. |
| Activity / notifications / read state | **Major:** two inbox implementations exist. The shared bell opens `ArenaNotificationsScreen`; the new calls inbox is separate. Old CLAIM_AVAILABLE opens My Pots. A single bell therefore does not establish a unified Panta/calls return loop. | Reconcile source, targets and unread state before presenting unified Activity. Don't silently discard old notifications or reroute claims to an unrelated Panta position. No mark-read writes for this audit. |
| Settings / wallet details / Add SOL / support | **Major:** older 180–220dp headers and white-on-coral small text conflict with compact dark-title sheets. There are both `SettingsBottomSheet` and `ProfileSettingsSheet`; some dead/no-op actions exist in the former. | Consolidate **reachable** variants after tracing entry points, not bulk-deleting “legacy” files. Preserve balances, Add SOL, support and disconnect semantics. Don't change chain/funding to make a screen look populated. |
| Trade review / wallet approval / uncertain submission | Critical information is present, but review uses another header variant and lengthy status prose. The controller correctly distinguishes pending from filled. | Keep quote expiry, fees, chain, side and signing decision explicit. Standalone Trade still needs an owned call; sell/claim/portfolio remain incomplete. No money movement or signed trade in this pass. |
| Existing challenges / details / history | This is user history, not disposable “legacy”. Older 24sp headers and screen-specific spacings differ from prediction detail. | Preserve history and callbacks, align chrome later without rewriting challenge business logic. |

## Cross-app design rules for the next increments

1. Root heading 24–28sp; secondary heading about 20–22sp; body 14–16sp;
   metadata at least 12sp. Do not copy the web board's compressed 11px text.
2. One primary heading per sheet, one scrolling body, one clear action area.
   Header sizing follows actual scaled text, not a fixed decorative 200dp slab.
3. Flat feed/catalog rows; no card inside a card merely to display two numbers.
   Preserve exact price strings and say USDC/share, never inferred probability.
4. Put implementation explanations behind a concise state/action. Do not bury
   the useful action beneath paragraphs about capabilities the user cannot use.
5. Keep 48dp actions, 320dp/2× text support and keyboard reachability. Never
   “fix” density by disabling text scaling, truncating settlement questions or
   shrinking all text.
6. Confirm each journey with existing-account state, populated fixtures,
   empty, loading, offline, refusal and retry. Compare handset screenshots to
   the draft before calling a pass complete.

## Panta: actual API cause, not a design excuse

`predictions.listEvents` returned HTTP 500. A safe read-only upstream probe
confirmed a 134-character opaque cursor; our adapter demanded a Solana address.
The cached call-ready list continued to return two markets, masking the broken
catalog walker. The corrected adapter accepts bounded opaque cursors, not
arbitrary market IDs, and syncs every category with its own continuation.

The new `predictions.catalog` returns normalized stored markets without requiring
a price. Panta documents that [list prices are null by design](https://docs.panta.market/api-reference/markets/list)
and [detail prices depend on RPC availability](https://docs.panta.market/api-reference/markets/get).
Missing prices do not mean there are no predictions. They still prevent locking
a call/trade wherever the existing validation requires current evidence.

The design-critique checks determined the hierarchy/density findings; mobile-build
checks require actual device evidence. The deployment checklist kept the catalog
rollout scoped and reversible. None of these checks certifies the unfinished
authentication, portfolio or funded-trading journeys as production-ready.
