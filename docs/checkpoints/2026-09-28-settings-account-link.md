# Settings account-continuity checkpoint — 28 September 2026

## Outcome

Implemented Google linking in the **existing Settings sheet**, preserving the
existing canonical person and MWA entry flow. No onboarding/profile creation,
history move, automatic merge, transaction, navigation replacement, or deployment.
Panta-only discovery and funded-trading-off gates are unchanged.

The debugging skill traced the reachable Settings action to the old Arena
public-identity-label endpoint, which did not bind `users.auth_user_id`. The fix
uses the already-implemented server account-claim contract, with regression tests
for the complete credential/identity boundary rather than only button rendering.

## Worktrees and files

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`, based on `f5b8213` for this increment.

Changed:

- `lib/features/authentication/providers/mwa_auth_provider.dart`: observable
  account revision, refuse wallet substitution on reauthorization, preserve SNS
  metadata, close failed signing sessions.
- `lib/features/authentication/session/chumbucket_session.dart`: gated Settings
  claim orchestration, account/session race guards, confirm before viewer adoption.
- `lib/features/authentication/session/session_bff_client.dart`: strict claim
  POST transport, readable safe refusals, no credential-bearing redirects.
- `lib/features/authentication/session/session_state.dart`: public capability fields.
- `lib/features/authentication/session/app_session_persistence.dart`: stage Google
  candidate only in memory until same-person confirmation; serialize commit/logout.
- `lib/features/profile/presentation/screens/widgets/identity_link_sheet.dart`:
  existing wavy sheet, Google-only proof flow, safe inline errors.
- `lib/features/profile/presentation/screens/widgets/profile_settings_sheet.dart`
  and `settings_bottom_sheet.dart`: accurate Link Google labels.
- `test/app_session_persistence_test.dart`: five candidate/commit/logout regressions.
- `docs/contracts/existing-account-claim-v1.md` and this checkpoint.

Added:

- `lib/features/authentication/session/existing_account_proof.dart`: pinned SIWS
  purpose/domain/URI/network, exact layout and bounded timestamp validation.
- `lib/features/authentication/session/mwa_existing_account_wallet.dart`: message-only
  signing adapter, validate MWA response metadata, never authorize a transaction.
- `test/existing_account_link_fakes.dart`, `existing_account_link_test.dart`,
  `existing_account_proof_test.dart`, `identity_link_sheet_test.dart`.

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`, remains clean at `d9068b9`. No API source/migration
changes in this increment. No shared bootstrap, dependencies or lockfiles changed.

Original user checkouts were not edited. Read-only `git status --porcelain=v1 -uall`
still reports 20 original-mobile entries, 138 legacy-mobile entries, and one
original-API lockfile entry. Existing recovery backups were not modified.

## Verification — actual final runs

Mobile:

```
flutter test --no-pub --reporter expanded
00:12 +676 ~1: All tests passed!
exit 0

flutter analyze --no-pub
275 issues found. (ran in 8.1s)
0 errors, 0 warnings, 275 info
exit 1 (unchanged existing info-level baseline)

git diff --check
exit 0
```

676 passing is +85 over the prior 591 baseline. Tests exercise exact request
bodies, no client identity input, wrong person/subject, disabled/misconfigured
capability, conflicts, expired/reused proof, browser timeout, wallet cancellation,
same-wallet reconnect, Google A→B→A, concurrent actions, stale HTTP replies,
sign-out/disposal, proof tampering, MWA metadata, staged session persistence and
the real sheet at 390pt with 1.0/1.8 text scale. Platform/browser/wallet/network
effects are injected; this is not a Seeker sign-off.

An initial focused run failed to compile one test because it used a removed
dotenv test helper. Corrected to the locked package's `loadFromString`; final
focused and full runs pass. No production file/environment values were loaded.

API (all three optional local-database environment variables unset; no `.env`):

```
bun --no-env-file run typecheck
$ tsc --noEmit
exit 0

bun --no-env-file test
712 pass
38 skip
0 fail
2442 expect() calls
Ran 750 tests across 56 files. [1.90s]
exit 0
```

No PostgreSQL instance was started and no migration was applied in this increment.
The prior disposable-Postgres evidence remains in the preceding checkpoints.

## Limits and next packet

- Server claims remain opt-in and no reviewed ownership anchors were created.
  A missing/disabled capability is an honest refusal before browser/wallet launch.
- No push, deployment, APK build/install, provider contact, production DB write,
  credential rotation, wallet funding, or trade was performed.
- **MWA reauthorization tokens are still in the existing preferences storage.**
  Keystore-backed migration/removal verification is the next implementation packet,
  not something this checkpoint claims to have finished.
- The locked MWA client uses the existing authorize/reauthorize/signMessages path;
  complete MWA 2.0/device compatibility still needs configured Seeker validation.
- Device testing must prove cancellation, retry, process restart, Google→same
  canonical person, original profile/history preservation and logout. No claim is
  made that the currently installed Seeker build includes this change.
- Existing credential remediation, legacy authorization review, migration/anchor
  approval and Panta durable-traffic release gates remain outstanding. Local tests
  do not grant authority to enable those gates.

Protocol reference consulted: the official [MWA specification](https://solana-mobile.github.io/mobile-wallet-adapter/spec/spec.html),
plus the actual locked `solana_mobile_client` and Supabase SDK source for response
and session serialization. No SDK upgrade was made in this packet.
