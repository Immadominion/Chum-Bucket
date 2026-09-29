# Seeker wallet-login guard — 30 September 2026

The Seeker's Solflare approval succeeded, but Chumbucket 1.0.5 reported a failure at the `secureSave` checkpoint. This is **not** a proved wallet rejection or a successful application login. The Solana Mobile wallet chooser's blurred screen is a separate unresolved handoff issue. No transaction was approved or sent.

While tracing the failure, we found that the legacy `MwaAuthProvider.authorize()` saved the wallet result and then called `sync_user_by_wallet`, with an upsert fallback. That could create a second `public.users` person for a wallet that was not the founder's existing profile. We stopped the app before a further attempt. A read-only production check still showed 212 people, 0 new calls, 0 call results and 0 native trade sessions.

## Scoped device-test correction

- 1.0.6/code 6 stopped treating the optional MWA `wallet_uri_base` as a mandatory secure-storage value. An unsafe/non-HTTPS value is discarded; public key, wallet address and token validation remain strict. This is a plausible correction, **not yet a verified root cause** of the Solflare `secureSave` error.
- 1.0.7/code 7 was built with `CHUMBUCKET_EXISTING_PROFILE_ONLY=true`. Before secure save, it performs a read-only exact-wallet lookup of `public.users.id`. No match or query failure stops authorization with a value-free message. A found profile bypasses `sync_user_by_wallet` and its upsert fallback. Restoring a prior local session also requires the same lookup. This prevents an accidental second profile in this test build; it does **not** itself prove a canonical-person claim or grant trusted Supabase Auth.
- The flag defaults to false in normal builds so existing new-user signup behavior is not silently changed. **Do not ship a release candidate on the strength of this device guard alone.** The legacy wallet sync/creation path and canonical-identity migration still need a reviewed product decision and authenticated existing-person E2E proof.

## Verification

- `flutter test --no-pub`: **878 pass / 7 skip / 0 fail**, exit 0.
- `flutter analyze --no-pub`: **274 info / 0 warnings / 0 errors**, exit 1 for existing info findings. Targeted `dart analyze` on the changed files: no issues.
- Guard tests exercise found/missing/unavailable HTTP responses and both accepted/rejected restore. All observed requests are GET; no sync RPC or upsert is reached by the guarded authorization branch.
- Debug APK built successfully with explicit public Supabase/calls/Arena URLs, `SOLANA_NETWORK=devnet`, `CALLS_BACKEND=bff`, receipt experience on, and the existing-profile-only flag. The ignored local JSON was not bundled or passed wholesale. APK SHA-256: `e8aed44753bc320cc1e44016194e47c242e4f40d7d44c0bce5e139557111b7b5`. Filename scan found no `.env`, Admin SDK, deploy keypair or keystore asset. Candidate signer SHA-256 `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26` matched the installed signer.
- `adb install -r` succeeded on Seeker `SM02G40619141343`. Android reports `1.0.7/code 7` and original first-install timestamp `2026-07-17 22:20:21`; no uninstall/data clear.
- Production read-only migration verification immediately before install: 212 people; 0 legacy follows, calls, call results, native trade sessions; all nine canonical-follow RLS/grant checks true.

## Still open

The code-7 Solflare login, original profile/history continuity, trusted Google/SIWS account claim, and authenticated production follow/call have **not** yet been witnessed. One controlled connection attempt using the founder-selected existing wallet is the next checkpoint. If the profile guard refuses, stop and reconcile identity; do not create a replacement user. If secure save still fails, classify the failure using only redacted stage markers. No funded trade, signature or broadcast is authorized by this checkpoint.
