# One bell: the calls inbox goes live — 2026-10-01

## Before

- Every bell in the people-first shell opened the legacy, wallet-keyed
  `ArenaNotificationsScreen` (followed calls, claim-ready winnings). Its reads
  take a wallet as input (pivot contracts §8 findings 3–4); "mark all read"
  needs a wallet signature.
- The calls inbox (Packet F: Backed / Faded / Resolved / Rematch, recipient
  derived from the session) was built in the API but never mounted:
  `notifications.unreadCount` on the calls BFF returned "No procedure found".
  The app had only a mock repository for it and no screen that opened it.

## Owner decisions

Mount as `inbox.*` (non-breaking); one bell screen with two sections; the
implementation agent applies the router change and deploys.

## API

- Commit `98a85b2` on `product/social-calls-api`: `router.ts` mounts
  `inbox` and `record`; `tests/socialNotificationsMount.test.ts` added. See
  `docs/contracts/integration-requests/packet-f.md`.
- `bun run typecheck`: pass. `bun test`: 1009 pass / 103 skip / 0 fail.
- Export via `scripts/prepare-calls-deploy.ts --prepare`: 145 committed files,
  import graph validated, archive SHA-256
  `aa638da9bd266d4b5e0649987c7fd15d48f79336358421b350ceb310628d5b51`.
- Deployed only to `chumbucket-calls-bff` (`63424c97-…`), production:
  deployment `3b823a07-392b-4de2-93a2-e078eec2874f` SUCCESS, clean boot.
  Previous `a89828f3` remains available for rollback.
- After rollout: `inbox.unreadCount` HTTP 401 (session required; was 404);
  `health`, `calls.feed`, `markets.open` 200; legacy `notifications` still
  present. Original Arena not deployed; `/health` 200.
- No schema, variable or credential change. The production tables
  `social_notifications` and `call_category_records` already exist (anon is
  refused, as the migration intends) but are not yet written by the API.

## App

- `BffNotificationsRepository`: `inbox.list / unreadCount / markRead` on the
  calls transport and session token; sends no user id or wallet. Maps the
  server view onto the existing `CallNotification` (server copy verbatim;
  Backed/Faded and challenge rematches open your call, results open the
  receipt, a rival's new call opens that call). Contract-tested against a page
  produced by the API's own code (`test/fixtures/inbox_page_server.json`).
- `main.dart` (integration-owned): registers `NotificationsProvider`, real BFF
  by default, mock only for an explicit `CALLS_BACKEND=mock` build.
- `ActivityScreen`: "Your calls" (connect row when there is no session), then
  "Earlier challenges" — the legacy wallet notices, shown only when present;
  a claim still opens My Pots and marking them read still asks the wallet.
- The shared bell opens Activity; its badge adds both unread counts, loaded
  when the bell first appears.
- `flutter analyze`: clean. `flutter test`: 1,099 pass / 40 skip / 0 fail.
- Seeker debug 1.0.26: the bell opens Activity; this account has no calls
  session yet, so it shows the Connect row; no wallet notices were present.
  Nothing was marked read, signed or connected during the check.

## Durable read state (follow-up, same day)

- API commit `7eccba5`: `SupabaseNotificationsStore` — the calls-store shape
  (in-memory mirror + write-behind) over the existing production tables.
  `social_notifications`: insert deduped on recipient + the trigger's key,
  `read_at` patches limited to the recipient's unread rows.
  `call_category_records`: upsert only when counts change, so an inbox read
  is not a write per person. `hydrate()` reads both back; inbox procedures
  wait for it and answer "unavailable" rather than re-deliver read rows as
  unread. Durable exactly when calls are.
- Own write queue, by design: the shared calls queue quarantines the social
  service on any failure and restarts it; a refused notification must not do
  that (re-derivation would make it a restart loop). Each write drains the
  calls queue first, so cited calls/responses/results land before it.
- Tests: `socialNotificationsDurable.test.ts` (wire contract over the real
  deriver and calls harness: inserts, read patches, change-only record writes,
  ordering, failure isolation, restart without duplicates);
  `socialNotifications.postgres.test.ts` (opt-in, `VERIFY_LOCAL_PG=true`): both
  migrations on a throwaway PostgreSQL 15 judge the statements PostgREST
  generates — dedupe, the RESOLVED guard, read_at-only updates, monotone
  records, recipient-only reads, no anon access. Passed locally.
  `bun run typecheck` pass; `bun test` 1016 pass / 104 skip / 0 fail.
- Deployment `c5a6a937-82e5-4d14-a640-e50b4a681767` SUCCESS on
  `chumbucket-calls-bff` only (export SHA-256
  `a74ef20e363967be64f8b664035eff73dce715ccbe68c662a0721f58ce1be39d`). Logs:
  calls store supabase; `notifications store: supabase — calls are durable`.
  Probes: health / calls.feed / markets.open 200, inbox.* 401; original Arena
  200. Rollback point: `3b823a07`.
- Not yet observed live: hydration runs on the first signed-in inbox request,
  and no linked session was available to make one. No schema, variable or
  credential change.

## Note

`integration-requests/README.md` also lists bottom navigation as
integration-owned; the Markets/Friends icon change in
`2026-10-01-prototype-alignment.md` touched it.
