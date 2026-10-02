# One account: wallet, Google or X, and a @username — 2026-10-02

## Owner decisions (2026-10-01)

1. A wallet signature is enough to use everything. Social login is never required.
2. Offer Google and X, for people without a wallet and as optional add-ons.
3. Existing wallet profiles: close the client-writable identity paths first,
   then carry a profile over to its wallet's sign-in automatically.
4. Apply all three pending migrations (below).

## What was incoherent

- The original app is wallet-first; the calls server accepted only Google
  sessions and had no wallet sign-in. Wallet users were routed to a Google
  "link your existing account" flow that is switched off
  (`existingAccountClaimsEnabled=false`).
- No username could be claimed; `completeProfile` took a display name only.
- After a successful Google sign-in the app said linking was unavailable.
- **Production never had `create_social_person_v1`** (migration
  `20260928100000` was not applied), so Google sign-up could not work there.

## Production database (applied, approved)

`supabase db push --linked --include-all`: `20260928100000_social_person_onboarding`,
`20260928120000_existing_account_claims`, `20261002090000_wallet_sign_in_and_usernames`
(unique `lower(handle)` index; `handle_status_v1`, `create_social_person_v2`,
`bind_wallet_session_v1`, all service-role only). Pre-check: 212 profiles,
4 handles, no case-insensitive duplicates. After: all three recorded; every new
function exists and refuses anon; existing reads unchanged.
Verified first on a throwaway PostgreSQL 15 with the real identity migrations
(`tests/walletSignInUsernames.postgres.test.ts`, 27 checks).

## API (commit `33523be`, deployment `00b25984`, calls BFF only)

- A Supabase Web3 (Sign in with Solana) session's verified address is read
  from the issuer's answer (provider id and custom claims must agree).
- `completeProfile` takes an optional `handle`; a wallet sign-in attaches its
  verified wallet; a wallet that already has an account is refused
  (`WALLET_HAS_PROFILE`), never duplicated.
- `usernameStatus` (public: available / invalid / reserved / taken).
- Carry-over in `whoami` behind `WALLET_PROFILE_CARRY_ENABLED`, **off**.
- Live checks: `usernameStatus` answers; `identityStatus` reports
  `walletSignIn: true, walletProfileCarry: false`.

## App

- One sheet everywhere (`requestCallSignIn`): Continue with wallet / Google /
  X. Providers are shown only when switched on in Supabase's public settings.
  The wallet signs one plain message (no transaction); the session goes
  through the same identity resolution as Google.
- First sign-in without an account: claim a @username (live availability)
  and a name. Nothing is created by signing in; only an explicit claim does.
  If a wallet is connected but the sign-in was Google/X, the form says to use
  the wallet instead to keep an existing profile.
- Activity and Profile → Calls offer "Sign in" into the same sheet.
- `flutter analyze` clean; `flutter test` 1,108 pass / 40 skip / 0 fail.
  Debug 1.0.28 installed; not exercised on the device (the owner was using
  it), and no wallet prompt was triggered.

## Needs the owner (Supabase dashboard)

- Authentication → Providers → **Web3 Wallet → Solana**: on.
- Authentication → URL Configuration → Redirect URLs: add `https://chumbucket.app`.
- Authentication → Providers → **Twitter (X)**: on, with an X developer app.
- Manual identity linking: on (for adding Google/X to a wallet account later).

## Next

Close the client-writable identity paths (legacy mobile writes and the
`web/` client move server-side; then the lockdown migration, proven on a
throwaway copy), then set `WALLET_PROFILE_CARRY_ENABLED=true`.
