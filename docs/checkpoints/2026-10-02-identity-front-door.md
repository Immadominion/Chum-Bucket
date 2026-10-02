# Identity: one front door, usernames, on-phone wallets, staying signed in — 2026-10-02

Branch `fleet/identity` (mobile, from `37c0a10`) with API branch
`fleet/identity` (from `9870733`). Nothing was pushed, deployed or applied to
production; no transaction was signed or sent.

## What a person sees now

1. **First screen (calls build).** "See who called it." and three ways in:
   Continue with wallet / Google / X. X appears only when Supabase reports it
   switched on; Google unless reported off. The option this phone last used is
   the primary button and carries a **Last used** pill, as on web sign-in
   pages. The pill's height follows the text size and it overlaps the button by
   8dp, inside the button's 12dp padding, so it never covers the label (checked
   at 320dp / 2x text). The legacy (challenge) build keeps its wallet-only door.
2. **Google or X with no wallet.** The whole app works: splash routes a
   signed-in account Home even when no wallet app is connected; Home, Friends,
   Activity, header and Profile read the wallet as optional. Friends explains
   where people show up instead of asking for a wallet; "Link Google" (which
   carries a wallet's profile) is offered only when a wallet is connected.
3. **A first sign-in** (no account yet) claims a @username on the front door
   before anything is created.
4. **An account without a @username** (made before usernames, or a wallet
   profile carried over — e.g. the owner's, shown as `@user-xxxxxxxx`) is
   asked once per account on this phone after sign-in; Profile keeps a
   "Claim your @username" row until it is done. A claimed handle is permanent.
5. **Onboarding carousel** now says what the product is: see who called it;
   back, fade or call it (free); the market settles it, with an optional real
   USDC trade on Panta that the person signs and can lose.
6. **A wallet on this phone** for accounts with no wallet app (Profile → My
   wallet): make one (or import a 12-word phrase), see its full address and
   "This wallet lives on this phone", fund it (USDC + a little SOL on Solana),
   back it up, show the recovery phrase or export the private key (each behind
   a warning). It is linked to the account through the existing server proof
   (`auth.requestWalletNonce` / `auth.linkWallet`, purpose `link_wallet`,
   labelled `embedded`). A wallet account back after a reinstall is offered
   "Reconnect my wallet" rather than a second wallet.
7. **Trading with it.** "Fund my call" signs with a connected wallet app if
   there is one, else the linked on-phone wallet (`choosePantaSigner`). The
   sheet says there is no second screen ("Sign and buy"). The phone refuses to
   sign anything but the reviewed buy: one v0 transaction, this wallet the only
   signer and fee payer, only ComputeBudget (BFF ceilings) → own USDC ATA →
   one Panta buy for the reviewed market/side/amount → the attribution memo.
   Same rule as the BFF's `PantaExecution.validateInstructions`.
8. **Staying signed in after deleting the app (Android).** See below.

## Staying signed in: Android Block Store

`SessionContinuity` (`lib/features/authentication/continuity/`) and
`BlockStoreChannel.kt` (`com.google.android.gms:play-services-auth-blockstore:16.4.0`).

- Every session the Supabase SDK saves (sign-in and each refresh) mirrors its
  **refresh token only**, plus the auth subject and the last sign-in method,
  into Block Store entry `chumbucket.session.v1`. It is marked for cloud backup
  only when `isEndToEndEncryptionAvailable()` (Android 9+, screen lock).
- Google: "If the user enables Backup services … Block Store data is persisted
  across the app uninstall/reinstall." On the first launch with no local
  session, splash hands the token to `auth.setSession` once (15 s cap). A
  refused token is deleted; offline keeps it for next launch.
- On-phone wallet phrases go to `chumbucket.wallets.v1`, per account, **only
  when end-to-end encrypted**; otherwise the wallet sheet says the recovery
  phrase is the only backup. Its Android Keystore-encrypted prefs file is
  excluded from Auto Backup (it cannot be read without its Keystore key).
- Explicit sign-out deletes the session entry (a sign-out task; a refused delete fails
  the sign-out so it can be retried). Wallet phrases are **not** deleted on sign-out:
  deleting the only copy of a key can destroy its funds.
- No Play services, iOS, tests: "unavailable" — nothing stored, nothing
  restored, sign in again as before.
- Known limit: restoring onto a second phone while the first is still signed
  in shares one refresh token; Supabase's reuse detection can then sign both
  out. They sign in again; nothing is lost.

### iOS (not built)

The equivalent is a Keychain item with `kSecAttrSynchronizable = true`
(iCloud Keychain, end-to-end encrypted) and
`kSecAttrAccessibleAfterFirstUnlock`, which survives app deletion. With
`flutter_secure_storage` that is a dedicated store with
`IOSOptions(accountName: 'chumbucket_continuity', synchronizable: true,
accessibility: KeychainAccessibility.first_unlock)`, implementing the existing
`BlockStorePort` (read / write / delete; "end-to-end encrypted" = iCloud
Keychain on). `SessionContinuity` needs no change. Today every iOS keychain use
in the app is `synchronizable: false`, deliberately.

## Server (API branch)

- `auth.claimUsername` (POST, token in body): the caller's own account claims a
  handle only while it has none — `HANDLE_ALREADY_SET` otherwise; invalid /
  reserved / taken keep their codes. A running calls mirror is refreshed so
  feeds stop showing the placeholder at once.
- `auth.whoami` also returns the stored `handle` (null = none; omitted when it
  could not be read, so a failed read never looks like "no username").
- `auth.linkWallet` takes optional `walletType: "mwa" | "embedded"` (label only).
- Migration `supabase/migrations/20261002150000_claim_own_handle.sql`:
  `claim_own_handle_v1(auth_user_id, handle)`, service-role only, rules from
  `handle_status_v1`, uniqueness from `uq_users_handle_lower`, row-locked.
  Proven on throwaway PostgreSQL 15 with the real identity migrations and the
  production column lock (`tests/claimOwnHandle.postgres.test.ts`, 36 checks).

## Needs the owner, in this order

1. Apply `20261002150000_claim_own_handle.sql` to production.
2. Deploy the API branch to `chumbucket-calls-bff` (old apps are unaffected:
   the extra `handle` is ignored; `walletType` is optional).
3. Build the app with `CALL_RECEIPT_EXPERIENCE=true` (default is false: without
   it the legacy wallet-only door and copy remain).
4. On a device: Google sign-in → kill and reopen (Last used) → uninstall and
   reinstall with Backup on (still signed in) → make a wallet in Profile, fund
   it with a small amount of USDC and SOL, and place a small Panta trade.
5. Delete Account is still "Coming soon"; when built it must also call
   `SessionContinuity.clearSession()`.
