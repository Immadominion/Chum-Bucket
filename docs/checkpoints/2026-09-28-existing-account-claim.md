# Repair checkpoint 3 — existing-account bootstrap

28 September 2026. Server-side implementation only; not release approval or a
claim that the configured phone flow now works.

## Scope and branches

- API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
  `product/social-calls-api`, started at `a85e3f8`.
- Mobile migration/docs: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
  `product/social-calls-v3`, started at `f4088b6`.
- No mobile Dart, UI, navigation, dependencies, lockfiles or build artifact changed.
- Original dirty checkouts are untouched: read-only `git status --porcelain=v1
  --untracked-files=all` reports 20 canonical mobile, 138 reference and 1 original
  API entries, matching the preceding checkpoint. Recovery archives are unchanged.
- No push, deployment, live migration, credential rotation, wallet transaction,
  provider contact, device installation or production data write was performed.

## Implemented and why

The debugging skill's reproduce-first workflow confirmed the circular identity
prerequisite: an authenticated but unlinked Google/Supabase user could not obtain
the old wallet-link proof (`AUTH_USER_UNLINKED`). Creating another person would
not preserve the live app's profile and history.

New default-off POST mutations allow an unlinked verified auth subject to prove
a wallet and claim a **reviewed existing** canonical person. They neither create
a profile nor merge accounts. Because old wallet mappings are client-writable,
the new private historical-anchor registry starts empty, with no auto-backfill.

The proof binds the auth subject, wallet, network and full message hash. SQL
atomically binds `users.auth_user_id`, consumes the proof and writes an immutable
audit. Two-user conflicts, forged mappings, replay, revoked anchors and expired
proofs fail closed. Only hashes of the proof are stored. The ordinary wallet-link
service explicitly rejects the new bootstrap purpose.

An additional regression reproduced a proof expiring while blocked on the
person row lock but still succeeding. The migration now rechecks expiry after
the lock. That regression failed before the correction and passes afterward.

See `docs/contracts/existing-account-claim-v1.md` for the actual wire contract,
storage rules, operator review requirements and mobile integration boundary.

## Files changed

API-relative paths:

- New: `src/auth/ExistingAccountClaimService.ts`, `ExistingAccountStore.ts`.
- Updated: `src/auth/SiwsMessage.ts`, `WalletLinkService.ts`,
  `AuthIdentityError.ts`, `AuthIdentityRuntime.ts`.
- Wiring/config: `src/api/authRoutes.ts`, `src/config.ts`.
- Tests: new `tests/existingAccountClaim.test.ts`,
  `tests/existingAccountClaim.postgres.test.ts`; updated the explicit route
  inventory in `tests/authIdentityIsolation.test.ts` from six to eight entries.

Mobile-relative paths:

- `supabase/migrations/20260928120000_existing_account_claims.sql`.
- `docs/contracts/existing-account-claim-v1.md` and this checkpoint.

## Actual verification

Automatic `.env` loading was disabled for Bun commands. The existing live RLS
database variable was unset; no production credential was read or used.

| Check | Actual result |
| --- | --- |
| Pre-change `bun --no-env-file run typecheck` | Exit 0 |
| Pre-change `bun --no-env-file test` | 626 pass, 11 skip, 0 fail; 2146 assertions; 637 tests/51 files; exit 0 |
| New focused service/router/store/HTTP tests | 20 pass, 0 fail; 64 assertions; exit 0 |
| Final `bun --no-env-file run typecheck` | Exit 0, no diagnostics |
| Final `bun --no-env-file test` (both DB variables unset) | **646 pass, 27 skip, 0 fail**; 2210 assertions; 673 tests/53 files; 867 ms; exit 0 |
| Explicit disposable PostgreSQL test file | **14 pass, 0 fail**; 89 assertions; 2.61 seconds; exit 0 |

The full suite's additional skip count is the 14 opt-in SQL tests plus two hook
entries Bun reports as unnamed skips. All 14 tests ran separately against real
local PostgreSQL, including service-role execution, anon/authenticated denial,
two-session races, retry, row-lock expiry, and deliberate audit-write failure.
The pre-existing live database checks were not enabled.

First SQL run: 11 tests completed and two immutability assertions timed out
because the test passed lazy SQL queries to rejection matchers without executing
them. Explicit query execution fixed the harness; no assertion was removed.
The later row-lock expiry test produced a genuine failing regression, fixed as
described above. The final migration comment-only wording change did not alter SQL.

Scratch cluster: `/private/tmp/chumbucket-account-claim.wClr7M/cluster`, port
56479, database `chumbucket_account_claim_test`; synthetic identities and keys
only. The named scratch database was recreated between runs. Cluster stopped
with `pg_ctl -m fast -w stop`; `pg_ctl status` confirms no server running. Its
stopped files remain as local test artifacts. The user's PostgreSQL16 service
was not touched. No Flutter suite/build was rerun: mobile executable code is
unchanged, and this migration was exercised directly in PostgreSQL.

## Risks, gates and next packet

`EXISTING_ACCOUNT_CLAIMS_ENABLED` remains **false by default**. No real ownership
anchors were approved. Existing credentials/grants require the previously
documented remediation and explicit live approval; this is not a production
security sign-off. An exposed service credential remains outside the protection
of service-only RPCs. The whole-app audit's other open findings remain open.

Next packet: integrate this proof through the existing Settings Google-link
action, with session/wallet race guards and regression tests; complete MWA
Keystore-backed credential storage and test a configured build on the Seeker.
Do not add a second profile screen or fall back to profile creation. Provider
selection/Panta and funded testing were not advanced; no funds are needed here.
