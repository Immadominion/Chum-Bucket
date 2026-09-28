# Repair checkpoint 1 — app continuity and account isolation

Date: 28 September 2026. Local changes only; not a release sign-off.

## Scope and working copies

- Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
  branch `product/social-calls-v3`, started at `b1cf776`.
- API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
  branch `product/social-calls-api`, unchanged at `a85e3f8`.
- Original checkouts were not edited. Read-only status counts still match the
  recovery inventories: canonical mobile 20, reference 138 with `-uall`
  (122 collapsed entries), original API 1. The reference's 104 archived files
  are not its status-entry count.
- No push, deployment, production database change, credential operation,
  wallet transaction, or device installation was performed.

## Changes actually implemented

### Account-boundary regression fix — commit `c225716`

- `lib/features/calls/providers/calls_provider.dart`: invalidate pending reads,
  writes and their error/finally handlers when the viewer changes. An old
  response cannot repopulate the new account's feed, details or invitations,
  publish an old-account success, or clear a newer request's busy state.
  Switching feed mode also invalidates the old feed/pagination requests.
- `lib/features/authentication/session/chumbucket_session.dart`: a refresh
  finishing after sign-out cannot return the previous session's held token.
- `test/calls_session_isolation_test.dart` and
  `test/session_token_boundary_test.dart`: 13 new regressions. All 13 failed
  before the corresponding fixes; all now pass.

The debugging skill's reproduce-first workflow exposed these failures before
the implementation was changed. This does not certify all other wallet-era
caches or the two existing logout paths as unified.

### Restore the existing app instead of nesting it inside a replacement

- `lib/main.dart`: restore `MwaSplashScreen` as the entry point. Preview session
  restoration and call deep-link delivery are gated, not unconditional.
- `lib/core/config/app_config.dart`: public build flag
  `CALL_RECEIPT_EXPERIENCE`, default **false**.
- `lib/shared/screens/home/home.dart`: retain Home / Calls / Friends / Profile.
  Default Calls uses the existing `CallsScreen`. An explicitly enabled preview
  uses `CallFeedScreen` in the same slot; market discovery pushes a route and
  sign-in opens a sheet without changing the selected tab. Lifecycle callbacks
  are registered after authentication restoration rather than racing it.
- Removed `lib/features/calls/presentation/screens/call_home_screen.dart`, the
  standalone Calls / Markets / You wrapper and its “Legacy wallet” detour.
  It remains recoverable in Git history; no original checkout file was removed.
- `lib/features/authentication/presentation/widgets/call_sign_in.dart`: reuse
  `ChumbucketWavySheet` and `ChallengeButton`. An unlinked Google account sees
  an explicit preview limitation, not a button to create another profile.
  The unlinked state makes no `auth.completeProfile` request. The underlying
  local API/client implementation is retained, not deployed or deleted.
- `lib/shared/screens/splash/mwa_splash_screen.dart`: stop delayed startup work
  from accessing a disposed screen.

### Layout defects exposed by testing the real shell

- `lib/features/profile/presentation/screens/profile_screen.dart`: give the
  history action tiles their Material surface without changing their styling.
- `lib/features/profile/presentation/screens/widgets/profile_wallet_card.dart`:
  allow title/loading/balance text to fit without horizontal overflow.
- `lib/shared/screens/home/widgets/predictions_home_tab.dart`: keep the normal
  fixed-header layout; allow the header to scroll on short screens or large
  text, and constrain section actions alongside their titles.
- `lib/features/challenges/presentation/screens/challenge_history_screen.dart`:
  constrain the title alongside the back button.
- `test/call_home_screen_test.dart`: replace tests of the removed parallel app
  with tests of the actual entry, all four destinations, Settings, wallet
  details, both history routes and return navigation, preview sign-in/discovery,
  and 1.6x text. Providers/network responses are local fakes.
- `test/session_profile_test.dart`: verify the unlinked state cannot create a
  second profile; retain the lower-level client/late-response tests.

## Verification — actual commands and results

| Check | Result |
| --- | --- |
| Focused session/provider suite (9 files) after privacy fix | 109 passed, exit 0 |
| `flutter test --no-pub --reporter expanded` after all code changes | **553 passed, 1 skipped, 0 failed**, 11 seconds, exit 0 |
| `flutter analyze --no-pub` | **0 errors, 0 warnings, 275 informational findings**, exit 1 |
| `flutter build apk --debug --no-pub` after final source change | Built successfully, 18.2 seconds, exit 0 |
| `git diff --check` | No whitespace errors, exit 0 |

The skipped mobile test is the opt-in live public-read test controlled by
`RUN_LIVE_READS`. No live reads were enabled. The first whole-suite run had one
failure in the added history-route test; completing the route-transition pumps
exposed a real challenge-title overflow, which was fixed before the final run.
No assertions were disabled to obtain the passing result.

The Android build reports existing Gradle/AGP/Kotlin future-compatibility
warnings; dependency versions and lockfiles were not changed.

Artifact: `build/app/outputs/flutter-apk/app-debug.apk`

SHA-256: `48762d06e6602ed8452f5cbcaa3e543c696048b84c2ee594074f50035d6a289a`

All 1,198 APK entry names were inspected. No `.env`, Firebase Admin/service-account,
keypair, keystore, `.jks`, or `.p12` filename matched. This is a filename check,
not a comprehensive binary secret scan. The existing asset/config regression
tests also pass. No credential contents were opened.

This APK was built without a public environment config file to verify compilation.
It is **not configured for live use**, was not installed, and is not the artifact
to hand to testers. No API tests were rerun in this checkpoint because API code
was unchanged; earlier audit results are not presented as a new run here.

## Remaining gates and next packet

This is containment and continuity repair, **not completion of the pivot**.
Default startup still follows the existing wallet/onboarding flow. Merely turning
on the preview flag does not complete walletless onboarding or account migration.

Next: verified existing-account continuity — Google and wallet proof must resolve
to the same canonical person without automatic email/wallet-string merges, and
sign-out must clear both identity paths and private state. Then verify the complete
configured flow on the Seeker without replacing or clearing existing user data.

The whole-app audit's unresolved follow, resolution-worker, notifications,
share-link, durable-storage, and production-compatibility findings remain open.
The rescued profile/home design WIP is preserved but not yet integrated. Provider
selection/Panta and funded testing were not advanced in this repair. Trading stays
gated; no funds are needed for this checkpoint. Credential rotation remains an
explicit founder/admin action, not something this work performed.
