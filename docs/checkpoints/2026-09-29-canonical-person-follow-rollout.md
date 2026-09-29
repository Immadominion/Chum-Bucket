# Canonical person Follow/Unfollow rollout — 29 September 2026

This is a scoped addition to the existing Chumbucket Calls slot and dedicated calls BFF, not a new app shell or a change to the legacy Arena follow graph. Panta remains the only active prediction venue. No call, trade, wallet signature, broadcast, filled position or account-claim anchor was created in this rollout.

## Source and ownership

- Mobile: `product/social-calls-v3` at `9738424940186c4f7efc8538fc027e105c165ef2`; clean after commit.
- API: `product/social-calls-api` at `01d5920a9717102f0012e2c2c6d9a6fdb19413e6`; clean after commit.
- Mobile changes: additive `20260929220000_canonical_person_follows.sql`, exact-project migration operator, BFF repository/payload/provider, existing `CallPersonScreen`, and follow tests.
- API changes: `people.follow` and `people.unfollow`, session-derived canonical actor, person follow state, durable person-follow persistence and tests. No client-supplied actor or wallet is accepted.

## Production change

- Target Supabase project: `odxsineiqquxqiuhxgfq`. The migration SHA-256 is `3287e937fb2864dd5f2da9f97e6db97d86c0f5abf7ce2cfe70c5618d9e3fe8e2`. Only this hash-pinned migration was applied, in one transaction, with Supabase migration history and PostgREST schema reload. No bulk migration push.
- Preflight and post-apply aggregate counts matched: 212 people; 0 legacy follows, calls, call results and native trade sessions. The new table is walletless and initially empty. Anon has no table privileges; authenticated clients have scoped outgoing-edge SELECT but no direct writes; service role writes. The additive followers-only calls policy and RLS were verified.
- Dedicated Railway calls BFF only: project `77e62285-a06d-4f5b-87b7-9de24fd02e2e`, environment `16dd9edb-fd0d-40d1-841a-08b6a3a0be35`, service `63424c97-c8bc-4f67-bb1c-46aac5baf9cc`, deployment `12a5bcfa-8c86-4edc-9ad8-0595fee46236` SUCCESS. Original Arena was not deployed or reconfigured; its `/health` returned HTTP 200.
- First zero-spend production smoke timed out at its 15-second per-request bound. Immediate bounded `/health` checks returned HTTP 200 for both services; the retry passed all 8 checks, with two durable crypto markets, Panta-only/native-funded config, and anonymous/forged/private-order/legacy-trading refusals. Anonymous `people.follow` and `people.unfollow` each returned HTTP 401; global `calls.feed` returned 200. The initial timeout is not erased by the passing retry and deserves recurrence monitoring.

## Verification and Seeker

- API: `bun --no-env-file run typecheck` exit 0; full suite **992 pass / 103 skip / 0 fail**, 3,327 assertions, 1,095 tests / 65 files, exit 0. Opt-in disposable PostgreSQL 15 canonical-follow migration/RLS/visibility test: **1 pass / 0 fail**, 16 SQL boolean checks; no existing local database touched.
- Mobile: full `flutter test --no-pub --reporter compact` **866 pass / 7 skip / 0 fail**, exit 0. `flutter analyze --no-pub`: 0 errors, 0 warnings, 275 pre-existing info findings, exit 1. Debug APK build succeeded. Gradle/AGP/Kotlin/NDK future-compatibility warnings remain.
- Seeker `SM02G40619141343`: initial `install -r` of code 2 was refused as a version downgrade, without changing app data. Rebuilt the same source/config as **1.0.4/code 4** and installed with `adb install -r` successfully. Candidate signer SHA-256 `95ba33d57d40875c15b67320c5d460c90affdefec22698b93c4a5927c5a47b26` matches the previously installed debug signer. APK SHA-256 `bed74593428181dc4205ea482b564bf00b4250c17d33c15f5a6373f7acb90495`. APK filename scan found no `.env`, `env.local.json`, Admin SDK, deploy keypair or dApp-store keystore. Android reports the original 17 July first-install timestamp, new version 1.0.4/code 4, and a running resumed `MainActivity`. A post-update accessibility-tree filter found **Connect Wallet** and **Friends**, not a new-profile prompt; this is not a visual/full-navigation or signed-in device test. Its temporary UI-dump file was removed from the device.
- The build used only public Supabase URL/publishable key, the dedicated calls and original Arena URLs, `CALLS_BACKEND=bff`, `CALL_RECEIPT_EXPERIENCE=true`, and `SOLANA_NETWORK=devnet` for the legacy social namespace. The local ignored JSON specified mainnet-beta, so it was **not** passed wholesale to Flutter. Panta's native mainnet path remains separately pinned by its BFF/wallet code.

## Still unproved

There is no authenticated existing-person follow/unfollow on the production Seeker yet. Production currently has no auth-linked existing people or real social calls. The founder must choose the existing account and complete the trusted Google/SIWS-to-canonical-person journey without creating a duplicate profile; then verify Following, followers-only visibility, unfollow privacy, cold restart and history. Do not invent an identity or seed a synthetic production follow to turn a green test into a false E2E claim. Funded buys remain enabled but are unrelated to this change; no spending authorization follows from this checkpoint.
