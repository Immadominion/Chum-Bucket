# Integration requests — Packet B (prediction BFF)

Two required patches and one deferred one. Everything else in Packet B lands in files
Packet B owns (`src/prediction/**`, `src/api/predictions.ts`, `supabase/migrations/*_venue_market_*.sql`)
and needs nothing from integration.

Until these land, Packet B builds and tests against a local fixture: `resolvePredictionConfig()`
reads `ctx.app.config.predictions` **first** and falls back to the environment, and every test
attaches the block with `withPredictionConfig()` from `src/prediction/config.ts`. Nothing is
blocked; the routes are simply not reachable from the public `appRouter` yet.

---

## 1. `src/api/router.ts` — nest the prediction sub-router (REQUIRED)

**Why it cannot be avoided:** `appRouter` is the only export the transport and the generated
client type read (`src/api/server.ts`, `scripts/gen-web-types.ts`). A sub-router that is never
nested is unreachable. Contract §1 records this as a one-key change ("tRPC nesting by object
key … no `mergeRouters`, no registry"), and §6 makes `src/api/router.ts` integration-owned.

**Exact patch:**

```diff
--- a/src/api/router.ts
+++ b/src/api/router.ts
@@
 import { DomainError } from "../domain/errors.ts";
 import { streamEvents } from "./eventStream.ts";
+import { predictionsRouter } from "./predictions.ts";
 import { authedProcedure, guard, publicProcedure, router } from "./trpc.ts";
 import { verifyCallProof, verifyGenericAction, verifySocialAction } from "../auth/WalletSignature.ts";
@@
 export const appRouter = router({
+  // Packet B — venue-backed prediction markets. Self-contained: it builds its
+  // own adapter/store behind a module-level memo and reads ctx.app.config, so
+  // nesting it starts nothing and costs nothing at import time.
+  predictions: predictionsRouter,
+
   // ── health / meta ────────────────────────────────────────────────────────
   health: publicProcedure.query(({ ctx }) => ({
     ok: true,
```

**What breaks without it:** every prediction route is dead code — the mobile client cannot list
events, read a market, or reach the kill switch. Packet C has nothing to call.

**Risk:** none to existing routes. The added key is new; no existing key is touched, and
`predictionsRouter` constructs nothing until a procedure is first called.

---

## 2. `src/config.ts` — an optional `predictions` block (REQUIRED for production wiring)

**Why it cannot be avoided:** contract §6 says new modules read config through `ctx.app.config`,
and `AppConfig` is integration-owned. Packet B currently resolves its config from
`ctx.app.config.predictions` when present and from the environment otherwise, which works but
leaves the Jupiter key and the `funded_positions` kill switch outside the typed config object
that `/health` and boot-time validation reason about.

**Exact patch:**

```diff
--- a/src/config.ts
+++ b/src/config.ts
@@
+/**
+ * Packet B — venue-backed prediction markets. The API key is SERVER-SIDE ONLY:
+ * it must never appear in a response body, a log line or a client (contracts §4).
+ * `fundedPositions` is the server-side kill switch (contracts §7) and defaults OFF.
+ */
+export interface PredictionsConfig {
+  venue?: "jupiter" | "fixture";
+  jupiter?: { baseUrl?: string; apiKey: string; timeoutMs?: number };
+  flags?: { fundedPositions?: boolean };
+  cache?: {
+    eventList?: number;
+    openMarket?: number;
+    orderbook?: number;
+    settledMarket?: number;
+    tradingStatus?: number;
+  };
+  circuit?: { failureThreshold?: number; resetAfterMs?: number; halfOpenMaxCalls?: number };
+  retry?: { attempts?: number; baseDelayMs?: number; maxDelayMs?: number };
+}
+
 export interface AppConfig {
   port: number;
@@
+  /** Venue-backed prediction markets (Packet B). Unset → fixture/demo catalog. */
+  predictions?: PredictionsConfig;
   game: GameConfig;
 }
@@ in loadConfig(), immediately before `return cfg;`
+  // Prediction BFF. With no key configured the BFF serves the clearly-labelled
+  // fixture catalog rather than nothing; `funded_positions` stays OFF unless
+  // explicitly enabled (contracts §7).
+  cfg.predictions = {
+    venue: env.PREDICTION_VENUE === "jupiter" && env.JUPITER_API_KEY ? "jupiter" : "fixture",
+    ...(env.JUPITER_API_KEY
+      ? {
+          jupiter: {
+            apiKey: env.JUPITER_API_KEY,
+            baseUrl: env.JUPITER_BASE_URL ?? "https://prediction-api.jup.ag",
+            timeoutMs: num(env.JUPITER_TIMEOUT_MS, 8_000),
+          },
+        }
+      : {}),
+    flags: { fundedPositions: env.FUNDED_POSITIONS === "true" },
+  };
   return cfg;
 }
```

**What breaks without it:** nothing today — the env fallback in
`src/prediction/config.ts:resolvePredictionConfig` covers exactly these variables, and the
route already reads `ctx.app.config` first. The cost of not applying it is only that the
prediction settings are invisible to `/health` and to any future boot-time config validation.

**Do NOT add the key to `/health`, `wiring`, or any response.** `describePredictionConfig()`
reports `jupiterConfigured: boolean`, never the value, and every `VenueError` is redacted on
construction (`src/prediction/redact.ts`). There is a test for this
(`tests/predictionResilience.test.ts` → "the API key is server-side only").

---

## 3. `src/api/trpc.ts` — a canonical app-user id on Context (DEFERRED, needs Packet A)

**Not requested yet.** Raising it now so the seam is known, not asking for it in this pass.

Contract §0.3: identity is `public.users.id`; a wallet is a linked credential. The Packet B
migrations obey that — `venue_orders.user_id` and `venue_positions.user_id` are
`REFERENCES public.users(id)` and every policy reads
`USING (user_id = public.current_app_user_id())`.

But `Context` (`src/api/trpc.ts:14`) carries only `wallet`. So `src/api/predictions.ts`
currently scopes ownership on `ownerKeyOf(ctx.wallet)` → `"wallet:<address>"`, which is
correct *today* (a wallet maps 1:1 to a session) and is deliberately a **separate, prefixed
key**, not a bare wallet string, so it cannot be confused with a canonical user id and cannot
be silently persisted into a `user_id` column.

Once Packet A's `current_app_user_id()` and `users.auth_user_id` are live, the right patch is:

```diff
 export interface Context {
   app: App;
   wallet?: Wallet;
+  /** Canonical public.users.id for the caller. The only thing that may authorise. */
+  appUserId?: string;
```

…resolved in `makeContext` from the verified credential. Packet B then swaps `ownerKeyOf()`
for `ctx.appUserId` in one place (`src/api/predictions.ts`), and the BFF's persisted
`ownerKey` becomes the same value the RLS policies scope on.

**What breaks without it:** nothing in the MVP (funded positions ship off by default, and the
BFF writes through the service role). It must be resolved before any funded row is written to
`venue_orders` in production, because `user_id` cannot be populated correctly without it.

---

## Migrations delivered (no integration action needed)

`supabase/migrations/`:
- `20260913130000_venue_market_catalog.sql` — `venue_markets`, `market_snapshots`
- `20260913130500_venue_market_resolutions.sql` — `market_resolutions` (service-write, append-only)
- `20260913131000_venue_market_orders.sql` — `venue_orders`, `venue_positions`

**Ordering dependency:** `20260913131000_venue_market_orders.sql` opens with a `DO` block that
raises if `public.current_app_user_id()` does not exist, so it must be applied **after** Packet
A's `*_auth_identity_*` migrations. It fails loudly rather than creating a policy that silently
references nothing. Verified: applying it against a database without that function aborts with
that message and writes nothing.

All three were applied and behaviour-tested against an ephemeral local PostgreSQL 15 cluster
(never a live database); 48 assertions covering the constraints, the triggers, the RLS scoping
and the anon/authenticated grants all pass. Contract §9 still applies: reconcile `pg_policies`,
`information_schema.columns` and `pg_proc` against the live project before applying. These
migrations alter nothing existing, so the §9 risk is limited to name collisions.
