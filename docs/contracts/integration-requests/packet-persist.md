# Integration requests — Packet PERSIST (the BFF actually persists)

Durable Postgres stores for the twelve migrated pivot tables, replacing
`InMemoryCallsStore` / `InMemoryPredictionStore` in any deployment that has
`config.social`.

**What landed without integration** (all in files Packets B and D own):

| File | Status |
| --- | --- |
| `src/prediction/pgrest.ts` | new — PostgREST plumbing (the `SocialStore` pattern, copied not imported), a typed `PgrestError` that keeps the SQLSTATE, the shared FIFO `WriteQueue`, deterministic ids |
| `src/prediction/supabaseStore.ts` | new — `SupabasePredictionStore` over `venue_markets` / `market_snapshots` / `market_resolutions` / `venue_orders` / `venue_positions` |
| `src/prediction/marketSync.ts` | new — `MarketSync`: idempotent, cursor-backed, updated-at-watermarked catalog pull |
| `src/calls/supabaseStore.ts` | new — `SupabaseCallsStore` over `calls` / `call_responses` / `call_results`, reading `public.users` and reading+writing `public.follows` |
| `src/prediction/runtime.ts` | edited — store selection + `persistence` / `durable` / `marketSync` / `ready` |
| `src/calls/runtime.ts` | edited — store selection (gated on Packet B actually persisting), UUID `newId`, `ready` |
| `src/prediction/index.ts`, `src/calls/index.ts` | edited — re-exports only |
| `tests/pgrestFake.ts`, `tests/supabasePersistence.test.ts` | new — 28 tests against a fake that transcribes the real CHECKs, unique indexes, FKs and triggers. No network, no real Postgres. |

**Two things are blocked, one is a cold-start window, one is a correctness
limit.** They are §1, §2, §3 and §5 below. Everything else works today.

---

## 1. Four `*_venue_check` CHECK constraints — add `'polymarket'` (REQUIRED, and it blocks the headline feature)

**Why it cannot be avoided.** `VenueId` in `src/prediction/types.ts` already reads
`'jupiter' | 'polymarket' | 'fixture'` (packet-poly.md §1 landed), `PolymarketVenue`
is live and keyless, and `PREDICTION_VENUE=polymarket` is selectable. But the
live schema refuses every polymarket row:

```sql
-- 20260913130000_venue_market_catalog.sql
CONSTRAINT venue_markets_venue_check      CHECK (venue IN ('jupiter', 'fixture'))
-- 20260913130500_venue_market_resolutions.sql
CONSTRAINT market_resolutions_venue_check CHECK (venue IN ('jupiter', 'fixture'))
-- 20260913131000_venue_market_orders.sql
CONSTRAINT venue_orders_venue_check       CHECK (venue IN ('jupiter', 'fixture'))
CONSTRAINT venue_positions_venue_check    CHECK (venue IN ('jupiter', 'fixture'))
```

There is no way to "fix the write": the venue genuinely *is* polymarket, and
writing `'jupiter'` instead would be a lie in a column three other tables and one
generated `is_demo` column read. So `supabasePersistenceDecision()` reports
polymarket as **not persistable** and both runtimes degrade to in-memory with
this on the boot log:

```
[persist] prediction store: in-memory — venue 'polymarket' is refused by
venue_markets_venue_check / market_resolutions_venue_check / venue_orders_venue_check /
venue_positions_venue_check, which are CHECK (venue IN ('jupiter','fixture')) in the
live schema. Persisting would mean loosening a constraint, so this server stays in
memory. Apply packet-persist.md §1 to persist polymarket
```

**What breaks without it:** a Polymarket deployment persists nothing. Calls,
results and the catalog are lost on redeploy — exactly the problem this work
exists to end. A fixture deployment persists fully today; a Jupiter deployment
persists fully today.

**Exact patch** — a NEW migration (this packet may not write migrations, and must
not edit an applied one). `ALTER ... DROP CONSTRAINT / ADD CONSTRAINT` is a
metadata-only change on these four tables while no polymarket row exists:

```sql
-- supabase/migrations/2026MMDDHHMMSS_venue_market_polymarket_venue.sql
-- Contract: pivot-contracts-v1.md §3 (VenueId), §4 (a read-only live venue),
--           §5 (additive only). See docs/contracts/integration-requests/packet-poly.md §1.
--
-- Polymarket is a LIVE, READ-ONLY venue: real markets, real prices, real
-- resolutions, and no trading through us (PolymarketVenue refuses every order
-- path and capabilities().trade is false). It therefore joins the market and
-- resolution allowlists, and it joins the order/position allowlists only so the
-- vocabulary stays uniform — no row can ever be written there, because no code
-- path can create a polymarket order.

ALTER TABLE public.venue_markets
  DROP CONSTRAINT IF EXISTS venue_markets_venue_check,
  ADD  CONSTRAINT venue_markets_venue_check
       CHECK (venue IN ('jupiter', 'polymarket', 'fixture'));

ALTER TABLE public.market_resolutions
  DROP CONSTRAINT IF EXISTS market_resolutions_venue_check,
  ADD  CONSTRAINT market_resolutions_venue_check
       CHECK (venue IN ('jupiter', 'polymarket', 'fixture'));

ALTER TABLE public.venue_orders
  DROP CONSTRAINT IF EXISTS venue_orders_venue_check,
  ADD  CONSTRAINT venue_orders_venue_check
       CHECK (venue IN ('jupiter', 'polymarket', 'fixture'));

ALTER TABLE public.venue_positions
  DROP CONSTRAINT IF EXISTS venue_positions_venue_check,
  ADD  CONSTRAINT venue_positions_venue_check
       CHECK (venue IN ('jupiter', 'polymarket', 'fixture'));

-- The public SELECT policy names the venues too, and would otherwise hide every
-- polymarket market from anon/authenticated. Still a real predicate, never USING (true).
DROP POLICY IF EXISTS venue_markets_public_select ON public.venue_markets;
CREATE POLICY venue_markets_public_select ON public.venue_markets
  FOR SELECT
  TO anon, authenticated
  USING (is_public AND venue IN ('jupiter', 'polymarket', 'fixture'));
```

**Also required in the same change, and easy to miss:**
`venue_markets_live_rows_keep_raw` is `CHECK (venue <> 'jupiter' OR raw_payload <> '{}')`.
It exempts polymarket by accident. §4 requires the raw payload for every LIVE
venue, and the BFF already refuses to write a live market without one. Tighten
it to say what it means:

```sql
ALTER TABLE public.venue_markets
  DROP CONSTRAINT IF EXISTS venue_markets_live_rows_keep_raw,
  ADD  CONSTRAINT venue_markets_live_rows_keep_raw
       CHECK (venue = 'fixture' OR raw_payload <> '{}'::jsonb);
```

**Then, in the API repo:** delete `'polymarket'`'s absence from
`PERSISTABLE_VENUES` in `src/prediction/supabaseStore.ts` (one line), and the
polymarket cases in `tests/supabasePersistence.test.ts` invert. Nothing else
changes — the stores are venue-agnostic.

**Risk:** low. `is_demo` stays `GENERATED ALWAYS AS (venue = 'fixture')`, so a
polymarket row is correctly **not** demo. No existing row is touched.

---

## 2. `src/index.ts` — await hydration, and tick the market sync (REQUIRED for a correct cold start)

**Why it cannot be avoided.** `CallsStore` and `PredictionStore` are synchronous
interfaces, so the durable stores serve reads from an in-process mirror that is
built from Postgres by `hydrate()`. `callsRuntimeFor()` starts that read on first
use and exposes `runtime.ready`, but nothing awaits it — so for the handful of
milliseconds between the first request arriving and hydration completing,
`calls.feed` and `markets.open` read as EMPTY rather than as "not loaded yet".
An empty feed on a database with 500 calls in it is a lie, however brief.

Second half: nothing ticks `MarketSync`. Today the catalog fills durably as a
side effect of `PredictionService.persist()` — every `predictions.listEvents` /
`getMarket` / `getOrderbook` read upserts what it read — so a browsed market IS
persisted and a call can reference it. But a market nobody has browsed since the
last deploy is not in `venue_markets`, and `calls_guard_insert` refuses a call on
a market it cannot see.

**Exact patch:**

```diff
--- a/src/index.ts
+++ b/src/index.ts
@@
 import { createApp } from "./app.ts";
+import { callsRuntimeFor } from "./calls/runtime.ts";
@@
   const app = await createApp(...);
+
+  // The durable stores serve reads from a mirror built from Postgres. Awaiting
+  // it here is what stops the first request after a deploy from reading an
+  // empty feed. Resolves immediately for an in-memory server.
+  const calls = callsRuntimeFor(app.config);
+  await calls.ready;
+  console.log(
+    `   Persistence:     ${calls.persistence.persisting ? "SUPABASE" : "IN-MEMORY"} — ${calls.persistence.reason}`,
+  );
+
+  // Keep venue_markets / market_snapshots / market_resolutions fresh. Idempotent
+  // and cursor-backed, so a tick that overlaps a restart repairs rather than
+  // re-imports. Off with MARKET_SYNC_ENABLED=false.
+  if (calls.prediction && calls.persistence.persisting && process.env.MARKET_SYNC_ENABLED !== "false") {
+    const tickMs = Number(process.env.MARKET_SYNC_TICK_MS ?? 60_000);
+    const tick = async () => {
+      try {
+        const report = await calls.prediction!.marketSync.runOnce();
+        if (report.marketsUpserted || report.snapshotsRecorded || report.resolutionsRecorded) {
+          console.log("[marketSync]", JSON.stringify(report));
+        }
+        await calls.prediction!.durable?.flush();
+      } catch (err) {
+        console.error("[marketSync] tick failed:", err instanceof Error ? err.message : String(err));
+      }
+    };
+    setInterval(tick, tickMs);
+    void tick(); // first pass at boot, like the reconciler's
+  }
```

This mirrors the reconciler wiring already at `src/index.ts:57-85` exactly,
including the "on by default whenever Supabase is configured, off with one env
var" precedent from `src/config.ts:346`.

**What breaks without it:** a cold-start window where a persisted feed reads
empty, and a catalog that only contains markets somebody happened to browse.

**Risk:** low. Both halves are inert on an in-memory server (`ready` is already
resolved, `persisting` is false).

---

## 3. `CallsStore` / `PredictionStore` should be ASYNC (the real fix; larger, and worth scheduling)

**The limitation, stated plainly.** Because the store interfaces are
synchronous, a durable write is applied to the mirror and then queued for
Postgres. The HTTP caller therefore gets its `200` before Postgres has seen the
row. Almost every rule is enforced by the mirror first — it is a real
`InMemoryCallsStore`, and the invariants it refuses are the same ones the
triggers refuse — so a rejection is rare. But **two rules live only upstream**
and cannot be checked in process:

1. `calls_guard_insert` reads the market's CURRENT `status` / `closes_at` and
   whether a `market_resolutions` row exists. The mirror's market snapshot can
   be a tick behind. A call locked in the last moments before a close, or on a
   market the venue resolved between two syncs, is accepted locally and refused
   durably.
2. the database's own `NOW()`.

When that happens the failure is recorded, counted, logged once (redacted),
returned by `store.failures`, and re-raised by `store.flush()` — and the next
`hydrate()` (a restart, or `store.resync()`) removes the phantom from the mirror.
It is never silent. But the user was told "locked" for a call that is not in the
database, and that is the one thing this design cannot fix from inside Packet B
and D.

**Exact patch (shape, not a diff — this is a scheduled piece of work):**

- `src/calls/store.ts` / `src/prediction/store.ts`: every mutator returns a
  `Promise`. `InMemoryCallsStore` becomes `async` with no behaviour change.
- `src/calls/CallsService.ts`, `src/calls/ResolutionSync.ts`,
  `src/prediction/PredictionService.ts`, `src/prediction/Reconciler.ts`: `await`
  the store.
- `src/api/calls.ts` and `src/api/predictions.ts` (integration-owned route
  modules): each already wraps its handler in `call(() => ...)` /
  `guard(async ...)`, so a returned promise is awaited transparently —
  **most route bodies need no change at all**, only the `createCall` /
  `respond` / `hideCall` handlers that currently treat the result as a value.
- the Supabase stores then `await this.pg.*` inline, the `WriteQueue` and the
  mirror-as-read-path disappear, and a constraint violation becomes the HTTP
  error the caller deserves.
- the tests in `tests/socialCalls*.test.ts` gain `await` on store calls.

**What breaks without it:** the write-behind window above. Everything else
works, and the mirror + `flush()` + re-hydration make it loud rather than
invisible.

---

## 4. A purpose-built cursor table, so `public.indexer_cursors` can stop being borrowed (NICE TO HAVE)

**Why it exists.** The pivot migrations added no cursor table, and
`ResolutionSync` and `MarketSync` both need a restart-safe watermark
(`CallsStore.getCursor` / `PredictionStore.setCursor`). Rather than write a
migration this packet is not allowed to write, both stores use the repo's
existing watermark table — `public.indexer_cursors`, which the arena reconciler
already uses for exactly this purpose — under distinct `source` values
(`bff_venue`, `bff_calls`) so nothing collides.

Two things are not ideal about that:

- the watermark is stored in a column called `last_signature`, which it is not;
- `indexer_cursors` has **no RLS and no explicit grants** (it relies on Supabase
  defaults, and §8.1's blanket `GRANT ALL ... TO anon, authenticated` from
  `001_complete_schema.sql:587` has never been fully revoked). A sync watermark
  is not sensitive, so nothing is leaked — but it is a new row in a table that
  does not follow §5's default-deny template.

**Exact patch:**

```sql
-- supabase/migrations/2026MMDDHHMMSS_venue_market_bff_cursors.sql
CREATE TABLE IF NOT EXISTS public.bff_cursors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL,
  cursor_key TEXT NOT NULL,
  cursor_value TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT bff_cursors_source_check CHECK (source IN ('bff_venue', 'bff_calls')),
  UNIQUE (source, cursor_key)
);

-- §5 mandatory template. No SELECT for anon/authenticated at all: a watermark is
-- operational state, not product data.
ALTER TABLE public.bff_cursors ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bff_cursors FROM anon, authenticated;
GRANT ALL ON public.bff_cursors TO service_role;
```

Then in the API repo, point `CURSORS_TABLE` at `bff_cursors` in both
`src/prediction/supabaseStore.ts` and `src/calls/supabaseStore.ts` and drop the
`network` column from the two payloads. One-line change each.

**What breaks without it:** nothing. The watermarks persist correctly today.

---

## 5. What still will not persist, and why (for the record — no patch requested)

1. **`public.users` is read, never written.** `SupabaseCallsStore.upsertPerson()`
   updates the in-process directory only. `public.users` belongs to Packet A and
   the legacy auth path (§6), and §8.1 is a live hole where `anon` can already
   rewrite any row there (`users_update USING (true)`, `users_insert WITH CHECK
   (true)`); this store is not going to become a second writer of it. People
   arrive by `hydrate()`, reading `id, handle, full_name, profile_picture,
   wallet_address, sns_domain`. Nothing in `src/` calls `upsertPerson` outside
   tests, so nothing is lost in production. **When Packet A's account-creation
   path lands, that is the writer.**

2. **`public.users` has no `display_name` and no `avatar_url` column.**
   `Person.displayName` comes from `full_name`, `Person.avatarUrl` from
   `profile_picture`, and `Person.handle` falls back `handle -> sns_domain ->
   user-<first 8 of the canonical id>` — never to the wallet, because a wallet is
   a credential and a handle is a public label (§0.3).
   `Person.settledCalls`/`correctCalls` are deliberately NOT stored:
   `CallsService.decorate()` re-derives them from `call_results` on every read,
   so a stored count could only ever be a second, staler answer.

3. **A follow for a wallet-less account cannot be persisted.**
   `public.follows.follower_wallet` / `followee_wallet` are `NOT NULL` with a
   non-empty CHECK (the table predates canonical ids). The store writes both the
   wallet columns and the canonical id columns; with no wallet on either side it
   refuses the durable write rather than putting a placeholder into a column
   other code reads as a credential. Relaxing that is a legacy-table change and
   is deliberately out of scope.

4. **`venue_positions` for a FILLED position needs a source order.**
   `venue_positions_filled_requires_reconciliation` requires `reconciled_at`,
   `source_order_id` and a non-zero size, but the normalized `VenuePosition`
   (§4) carries no source order. The store recovers it from that owner's own
   reconciled order on the same market and side; with no such order the position
   is not representable as FILLED and the write is refused, because inventing a
   source order would be a lie about where money came from. `funded_positions`
   is OFF by default (§7) and `PolymarketVenue.listPositions` refuses outright,
   so no production path reaches this today.

5. **`venue_orders` / `venue_positions` need a canonical user.** Both
   `user_id` columns are FKs onto `public.users(id)`, but the BFF's owner handle
   is `wallet:<address>` (`src/api/predictions.ts`). The store LOOKS the
   credential up (`users.wallet_address`, then `linked_wallets.wallet_address`)
   and refuses when it resolves to nobody — it never mints a user, which is
   precisely the hole §8.2 describes in `sync_user_by_wallet`.

6. **Snapshot hydration is page-bounded.** `market_snapshots` has no
   `DISTINCT ON` equivalent in PostgREST, so the latest snapshot per market is
   recovered by walking `observed_at DESC` in up to five pages of 1000 and
   keeping the first row seen per market. Active markets are covered
   immediately; `PredictionHydrationReport.marketsWithoutSnapshot` counts any
   that are not, and the next `MarketSync` pass re-observes them. A purpose-built
   `latest_market_snapshot` view (`SELECT DISTINCT ON (market_id) ...`) would
   make it exact in one request, and is the natural companion to §4.
