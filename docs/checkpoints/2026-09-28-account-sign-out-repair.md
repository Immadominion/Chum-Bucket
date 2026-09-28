# Repair checkpoint 2 — shared sign-out and account boundaries

28 September 2026. Local implementation and verification, not release approval.

## Worktrees and scope

- Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
  branch `product/social-calls-v3`, started at `1c18d08`.
- Session-race fix committed as `aa6ecbe`. The shared-sign-out change and this
  checkpoint follow in a separate scoped commit on the same branch.
- API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
  branch `product/social-calls-api`, remains clean at `a85e3f8`.
- The original mobile, reference and API checkouts were not edited. Read-only
  `git status --porcelain=v1 --untracked-files=all` still reports 20, 138 and 1
  entries respectively. Existing recovery archives were not changed.
- No deployment, push, production database mutation, external credential
  rotation, wallet operation or Seeker installation was performed.

## Implemented behavior

The existing entry, four-tab shell, profile, settings and design remain. The
call/receipt preview remains default-off. No second profile creation flow or
automatic account merge was added.

Profile Settings and the call sign-in sheet now use one sign-out action. The
alternate `SettingsBottomSheet` component (no current route references found)
also uses it instead of retaining a separate, unsafe logout implementation.

That action captures the current account dependencies, clears local Google and
MWA credentials, disposes the account-scoped provider/navigation tree, stops the
home lifecycle/realtime handlers, and clears challenge/sync caches. A successful
cleanup creates fresh providers. A failed cleanup keeps account screens hidden
behind a retry screen; every cleanup task is attempted even if another fails.
It does not open the external wallet, submit a transaction, erase onboarding
preferences, or erase another Supabase project's session.

Late OAuth callbacks, identity responses and refreshes cannot restore the old
call identity. An identity response must match the requesting auth subject. A
new account's identity lookup need not wait for an old account's held request.
The existing Google linking action checks its original wallet/account before
submitting a link after browser/signature round trips.

Google session writes/removal are serialized using the SDK's existing project
storage key. Delayed saves cannot recreate the removed credential. Persistence
stays locked until an interactive sign-in begins. A rejected late browser save
also calls the process-wide Supabase SDK's sign-out, not merely a widget reset.
MWA session writes/removal are likewise serialized and old async completions
are invalidated. This is **not** the pending secure-storage migration.

Local notifications are queued: logout cancels a show already in progress and
suppresses later shows/taps. A persisted signed-out marker is checked by the
background-isolate delivery path. Only a still-current, successfully registered
wallet resumes delivery. Cleanup invalidates this device's FCM token; it does
not delete every device registration for a wallet. Token/message-content debug
logging was removed from the touched receive path.

## Changed files

All paths below are relative to the mobile worktree.

- Session handling: `lib/features/authentication/session/chumbucket_session.dart`,
  `supabase_auth_port.dart`, new `app_session_persistence.dart`, new
  `app_sign_out_controller.dart`, new `app_sign_out.dart`.
- Provider lifetime/wiring: `lib/main.dart`, new
  `lib/features/authentication/presentation/widgets/account_session_host.dart`,
  `lib/core/utils/base_change_notifier.dart`,
  `lib/features/authentication/providers/mwa_auth_provider.dart`,
  `lib/features/wallet/providers/mwa_wallet_provider.dart`,
  `lib/features/arena/providers/arena_provider.dart`.
- Shared account state: `lib/shared/providers/challenge_state_provider.dart`,
  `lib/core/services/realtime_service.dart`, `fcm_token_service.dart`,
  `notification_service.dart`.
- Sign-out controls: `lib/features/authentication/presentation/widgets/call_sign_in.dart`,
  `lib/features/profile/presentation/screens/widgets/profile_settings_sheet.dart`,
  `settings_bottom_sheet.dart`.
- Test-exposed layout corrections in that alternate settings component:
  `menu_tile.dart` supplies ListTile's Material surface; `profile_buttons.dart`
  constrains the button label; `settings_bottom_sheet.dart` scrolls when content
  exceeds available height. Colors, typography and destinations are unchanged.
- Tests: new `test/session_account_boundary_test.dart`,
  `test/app_session_persistence_test.dart`, `test/app_sign_out_test.dart`,
  `test/challenge_account_boundary_test.dart`,
  `test/notification_account_boundary_test.dart`; corrected the different-user
  fixture in `test/session_chumbucket_session_test.dart` to return that user's
  own auth subject.
- This checkpoint document.

## Verification

The debugging skill's reproduce-first workflow produced five failing session
regressions before fixing them. Additional regressions exercise real sign-out
widgets with injected platform effects and synthetic identities; they do not
contact Google, Firebase, Supabase, a wallet or a production API.

| Final check | Actual result |
| --- | --- |
| Storage + all sign-out controls, two test files | 13 passed, exit 0 |
| `flutter test --no-pub --reporter expanded` | **577 passed, 1 skipped, 0 failed**, 13 seconds, exit 0 |
| `flutter analyze --no-pub` | **0 errors, 0 warnings, 275 info**, exit 1; unchanged info count |
| `flutter build apk --debug --no-pub` | Success, 19.0 seconds, exit 0 |
| `git diff --check` | Exit 0, no whitespace errors |

There are 24 new tests versus the preceding checkpoint's 553 passing tests.
The single skipped test remains the opt-in live public-read test; live reads
were not enabled. Intermediate alternate-settings tests failed on a test-double
configuration error and then real Material/overflow issues. Those were corrected;
no assertions were suppressed. The full suite was rerun after the final SDK
late-callback cleanup change. No API tests were rerun because API code is unchanged.

The locked local `gotrue 2.15.0` and `supabase_flutter 2.10.1` source was inspected:
SDK sign-out removes its in-memory session before provider revocation, while
the Flutter auth listener does not await LocalStorage writes. The storage queue
and explicit late-session rejection address those actual behaviors.

Artifact: `build/app/outputs/flutter-apk/app-debug.apk`.

SHA-256: `842c03bf8c092d0619b62cec83db8ebee21f1fe2a4bd0e51517215c33ceebac9`.

All 1,198 ZIP entry names were checked. No `.env`, Firebase Admin/service-account,
keypair, keystore, `.jks` or `.p12` filename matched. This is a filename check,
not a full binary secret audit. The build used no environment config file, is
not configured for live use, and was **not installed**. Existing Gradle/AGP/Kotlin
future-compatibility warnings remain; no dependency or lockfile was changed.

## Remaining risks and next packet

**Existing-account linking is not implemented by this checkpoint.** Source
inspection found a circular prerequisite: `WalletLinkService.authenticate()`
requires `userIdForAuthUser()`, and `requestWalletNonce`, `linkWallet` and
`claimLegacyIdentity` all call it. A Google user with no canonical mapping cannot
use those endpoints to claim the existing wallet profile. The current Settings
link action adds a public identity but does not establish `users.auth_user_id`.
`completeProfile` would create another person; it is not the remedy.

The migration/security findings in `docs/contracts/pivot-contracts-v1.md` §8
also show why looking up an arbitrary wallet string is not ownership evidence:
older grants and `sync_user_by_wallet` permit rewriting the mapping. This turn
did not re-query production or change those policies.

Next packet: a verified existing-account claim contract and local two-user abuse
tests, preserving `public.users.id`, followed by the compatible additive server
implementation. Reconcile legacy grants/mappings and prove wallet ownership
before enabling that path; do not merge by email, display name or client wallet
string. Device verification must use a configured build and preserve installed
user data.

Other release gates still open:

- Google remote-session revocation may fail offline; local removal does not
  promise revocation of already-issued credentials. Failure/retry behavior is
  tested in-process, not across power loss during failed storage cleanup.
- MWA reauthorization credentials still use the existing preference storage;
  Keystore-backed migration and mobile nonce/SIWS completion remain outstanding.
- Local notification guards do not certify OS-rendered queued pushes, cross-
  isolate races, server inbox authorization, multi-device token registration or
  recipient binding after a later account switch. No real push test was run.
- In-flight external wallet transactions are not canceled or reversed by logout.
  This is not a new funded-trading implementation or a financial-state audit.
- The whole-app audit's follow, resolution-worker, share-link, durable call-store,
  backend compatibility, rescued design WIP and credential-remediation gates
  remain open. Panta/provider selection and funded testing were not advanced.
