# Seeker UI continuity — 1 October 2026

## Outcome and scope

The approved layout is installed on the Seeker as **1.0.12 / code 12**. This is
a debug UI-review candidate, not a store release or a claim of working funded
trading. The existing profile, connected-wallet state, friends and original
challenge history remain present. No uninstall, app-data clear or new profile
was used to get the layout running.

Worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`

Branch: `product/social-calls-v3`. Started clean at `e49dfc6`.

Code commits:

- `ed1bf43` — preserve profile edit flow and readable system bars.
- `143e098` — keep bottom navigation labels readable at large text.

The mobile-build checks prompted physical-device navigation, large-text and
cold-start verification. No new design direction, scaffolding or telemetry was
introduced. Original dirty checkouts and the API worktree were not edited.

## Device findings and changes

1. **Light status-bar icons survived the splash on a light Home screen.** The
   shell now declares its system-bar styling through `AnnotatedRegion`, so
   custom-header tabs restore dark icons when they become visible again.
2. **Existing-profile editing was still behaving like first-time setup.** It
   said “Complete Your Profile”; cancel and save constructed another Home
   screen and completed onboarding. Existing edit now says “Edit Profile” and
   pops back to the original Profile route. Only required first-time setup
   retains the onboarding completion path.
3. **Profile fetches exposed an editable blank form before loading finished.**
   Loading/error states now prevent writes, provide retry, and preserve drafts
   on save failure. Saving checks the loaded wallet against the current session,
   rejects duplicate submissions and whitespace-only names, and checks mounted
   state after asynchronous operations. The existing profile update RPC and
   server authorization were not changed. Removed the screen's raw profile log.
4. **At Android font scale 2.0, “Markets” wrapped its last letter in the bottom
   bar.** Labels now remain single-line and fit their own tab width, with equal
   line boxes for icon alignment. Text can grow until the available label width
   is exhausted; body text is not clamped. Full semantic labels and tap targets
   are retained.

Changed implementation files:

- `lib/shared/screens/home/home.dart`
- `lib/features/profile/presentation/screens/edit_profile_screen.dart`
- `lib/shared/screens/home/widgets/chumbucket_bottom_navigation.dart`

Changed tests/evidence:

- `test/call_home_screen_test.dart` — two real system-overlay regressions,
  including all four tabs and returning from an opposite-style detail route.
- `test/edit_profile_flow_test.dart` — ten tests covering loaded data, cancel,
  successful/duplicate save, pending load, null/throwing fetch with retry,
  rejected/throwing save, account switch, disposal and required setup validation.
- `test/ui_people_layout_continuity_test.dart` — actual Profile → Edit → Cancel.
- `test/ui_home_layout_test.dart` — rendered text selection boxes must be one
  line, fit within the semantic tap target, and remain selectable at 320dp/2×.
- `test/goldens/ui_home.png` — reviewed normal-size nav-label raster adjustment;
  the initial diff was 386 pixels / 0.12%, confined to those labels.

## Actual verification

- `flutter analyze --no-pub`: **No issues found**, exit 0.
- Focused edit/home/continuity tests: **30 passed, 0 failed**, exit 0.
- Final `flutter test --no-pub --reporter expanded`: **972 passed, 11 skipped,
  0 failed**, exit 0, 26 seconds. The same seven existing skips and four opt-in
  visual captures remain. No test was disabled by these fixes.
- System-bar tests failed before the fix (2 failures). The strengthened
  large-text nav assertion also failed before its fix. Both pass afterward.
- `flutter build apk --debug --no-pub --target lib/main.dart
  --build-name=1.0.12 --build-number=12 --dart-define-from-file=<private-public-defines>`:
  exit 0. No dependency or lockfile changes.
- `git diff --check`: clean.

Observed on the real handset during the code 10 → 11 → 12 corrective sequence:

| Flow | Observed result |
| --- | --- |
| In-place update from previously installed code 9 | Existing profile, avatar, bio, friends and wallet connection preserved |
| Home / Markets / Friends / Profile | Four destinations reachable; no football Matches destination in the new primary layout |
| Markets → Panta market | Real short-dated market, independent YES/NO venue prices, attribution, timestamps and rules section rendered |
| Make a call → Link Google → Continue (code 11) | Explicit linking-unavailable message; no OAuth or wallet approval screen, no new profile |
| Profile → Edit → Cancel (rechecked on code 12) | Existing fields loaded; returns to the same Profile tab and preserves its selected subtab |
| Friends (code 11) | Existing five connections displayed |
| Profile → Settings (code 12) | Original Account & Support sheet reachable; no destructive action selected |
| Profile → Challenges → Challenge history (code 12) | Original records displayed; no claim/refund/transaction selected |
| Font scale 2.0 (code 12) | Home controls and nav labels intact; market YES/NO, attribution and footer fully reachable by scrolling |
| Force-stop and cold launch (code 12) | Home loads with readable system bars; existing profile and connected wallet return without onboarding |

Original Android font scale **1.0** was restored and read back. Personal
screenshots stay outside Git. No real profile save, follow, call, trade, claim,
refund, signature or wallet approval was submitted. Successful edit saves were
tested using a fake provider, not by changing the user's production profile.
This is not a TalkBack audit or complete live end-to-end trading test.

## Installed artifact and recovery

- Package: `dev.cleva.chumbucket`; final version **1.0.12 / 12**.
- Source commit: `143e098` (clean tree at build time).
- Device-reported update time: `2026-10-01 01:07:51`.
- Original first-install time remains `2026-07-17 22:20:21`.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- SHA-256: `80fa08fefd63bf1a649b6689fd66cde58df7a142ea3e1e9ecab2fc496be358fb`.
- Signer SHA-256: `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`,
  verified to match the originally installed candidate before replacement.
- Original code-9 APK backup:
  `/private/tmp/chumbucket-ui-seeker-20261001.rljrp6/installed-code9.apk`.
- Backup SHA-256: `d8e4ea6eaa40496bb2fe059038c26e99c50b67678dc8fdca1640f2377f210011`.

Build configuration was generated privately from an explicit allowlist: public
Supabase URL and anon/publishable key (rejecting privileged roles), existing
Arena and calls-BFF URLs, `CALLS_BACKEND=bff`, the existing social-wallet
`SOLANA_NETWORK=devnet`, `CALL_RECEIPT_EXPERIENCE=true`, and
`CHUMBUCKET_EXISTING_PROFILE_ONLY=true`. It did not copy the entire local config.
Panta market data comes from the live calls BFF; the wallet network setting is
not proof of funded Panta execution. No provider/server keys were added.

APK filename inventory found zero `.env`, `env.local.json`, Admin-service-key,
keypair or keystore assets. This is an asset-path check, not a comprehensive
binary secret audit or closure of the earlier credential-remediation gate.

Private screenshots, build/test logs and the build helper are in the same
temporary directory as the APK backup. These temporary files are diagnostic
evidence, not a durable account-data backup. No app data was extracted.

## Remaining blockers and next packet

**Existing-account authorization is still the primary blocker.** Read-only
`auth.identityStatus` returned HTTP 200 with identity enabled and
`existingAccountClaimsEnabled=false`. The old wallet/profile being visible
does not authorize a new canonical-person session. The handset confirms the
preflight refusal. Do not enable the flag or seed ownership from a mutable
wallet mapping simply to bypass this screen. The outstanding ownership evidence
and rollout are described in
[the existing-account checkpoint](2026-09-30-seeker-existing-account-continuity.md#remaining-blocker-and-next-packet).

**Catalog availability varied during this session.** Initially `markets.open`
returned only an OPEN crypto market about 91 days away, outside the approved
4-hour–7-day window, so the empty UI was accurate. A subsequent HTTP-200 read
returned two Panta markets, including one closing in approximately 37 hours;
that market then rendered on-device. No fake content, alternative venue or
relaxed time filter was introduced. Investigate discovery/price availability
during backend reconciliation rather than treating one successful fetch as
proof of stability.

The [deferred UI/backend contracts](../ui-review-2026-09-30/README.md#deferred-contract-work--deliberately-not-faked)
still apply: direct trade without an owned call, positions/sell/claim, unified
activity, complete following directories, lifetime records, invitation state
and missing trade economics. Funded execution and credential remediation are
not complete. No backend was deployed, production database changed, credentials
rotated, provider contacted or commit pushed in this pass.

Next packet: user review of the installed UI, then existing-person authorization
and Panta contract reconciliation. After ownership is established safely,
prove the same-account free-call/Back/Fade/receipt journey on the handset before
any separately approved funded trade test.
