# Seeker: existing-account continuity — 30 September 2026

## Outcome and ownership

The normal Chumbucket app now has a witnessed successful returning-wallet
connection on the Seeker. Its original profile, history and four-tab shell are
accessible, Home shows live Panta discovery, and the wallet session survives a
forced app-process stop and relaunch. This is not a Google/SIWS claim, a device
reboot test, an asset reconciliation or a completed trade.

Mobile worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`, starting at `b098e81`.
API worktree: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`, unchanged at `a504c07`; deployed runtime
remains `894ece1`. No originals, production schema/configuration, ownership
anchors or venue results were edited. No Git push or deployment occurred.

## Actual device evidence

Only Seeker `SM02G40619141343` was operated; the other attached Android phone
was left untouched. Package: `dev.cleva.chumbucket`, normal `lib/main.dart`.

1. Verified installed code-7 and candidate code-8 signing certificates match.
   `adb install -r` succeeded; installed version became **1.0.8 / code 8**.
   Original first-install timestamp stayed **2026-07-17 22:20:21**. No app-data
   clear, uninstall, device credential extraction or replacement profile.
2. Opened Connect Wallet. Android showed a wallet chooser. Asked the founder
   to select their original wallet and complete only connection/unlock, with
   no transaction approval. The app subsequently returned to Home; the fixed
   `navigation_home` marker and visible existing profile confirm successful
   login. The selected wallet app/approval screen were not observed, so this
   does not prove the exact cause of the earlier secure-save failure.
3. Home showed Panta crypto markets, followed by existing challenges; no
   football Matchday discovery. Existing Profile showed the returning person's
   avatar, bio and **Edit Profile**, not Create my profile.
4. Original Account & Support/Settings sheet opened. Friends loaded. Profile
   showed two prediction-history entries and 32 challenges; both history
   screens opened. Old prediction rows still have generic Home/Away labels,
   including an old In-play label. Their presence is verified, not their
   correct settlement or claimability. No Claim or challenge action was taken.
5. Calls showed Global/Following and an honest empty feed. Its **Call it**
   action exposed the defect below: generic Google sign-in despite an existing
   connected wallet. No call, follow or trade was submitted.
6. Force-stopped only Chumbucket and relaunched. Home/profile session restored
   without another wallet connection prompt. This is cold-process restoration,
   not power-loss, OS-reboot or full-device-backup evidence.
7. Opened an actual ETH Panta market from Home. Detail showed its exact question,
   Panta attribution, rules/source, independent USDC/share side prices and
   observation timestamp with the indicative/not-a-trade-quote notice. No side
   was locked and no wallet transaction was requested.

Private screenshots are outside Git at
`/private/tmp/chumbucket-seeker-code8.Ddv7Qx/`. They contain personal profile and
history data; do not publish or bundle them. Diagnostics used only fixed,
allowlisted login-stage markers; the log collector was stopped afterwards.

## Root cause and scoped correction

`requestCallSignIn()` always opened the generic `CallSessionPanel`. That does
not bind a returning wallet user to their original canonical person. Settings
already has the separately reviewed `IdentityLinkSheet` that checks server
capability **before** Google, verifies ownership and returns to the same screen.

- `lib/features/authentication/presentation/widgets/call_sign_in.dart`: for a
  connected wallet without a ready canonical session, reuse that existing link
  sheet. Preserve the normal Google panel for walletless entry. No auth bypass,
  identity merge, create-person fallback or replacement navigation was added.
- `test/call_existing_account_entry_test.dart`: three regressions cover direct
  and shell-callback entry, the disabled capability refusing before OAuth or
  proof issuance, dismissal back to the original destination, and walletless
  entry without an MWA provider.

The debugging skill guided reproducing the real-device mismatch and reusing
the established account-link path rather than changing identity authorization.

## Installed corrective candidate

- Built and installed **1.0.9 / code 9** with `adb install -r`: Success.
  Updated at **2026-09-30 21:48:41**; original first-install timestamp unchanged.
- APK: `build/app/outputs/flutter-apk/app-debug.apk`.
  SHA-256: `d8e4ea6eaa40496bb2fe059038c26e99c50b67678dc8fdca1640f2377f210011`.
- Signer SHA-256:
  `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26`,
  matching code 7/8. This is the installed debug signer, not release signing.
- Build uses only allowlisted public defines: original Arena, production calls
  BFF, social `devnet`, `CALLS_BACKEND=bff`, `CALL_RECEIPT_EXPERIENCE=true`, and
  `CHUMBUCKET_EXISTING_PROFILE_ONLY=true`. No complete env file was bundled.
  Filename scan: zero `.env`, local env JSON, Admin SDK, keypair or keystore
  matches. This is not a full binary secret audit. Build exit 0, with existing
  Android toolchain migration warnings.
- After update, Home restored the existing avatar/session without reconnecting.
  Calls → Call it now opens the original **Link Google** wavy sheet. Tapping
  Continue displayed the fixed unavailable/account-unchanged message without
  opening Google or a wallet prompt. The production capability remains off;
  this device result verifies the corrected entry/refusal, not successful linking.
- A second force-stop/relaunch on code 9 again restored the existing session
  without connecting the wallet. At that later observation Home showed **No
  markets ready for calls** again, while old challenges remained visible. The
  three-market smoke pass is therefore not sustained discovery availability.
  Intermittent Panta price/discovery behavior remains a separate test-readiness
  issue; no stale price or alternate provider was substituted to hide it.

## Verification

- Targeted entry/link/session suite: **46 pass / 0 fail**, exit 0.
- Full `flutter test --no-pub --reporter expanded`: **888 pass / 7 skip / 0 fail**,
  exit 0. Initial new-test runs failed on uninitialized test config and then an
  obsolete dotenv test-helper name; the fixture now uses the locked package's
  `loadFromString` with synthetic devnet config. The passing runs are after it.
- `flutter analyze --no-pub`: **274 infos / 0 warnings / 0 errors**, exit 1,
  unchanged baseline. Do not report analyzer exit 0.
- `dart format --output=none --set-exit-if-changed` on both changed Dart files:
  zero changes, exit 0. `git diff --check`: exit 0.
- Production zero-spend smoke initially failed because discovery had no
  call-ready markets. A later run passed **8/8**, **three** durable Panta crypto
  markets, funding/native readiness enabled, and anonymous/forged/private-order/
  legacy-trading refusals verified. Provider prices remain variable; this is
  not evidence of a permanent availability fix. No signed/broadcast/filled trade.
- Read-only canonical-follow verification: **212 people**, zero new calls,
  call results, legacy follows and native trade sessions; all nine grant/RLS
  checks true. No API suite rerun: API source was unchanged in this increment.

## Remaining blocker and next packet

Production `auth.identityStatus` returns enabled identity support but
**`existingAccountClaimsEnabled=false`**. The trusted historical ownership
anchor/claim migration has not been rolled out or seeded. A displayed old
wallet/profile match is a continuity check, not server ownership authorization.

Next: review the exact existing-person ownership evidence, outstanding legacy
authorization/credential remediation, and narrowly scoped production claim
rollout. Never seed anchors from mutable wallet mappings or turn on the flag
just to get past the screen. Only then complete real Google + SIWS into the
same canonical person and prove Follow/call/receipt on the handset.

No wallet funding is needed for this account checkpoint. Native buys are enabled
but no real funded order has been approved, signed, broadcast or filled. A
future money test needs an explicit market, side, amount and user approval;
in-app sell/claim remains unfinished. This debug candidate is not a store release.
