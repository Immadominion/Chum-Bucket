# Checkpoint — Panta only

28 September 2026. User decision: use just Panta, not Polymarket or Jupiter.

## Implemented locally

The only live prediction provider selectable through configuration and the
runtime factory is now Panta. Unset `PREDICTION_VENUE` defaults to `panta`;
other values (including `fixture`) fail with a non-sensitive configuration
error. Missing or sandbox Panta credentials also fail; no fallback catalog.
Old provider credentials do not affect selection. Funded positions stay off
even when `FUNDED_POSITIONS=true` is present.

Historical Polymarket/Jupiter data retains its identity and attribution. It
is excluded from new-call discovery, and direct create/Back/Fade/Challenge
attempts are refused. Historical reads and sharing remain intact at the
service layer. No database records, prior migrations or original checkouts
were deleted or rewritten.

Fixture injection remains an explicit in-code test seam, not an environment
setting. Old adapter implementations remain for regression/history support,
but the live composition no longer imports or constructs them. Replaced the
old provider-selection tests with Panta-only refusal/selection tests; existing
adapter normalization and historical persistence tests still run.

The debug skill guided reproducing the old selection paths and pinning their
replacement with regression tests rather than merely changing UI branding.

## Worktrees and files

API: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls-api`,
branch `product/social-calls-api`:

- `.env.example`, `src/config.ts`
- `src/prediction/{venuePolicy,config,runtime,types,PredictionService}.ts`
- `src/calls/{CallsService,markets}.ts`
- `tests/{venueSelection,predictionRoutes,integrationMount,supabasePersistence}.test.ts`
- Replaced `tests/polymarketRuntime.test.ts` (recoverable in Git).

Mobile: `/Users/mac/Documents/codes/opensauce/world/chumbucket-social-calls`,
branch `product/social-calls-v3`:

- This checkpoint and `docs/contracts/panta-venue-findings.md`.
- Comments only in `lib/features/calls/data/calls_repository_factory.dart`:
  remove the stale claim that selecting the BFF proves provider readiness.
- No navigation, screen, wallet, account or executable mobile behavior changed.

## Verification

All Bun commands used `--no-env-file`, with
`AUTH_IDENTITY_TEST_DATABASE_URL` and `ACCOUNT_CLAIM_TEST_DATABASE_URL` unset.

- `bun run typecheck`: exit 0, no diagnostics.
- `bun test tests/venueSelection.test.ts`: 15 pass, 0 fail, 54 assertions.
- Full `bun test`: **693 pass, 27 skip, 0 fail**, 2,381 assertions;
  720 tests across 54 files, 892 ms, exit 0.
- `git diff --check`: clean.
- No live database, provider request, deployment, transaction or device install.
- No Flutter build/test needed for documentation/comment-only mobile changes.

## Still blocked from release

This commit is not permission to deploy. The previously deployed BFF and the
installed phone build are unchanged. A deployment retaining the previous
provider setting will be refused, intentionally. The complete Panta
storage/client migration must precede any approved deployment/config switch.

Panta native USDC/share prices are not probability snapshots. Its additive
storage, immutable price-at-call receipt contract and matching mobile models
remain unfinished, so the existing durable-traffic/new-call Panta guards stay
in place. The prior live read sampled no usable open questions; do not fill
that gap with another provider or invented results. No new live catalog read
was made in this checkpoint.

Next packet: native-price storage and receipts within the existing Chumbucket
flow, then existing-account Settings linking and configured Seeker validation.
Market creation/funding requires separately scoped approval; trading remains
off until the free loop and eligibility/compliance/device gates pass.
