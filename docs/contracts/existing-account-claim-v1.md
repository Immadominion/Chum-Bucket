# Existing-account claim v1 — server implemented, disabled

28 September 2026. This adds a safe bootstrap path; it does not replace the
existing app entry, profile, wallet, Settings or sign-out flow.

## Identity contract

A verified Supabase session that has no canonical person can request a fresh
`claim_account` SIWS proof. The server verifies the signature, then an atomic
database RPC binds that auth subject to **an existing** `public.users.id`.
No user is created; no history is moved; no profiles or wallets are merged.

The target comes exclusively from a private, reviewed historical ownership
anchor. Neither an email match, client-supplied person id, profile field,
`users.wallet_address`, nor the old `linked_wallets` mapping authorizes a claim.
Those historical wallet mappings have known client-write paths; a valid current
wallet signature alone cannot establish which old profile it should own.

The additive migration creates an **empty** anchor registry. It does not
backfill or approve any account. There is no public approval endpoint.

## HTTP surface

Both procedures are tRPC **POST mutations**, using the existing JSON envelope.
Credentials and signatures belong in the body, never in a URL. Input objects
are strict; extra identity/review fields are rejected.

| Procedure | Input | Result |
| --- | --- | --- |
| `auth.requestExistingAccountProof` | `supabaseAccessToken`, `address`, `domain`, `uri` | Exact SIWS `message`, `issuedAt`, `expiresAt`, `domain`, `uri`, `network`, `purpose: claim_account`, `proofVersion: 1` |
| `auth.claimExistingAccount` | `supabaseAccessToken`, `address`, `message`, `signature` | Existing `userId`, verified `authUserId`, `outcome: claimed \| already_claimed` |

`auth.identityStatus.existingAccountClaimsEnabled` is false unless the flag is
enabled and the server has a configured claim store. It reports capability,
not individual eligibility or successful migration/schema reconciliation.

The signing client must use the exact returned message. This purpose does not
authorize a transaction, wallet transfer, spend or new profile. Ordinary wallet
attachment/transfer endpoints reject this purpose, including internal callers.

## Storage and transaction boundary

- `existing_account_anchors`: reviewed person/address/network binding with an
  evidence hash and private review reference. Immutable except one-way revocation.
- `existing_account_proofs`: verified auth subject, address, network, nonce hash,
  full-message hash, issuance/expiry and consumption. No raw JWT, signature or
  message is stored. The message hash binds the exact domain, URI, purpose and times.
- `existing_account_claims`: append-only claim audit, retaining the canonical
  user, auth subject, anchor, proof and version. No auth-user deletion cascade.

All three tables enable RLS with zero client policies and revoke client grants,
including inherited broad default grants. RPCs are service-role-only and have
pinned search paths. The service role cannot directly rewrite proofs or audits.

Issuance serializes per auth subject, permits at most ten issues per minute and
supersedes unused proofs. Redemption serializes on the auth subject and target
person, checks every binding and rejects either kind of existing-owner conflict.
Expiry is checked again after waiting for the anchor/person locks.

Auth binding, proof consumption and audit append commit together. Failure rolls
back all three. A still-valid, same-session retry can read its committed result;
it cannot repeat the writes. No guarantee of retry success after proof expiry,
anchor revocation or identity removal is made.

## Refusals

- `ACCOUNT_CLAIMS_DISABLED`: capability off; no proof is issued.
- `ACCOUNT_CLAIM_UNAVAILABLE`: no reviewed active anchor, or target unavailable.
- `ACCOUNT_CLAIM_CONFLICT`: subject already has another profile, or target has
  another auth owner. Never offer an automatic merge.
- `ACCOUNT_CLAIM_RATE_LIMITED`: too many proof requests; retry later.
- Existing SIWS/session/nonce errors retain their distinct codes. Infrastructure
  failures return `IDENTITY_STORE_ERROR` without provider bodies or credentials.

## Required before enabling

1. Founder/admin completes the credential remediation and legacy authorization
   review recorded in `docs/recovery-manifest.md` and the whole-app audit. This
   feature does not close the old client-writable identity paths.
2. Reconcile live schema/grants/RPCs read-only and explicitly approve any live
   migration. This migration has only been applied to disposable local Postgres.
3. Review a limited ownership cohort using independently trustworthy historical
   evidence, not current client-writable rows. Record a private evidence hash,
   review reference and reviewer in anchors; do not publish evidence or secrets.
   Conflicting/missing evidence stays unavailable for manual recovery.
4. Integrate through the **existing** Settings Google-link action. Bind the
   entire operation to the starting wallet/session; discard late completions
   after sign-out/account changes. Refresh `auth.whoami` and require the returned
   existing id. Never call `completeProfile` as a fallback.
5. Complete MWA/secure-storage work and configured Seeker tests, including
   cancellation, conflict, expiry, retry, sign-out and preservation of old history.
6. Only with release approval, set `EXISTING_ACCOUNT_CLAIMS_ENABLED=true` (exact
   lowercase value). Keep it false to stop new requests and redemptions. Already
   established identities/audits are not deleted by switching it off.

No migration, anchor approval, provider contact or flag change is authorized by
this document. Funded trading and venue selection are separate gates.
