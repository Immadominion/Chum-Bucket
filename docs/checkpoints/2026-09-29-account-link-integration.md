# Existing-account local integration — 29 September 2026

## Outcome

The production Flutter account-link controller and HTTP client now have a
reproducible test through the mounted BFF, real PostgREST and disposable PostgreSQL.
The original canonical person, name, wallet mapping, history and receipt survive
linking. Cancellation, unavailable ownership evidence and ownership conflicts do
not bind another account. A lost reply after a committed claim can be retried
without creating another profile.

Google consent/callback and MWA approval are injected. The test signs the real
server-issued message with an isolated synthetic Ed25519 key using the locked
Dart Solana library; the production server verifies it. This is **not** a real
Google/Seeker round-trip, a production migration, or whole-app release approval.
No screens, app entry, navigation, Panta configuration or trading gates changed.

The application-debugging skill drove the cross-boundary reproduction and the
subsequent failing regression before fixing server transport behavior.

## Confirmed defect and fix

Identity adapters followed upstream redirects by default. A local two-server
regression demonstrated that all four tested operations (issuer verification,
person lookup, profile RPC and account-claim RPC) contacted the redirected host
for 301/302/307/308 responses. Some fetch/JSON errors also escaped unsanitized;
issuer verification and person-store requests had no explicit timeout.

All identity requests now refuse redirects. The issuer and identity store have
10-second abort signals (the claim store already had one). Native fetch/parser
errors become the fixed `IDENTITY_STORE_ERROR` code, with no provider payload or
credential in the exception. Known non-2xx issuer refusals retain their existing
null-session behavior. Issuer documentation no longer promises instant token
revocation or assumes every Supabase project uses HS256.

The transport regression was **2 pass / 22 fail** before the fix, then
**24 pass / 0 fail**, 68 assertions afterward. No real credential was used.

## Worktrees and changed files

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`, starting at `d9068b9`.
Local commits: `a52af8d` (transport fix) and `eb38486` (integration runner).

- `src/auth/ExistingAccountStore.ts`, `IdentityStore.ts`, `SupabaseJwt.ts`:
  redirect refusal, bounded requests and sanitized errors.
- `src/api/server.ts`: optional listen host for loopback-only integration;
  deployed callers keep the previous default when omitted.
- `tests/authIdentityTransport.test.ts`: 24 real-HTTP/injected-failure regressions.
- `scripts/verify-account-link-local.ts`: explicit opt-in local orchestration.

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`, starting at `c1e958b`.

- `test/existing_account_local_integration_test.dart`: six opt-in integration
  tests using the real session/client and synthetic external approvals.
- This checkpoint and the account-claim contract's verification note.

No migration, package, lockfile or mobile executable code changed. The original
dirty checkouts remain unedited: 20 canonical-mobile, 138 reference-mobile and
one original-API dirty entries (`git status --porcelain=v1 -uall`).

## Exact verification

| Check | Result |
| --- | --- |
| Cross-language Flutter/BFF/PostgREST/PostgreSQL run | 6 pass / 0 skip / 0 fail, exit 0 |
| Actual PostgREST client-role checks | 10 denials: anon/authenticated cannot read any of the three claim tables or invoke either privileged RPC |
| Database preservation checks | Five original people and receipts preserved; two people linked; three proof audits (one fresh-proof retry); no profile-creation RPC |
| API typecheck | `tsc --noEmit`, exit 0 |
| Full API tests | 736 pass / 38 skip / 0 fail; 2510 assertions; 774 tests across 57 files; 1.95s; exit 0 |
| Full Flutter tests without local opt-in | `00:23 +708 ~7: All tests passed!`, exit 0 |
| Full Flutter analyzer | 0 errors / 0 warnings / 275 existing info, 4.2s, exit 1 |
| Targeted new Flutter test analysis | No issues found, exit 0 |
| Diff whitespace checks | Exit 0 in both worktrees |

Six of the Flutter skips are the new opt-in tests; all six ran in the separate
local integration invocation. One pre-existing skip remains. The API's existing
optional database tests were not enabled in its default full-suite invocation.
No prior README count is being used as evidence.

An initial runner typecheck found an implicit-any callback in the database
assertion; adding the row type fixed it. The initial PostgREST binary launch
needed the existing PostgreSQL libpq directory on its child-only library path.
No global library symlink, system service or dependency upgrade was made.

## Reproduce and isolation

Run from the API product worktree:

```sh
POSTGREST_BIN=/absolute/path/to/postgrest \
FLUTTER_BIN=/absolute/path/to/flutter \
bun --no-env-file scripts/verify-account-link-local.ts --run
```

`POSTGRES_BIN_DIR` optionally supplies a local PostgreSQL tools directory.
The runner requires explicit `--run`, accepts no database URL, creates a fresh
owner-only temporary cluster and checks its actual data-directory identity
before applying SQL. Every HTTP/database listener binds 127.0.0.1. Children get
an environment allowlist, not inherited provider/database credentials. No `.env`
is loaded and no real wallet/keypair is opened. Reconciliation is explicitly off.

Only two existing additive migrations are applied to a representative legacy
schema: `20260913120000_auth_identity_auth_user_link.sql` and
`20260928120000_existing_account_claims.sql`. This is a claim-path compatibility
test, **not** reconciliation of the complete production migration history.
Anchors are synthetic, seeded only inside that newly-created cluster.

PostgREST's real JWT/role/RPC machinery is used. A narrow local gateway supplies
synthetic GoTrue `/auth/v1/user` answers and forwards `/rest/v1` to PostgREST.
No identity runtime/store/Supabase verifier is replaced or primed. Browser consent,
OAuth redirect delivery, SDK persistence and wallet-app interaction remain
outside this test. Session reconstruction tests the durable account binding,
not a physical device restart.

Tools: PostgreSQL 15.15 (existing Homebrew installation), PostgREST 16.4 portable
macOS ARM64 release, Bun 1.3.14, existing locked Flutter dependencies.
PostgREST was downloaded only into `/private/tmp/chumbucket-account-tools.mpIcIP`;
its archive SHA-256 matched the official release asset digest:
`5720fbde4a19ade9fb189791615c84beb9f0e58201b1b6d17fe3b698faf60776`.
The user's normal PostgreSQL service and Docker configuration were untouched.

Final retained synthetic cluster:
`/private/var/folders/zm/v0w94xb95p11_5df6rxm0js80000gp/T/chumbucket-account-flow-ffzN9D/isolated-db`.
Earlier successful local runs used sibling suffixes `Msewyg` and `V6dZo4`.
Each runner shut down its own BFF, gateway, PostgREST and PostgreSQL in `finally`.
`pg_ctl status` independently confirms the final cluster is stopped. These are
synthetic test artifacts only; no user data was removed.

## Remaining gates / next packet

Next is the actual Seeker Settings Google → wallet proof → same canonical
person round-trip in an approved test environment, including cancel/retry and
old profile/history visibility. That requires suitable non-production OAuth
configuration and reviewed test ownership anchors; the local test does not
authorize enabling claims for live users.

Panta remains the only live venue choice; funded trading stays off. Panta durable
runtime, credential remediation, legacy authorization review and full-app device
release checks remain separate outstanding gates. No push, deployment, production
write, real anchor approval, device install, trade or provider outreach occurred.

Tooling source: official [PostgREST installation guidance](https://postgrest.org/en/latest/explanations/install.html)
and [v16.4 release](https://github.com/PostgREST/postgrest/releases/tag/v16.4).
