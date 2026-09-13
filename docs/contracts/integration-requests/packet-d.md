# Integration request — Packet D (social calls server, resolution sync, receipts)

**Raised:** 13 September 2026 · **Packet:** D · **Owner to apply:** integration

Packet D owns `src/calls/**`, new `src/api/calls.ts`, and
`supabase/migrations/*_social_calls_*.sql`. Everything below is in an
integration-owned file, so it is written here rather than applied.

**The packet typechecks, passes its tests and needs none of these patches to be
correct today** — each entry says exactly what is degraded until it lands.

| # | File | Needed for | Degraded without it |
| --- | --- | --- | --- |
| 1 | `src/api/router.ts` | reaching ANY of the eight procedures | the whole surface is unreachable from the app |
| 2 | `src/api/trpc.ts` | a wallet-less Supabase session | such a caller cannot write; reads are unaffected |
| 3 | `src/config.ts` | config through `ctx.app.config` | the env fallback is used instead — no behaviour change |
| 4 | `src/app.ts` | running the resolution sync on a timer | the sync runs only when something calls it |

Nothing is requested in `src/domain/**` or `src/core/projections/ReadModel.ts`.
See §5.

---

## 1. `src/api/router.ts` — mount the three namespaces (REQUIRED)

`packet-c.md` §5 names the procedure paths `calls.feed`, `markets.open`,
`people.get`, … so the mount is three keys, not one. `src/api/calls.ts` exports
the three sub-routers individually for exactly this.

Add the import beside the existing two:

```diff
 import { authRouter } from "./authRoutes.ts";
 import { predictionsRouter } from "./predictions.ts";
+import { socialCallsRouter, socialMarketsRouter, socialPeopleRouter } from "./calls.ts";
```

Add three keys to the `pivot sub-routers` block at `src/api/router.ts:154-164`,
after `predictions: predictionsRouter,`:

```ts
  /** Packet D — free social calls, venue-derived results and receipts. */
  calls: socialCallsRouter,
  markets: socialMarketsRouter,
  people: socialPeopleRouter,
```

**Collision check, already run:** `appRouter` has no `calls`, `markets` or
`people` key today, and no path beginning `calls.` / `markets.` / `people.`.
`tests/socialCallsMount.test.ts` composes this exact patch off the same exports,
asserts the resulting eight paths, and asserts the absence of a collision — so
this is a patch that has been run before it is applied.

**Degraded without it:** every procedure is unreachable from the app. The
packet's own suite drives them through `callsRouter.createCaller(...)` and
passes either way, which is precisely why the mount test exists.

---

## 2. `src/api/trpc.ts` — carry the Supabase session on `Context` (RECOMMENDED)

### Why

Contract §0.3: identity is `public.users.id`; a wallet is a linked credential.
Packet A shipped the mapping (`current_app_user_id()` in SQL,
`IdentityStore.userIdForAuthUser` in TypeScript), and Packet D reuses it rather
than adding a second identity path.

Today `makeContext` verifies `Authorization: Bearer <token>` through
`app.auth.verify`, which yields a **wallet**. Packet D maps that verified wallet
to a canonical user. That works for every caller the app currently has.

What it does not cover is a **wallet-less Supabase session** — a person who
signed in with X or email and has not linked a wallet. `authedProcedure` rejects
them (`if (!ctx.wallet)`), so they cannot make a call, which contradicts §0.3:
requiring a wallet to speak makes the wallet the identity.

Packet D already reads the field defensively, so applying this patch changes no
code in `src/calls/**` and no test.

### The patch

```diff
 export interface Context {
   app: App;
   wallet?: Wallet;
   /** The player's Privy wallet handle (when provider-custodied) — for deposit sweeps. */
   privyWalletId?: string;
   /** The provider's own user id (e.g. Privy user id) — needed to ask the Auth
    *  port for that user's already-linked social identities (X/Google). */
   privyUserId?: string;
+  /**
+   * The raw `Authorization: Bearer` credential, kept so a module can verify it
+   * against a DIFFERENT issuer than the app's Auth port. Packet A's GoTrue
+   * verifier is the only consumer: it turns a Supabase JWT into auth.uid() and
+   * then into a canonical public.users.id. Never logged, never echoed into a
+   * response, never used as an identity on its own.
+   */
+  supabaseAccessToken?: string;
 }

 export async function makeContext(app: App, token: string | undefined): Promise<Context> {
   const user = await app.auth.verify(token ?? "");
-  if (!user) return { app };
+  if (!user) return { app, ...(token ? { supabaseAccessToken: token } : {}) };
   return {
     app,
     wallet: user.wallet,
+    ...(token ? { supabaseAccessToken: token } : {}),
     ...(user.privyWalletId ? { privyWalletId: user.privyWalletId } : {}),
     ...(user.userId ? { privyUserId: user.userId } : {}),
   };
 }
```

(The two unchanged spread lines are the file's existing ones — only the
`supabaseAccessToken` line is new. Keeping the token on a context that failed
`app.auth.verify` is deliberate: a Supabase JWT is not a Privy token, so the
app's Auth port is *expected* to reject it, and the GoTrue verifier is the one
that can say whether it is real.)

### And the gate itself

With the field present, `authedProcedure` should accept either credential:

```diff
 export const authedProcedure = publicProcedure.use(({ ctx, next }) => {
-  if (!ctx.wallet) {
-    throw new TRPCError({ code: "UNAUTHORIZED", message: "connect your wallet (x-wallet)" });
+  if (!ctx.wallet && !ctx.supabaseAccessToken) {
+    throw new TRPCError({ code: "UNAUTHORIZED", message: "sign in to continue" });
   }
   return next({ ctx: { ...ctx, wallet: ctx.wallet } });
 });
```

**This second half is a behaviour change to a shared procedure and should be
reviewed on its own.** Every existing `authedProcedure` route reads `ctx.wallet`
and would then see `undefined` for a wallet-less session. If that is not
acceptable, the alternative is a separate `sessionProcedure` exported alongside
`authedProcedure` and used only by `src/api/calls.ts`; Packet D is happy with
either and needs no change for the second option.

**Degraded without either:** a wallet-less Supabase user can read everything and
write nothing. Every wallet-bearing caller — which is all of them today — is
unaffected.

---

## 3. `src/config.ts` — the `calls` block (OPTIONAL)

`src/calls/config.ts` reads `ctx.app.config.calls` first and falls back to the
environment, so this changes nothing about behaviour; it moves the settings out
of process env and into the typed config, matching Packets A and B.

```diff
 export interface AppConfig {
   // … existing fields …
+  calls?: {
+    /** §7 `call_receipt_experience`. On by default — it IS the free social loop. */
+    callReceiptExperience?: boolean;
+    /** Host used to build a shareable call/person link. Not a secret. */
+    shareBaseUrl?: string;
+    maxPageSize?: number;
+    syncPageSize?: number;
+    syncMaxPagesPerPass?: number;
+  };
 }
```

and, in `loadConfig`:

```ts
  calls: {
    callReceiptExperience: env.CALL_RECEIPT_EXPERIENCE !== "false",
    shareBaseUrl: env.CALLS_SHARE_BASE_URL ?? "https://chumbucket.app",
  },
```

Env names already honoured by the fallback: `CALL_RECEIPT_EXPERIENCE`,
`CALLS_SHARE_BASE_URL`, `CALLS_MAX_PAGE_SIZE`, `CALLS_SYNC_PAGE_SIZE`,
`CALLS_SYNC_MAX_PAGES`.

**Degraded without it:** nothing. The env fallback is the same values.

---

## 4. `src/app.ts` — run the resolution sync on a timer (OPTIONAL)

`ResolutionSync.runOnce()` is idempotent, cursor-backed and cheap, and it is
what turns venue evidence into `call_results`. Nothing schedules it today, so it
advances only when something calls it.

```ts
  // Packet D — derive call_results from Packet B's venue resolutions.
  // Idempotent and cursor-backed: running it twice changes nothing, and a
  // restart repairs from venue history (contracts §0.2).
  const calls = callsRuntimeFor(config);
  calls.attachReceipts(store);            // arena-era receipts; returns an unsubscribe
  const syncTimer = setInterval(() => {
    try {
      calls.sync.runOnce();
    } catch (e) {
      console.error("[calls] resolution sync failed", e);
    }
  }, 30_000);
  syncTimer.unref?.();
```

`callsRuntimeFor` is exported from `src/calls/runtime.ts`. Calling it from the
composition root and from a procedure yields the SAME runtime (it is memoised on
the config object), so there is no double store and no double subscription —
`attachReceipts` is itself idempotent and returns the same thunk on a second
call.

**Degraded without it:** results settle only when `runOnce()` is invoked. A
future `calls.sync` ops procedure, a cron, or a pull-to-refresh all work; the
correctness properties do not depend on the schedule.

---

## 5. Explicitly NOT requested

- **No change to `src/domain/**`.** No new variant on the `DomainEvent` union
  was needed. The receipt event shapes are declared inside `src/calls/receipts.ts`,
  and the arena-era generalisation reads the EXISTING `CallMade` / `CallSettled`
  / `CallVoided` payloads. `Bucket` is an open string brand (§1), so `'YES'` and
  `'NO'` already type-check as buckets with zero changes.
- **No change to `src/core/projections/ReadModel.ts`.** §6 calls its hardcoded
  projection array "friction, not a seam". `CallReceiptsProjection.attach(store)`
  tails `EventStore.subscribe()` independently and returns its unsubscribe thunk;
  `tests/socialCallsReceipts.test.ts` proves a second subscriber still receives
  every event, so nothing existing is disturbed.
- **No change to `src/api/predictions.ts`, `src/prediction/**` or
  `src/auth/**`.** Packet B's store is read through a narrow port
  (`src/calls/markets.ts`) composed from its public interface, and Packet A's
  runtime is used exactly as it is.
- **No change to `src/social/SocialStore.ts`.**
- **No new package.** Zero new dependencies.
- **No migration outside `*_social_calls_*.sql`**, and no modification to any
  existing migration or to any table Packet A or B created.

---

## 6. The migrations, and how they were verified

Three additive migrations were added to `supabase/migrations/`:

| File | Table |
| --- | --- |
| `20260913140000_social_calls_calls.sql` | `public.calls` |
| `20260913140500_social_calls_responses.sql` | `public.call_responses` |
| `20260913141000_social_calls_results.sql` | `public.call_results` |

Each aborts loudly if `public.current_app_user_id()` is absent, the way Packet
B's orders migration does, and each follows the §5 template (RLS enabled,
`REVOKE ALL` from `anon, authenticated`, `GRANT ALL` to `service_role`, pinned
`search_path` on every new function, `REVOKE`/`GRANT` on every new function, no
`CREATE OR REPLACE`, and no `USING (true)` policy anywhere).

**They were applied and exercised on a throwaway PostgreSQL 15 cluster** created
in a temp directory and destroyed afterwards — no live database, no provider, no
cluster that already existed. 61 behavioural checks passed: every immutable
column refused, hard DELETE refused for service_role AND superuser, the full
result truth table including VOID, a settled result refusing an override, the
two-user public/followers visibility rules for `anon`, a follower and a
stranger, a client's INSERT/UPDATE/DELETE on `call_results` refused, and the
soft delete hiding a call while its `call_results` row survived unrewritten.

**Before applying to the live project**, contract §9 still stands: the
repository schema is not the live schema, so dump `pg_policies`,
`information_schema.columns` and `pg_proc` and reconcile first. These migrations
are purely additive — they create three new tables and four new functions and
alter nothing that exists — which is the category §9 calls safe. The one thing
worth confirming on the live database is that `public.follows` really has
`follower_user_id` / `followee_user_id` (the `calls_followers_select` policy
reads them) and that `public.venue_markets` and `public.market_resolutions` are
present from Packet B.

---

## 7. One contract ambiguity, and how Packet D resolved it

§3 freezes `marketId`, `side`, `entryProbability`, `snapshotId`, `createdAt` and
"the free/funded provenance" after `lockedAt`. It says nothing about `thesis`,
`confidence`, `visibility`, `parentCallId`, `userId` or `lockedAt` itself.

§0.1 says a call is "a free, **immutable**, timestamped statement by a person".

Packet D treated §3's list as the **floor, not the ceiling**, and froze those six
as well — so the only columns any writer may change after insert are `hidden_at`
and `hidden_reason`. A call whose thesis can be rewritten after the answer is
known is not a receipt, and an audience that can be widened retroactively makes
"who could see this when it was made" unanswerable.

`funding_state` is included in the frozen set for the same reason: a row that
could walk `NONE -> FILLED` would be exactly the free/funded provenance
changing. A funded artefact is a separate `venue_positions` row that REFERENCES
a call (§0.1), never this column moving.

**If integration disagrees**, the change is small and local: remove the entries
from `IMMUTABLE_CALL_FIELDS` in `src/calls/store.ts` and the matching `IF`
blocks from `public.calls_guard_immutability()`. The test
`tests/socialCallsImmutability.test.ts` is generated from that same list and
asserts the SQL covers it, so the two can never drift apart.
