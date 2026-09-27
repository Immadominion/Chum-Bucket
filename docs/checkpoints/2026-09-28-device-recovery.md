# Device recovery checkpoint — 28 September 2026

## Actual outcome

The Seeker now starts into Calls / Markets / You without a wallet gate. Real
Polymarket questions, prices (including their stale indicator), and resolution
rules render through the existing deployed BFF. The user selected their Google
account on the device; that session survives an in-place debug APK update.

The deployed BFF reports `AUTH_USER_UNLINKED`. The new mobile build now offers
explicit public-name onboarding instead of an ineffective retry button. Its new
server route and additive SQL function are implemented and tested **locally**, not
deployed. No live profile was created, no real call was posted, and no trade was
submitted in this checkpoint. This is not an end-to-end completion claim.

## Worktrees / commits / changed files

Only the recovered product worktrees were edited. The three original dirty
checkouts and their recovery backups were not changed.

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`:

- `1c34643`: `lib/core/config/app_config.dart` and
  `test/app_config_startup_test.dart` — initialize flutter_dotenv from an empty
  string before reading public build settings; never load an environment asset.
- `be622c2`: `lib/features/calls/data/call_models.dart`,
  `lib/features/calls/providers/calls_provider.dart`,
  `test/{bff_calls_errors,calls_models,calls_catalog_regression,live_catalog_smoke}_test.dart`
  — accept the backend's Polymarket vocabulary, surface schema drift, and filter
  closed/not-yet-open catalog entries using the clock.
- `008c4dc`: `lib/features/authentication/session/{chumbucket_session,session_bff_client}.dart`,
  `lib/features/authentication/presentation/widgets/call_sign_in.dart`,
  `test/session_profile_test.dart`, and
  `supabase/migrations/20260928100000_social_person_onboarding.sql` — explicit
  verified-session onboarding, idempotent canonical identity, and sign-out race
  protection. No email/wallet-based legacy merge.
- `4b34bae`: `lib/main.dart`,
  `lib/features/calls/presentation/screens/{call_home_screen,call_markets_screen,call_feed_screen,call_detail_screen,call_person_screen,market_detail_screen}.dart`,
  and `test/call_home_screen_test.dart` — reachable social entry point, real
  sign-in actions from deep-linked screens, public discovery, explicit legacy access.

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`:

- `0099b9e`: `src/calls/{CallsService,markets}.ts`,
  `tests/{socialCallsDeadline,socialCallsResults,supabasePersistence}.test.ts` —
  server rejects calls/back/fade outside the venue window or after published resolution.
- `a85e3f8`: `src/api/{authRoutes,calls,notifications,server,trpc,socialProcedure}.ts`,
  `src/auth/IdentityStore.ts`, `src/calls/{runtime,supabaseStore}.ts`,
  `tests/{authIdentityFixtures,authIdentityIsolation.test,socialSessionHttp.test,socialProfilePostgres.test,socialDurabilityBarrier.test}.ts` —
  bearer-header integration, walletless verified identity, service-only profile RPC,
  directory refresh after onboarding, and durable acknowledgement barrier.

## Verification actually run

| Check | Result |
| --- | --- |
| Flutter suite before this recovery | 524 passed |
| Final `flutter test` | **536 passed, 1 skipped, 0 failed** |
| `flutter analyze` | **282 info-level issues, 0 warnings, 0 errors** (existing baseline; exit 1) |
| Live public-read smoke test with `RUN_LIVE_READS=true` | **1 passed**; real catalog and detail decode, snapshot present, crowd split withheld |
| `flutter build apk --debug --dart-define-from-file=env.local.json` | exit 0; Kotlin migration warnings from dependencies |
| APK archive scan | **0 `.env` entries** |
| Seeker in-place install | `Success`; Google session retained |
| API suite before this recovery | 612 passed, 10 skipped, 0 failed |
| Final `bun run typecheck` | exit 0, no diagnostics |
| Final `bun test` | **626 passed, 11 skipped, 0 failed**, 2,146 expectations, 637 tests / 51 files |
| `VERIFY_LOCAL_PG=true bun test tests/socialProfilePostgres.test.ts` | **1 passed, 0 failed**; nine SQL boolean assertions plus four invalid-input rejection checks |
| `git diff --check` | clean in both worktrees |

The Flutter skip is the opt-in live-read test, which was also run separately.
Ten API skips are existing external-database RLS tests; the eleventh is the new
local PostgreSQL test, also run separately. Do not represent those ten as passed.

The PostgreSQL test creates its own Unix-socket-only temporary PG15 cluster,
applies only the new function to a minimal legacy-compatible fixture, and stops
and removes the cluster. It never consumes a production database URL or touches
the existing Homebrew PostgreSQL instance. This is not full migration-stack or
production-schema reconciliation.

Installed debug APK SHA-256:
`3ddf3eb19f97116e9685f873267141c6a26a3c0e9660343b89539f70dbb0eb3a`.

Local screenshots/logs: `/tmp/chum-device-L4gYO0/`. Useful device evidence:
`chum-home-latest.png`, `chum-markets-latest.png`,
`chum-market-detail-latest.png`, `chum-profile-latest.png`.
Do not publish account-picker screenshots: they contain personal account labels.

## Deliberate limits / next packet

1. **Live onboarding is blocked on deployment approval.** Apply the one additive
   profile migration, then deploy the tested API to the existing
   `chumbucket-calls-bff` service only. No arena deployment, trading enablement,
   key rotation or funding is included. Until then the phone's new profile
   button cannot succeed against the old server.
2. **Durability is fail-closed, not transactional.** The current writer uses a
   shared FIFO queue and an in-memory mirror. A failed save now produces a 503
   and quarantines social reads rather than publishing a phantom call. Partial
   multi-row writes still need database reconciliation/restart; do not casually
   clear failure records or call this an atomic call/response transaction.
3. **The whole free loop is not finished.** The walletless follow mutation and
   profile UI remain missing; social-call device create/back/fade/share and
   return-to-receipt still need verification after authorized onboarding.
   Discovery currently lists all callable crypto deadlines, not just the desired
   roughly 4-hour–7-day editorial window. Email OTP recovery also remains owed.
4. **Panta is not implemented as a venue yet.** Read-only investigation found a
   real documented API and existing server-side credentials. This session's live
   list contained 84 markets; six titled markets were resolved, while the open
   markets lacked titles. A blank question is not usable call evidence. Panta
   prices/payout semantics must not be relabelled as Polymarket probabilities.
   See `docs/contracts/panta-venue-findings.md` and https://docs.panta.market/.
   No provider contact, market creation, quote submission or funded order occurred.
5. **Credential exposure remains unresolved.** See `docs/recovery-manifest.md`.
   No exposed private key/environment contents were opened or printed; no
   external credential was rotated. Removing the APK asset does not undo the
   prior release exposure. Existing legacy authorization findings remain release gates.

The debug skill's reproduce/isolate/verify sequence drove this checkpoint:
device behavior exposed startup, routing, wire-vocabulary and onboarding gaps
that large isolated test counts had not detected. No additional agent fan-out
or destructive cleanup was used.
