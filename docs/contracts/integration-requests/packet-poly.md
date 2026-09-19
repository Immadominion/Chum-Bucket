# Integration requests — Packet POLY (read-only Polymarket venue)

A real, read-only venue adapter for Polymarket's public gamma REST API
(`https://gamma-api.polymarket.com`). No API key, no credential, no invented data.
The roadmap sanctions it: *"use Polymarket and/or Kalshi public REST only through
another normalized READ-ONLY adapter. Keep their native rules/results and disable
trading."*

**What landed without integration** (all in files Packet B owns):

| File | Status |
| --- | --- |
| `src/prediction/PolymarketVenue.ts` | new — the only file that knows Polymarket's wire shape |
| `src/prediction/config.ts` | edited — `PREDICTION_VENUE=polymarket` resolution + optional `polymarket` block |
| `src/prediction/runtime.ts` | edited — venue selection extracted into `buildVenue()` |
| `src/prediction/index.ts` | edited — one re-export |
| `tests/polymarket*.ts` | new — 85 tests over RECORDED live responses; the suite makes no network call |

**Nothing is blocked.** The adapter compiles, is selectable, and is fully tested
against the current frozen types. The two requests below remove two documented
workarounds; until they land, the workarounds are correct, contained, and
commented at the point of use.

---

## 1. `src/prediction/types.ts` + contracts §3 — add `'polymarket'` to `VenueId` (REQUIRED)

**Why it cannot be avoided:** `VenueId` is `'jupiter' | 'fixture'` — a closed union,
frozen by `pivot-contracts-v1.md` §3, with the same names in Dart. A third real
venue cannot be named without widening it. Widening a frozen type silently is
exactly what §3 forbids, so the adapter compiles against the union as it stands
through **one documented cast in one place**:

```ts
// src/prediction/PolymarketVenue.ts
export const POLYMARKET_VENUE_NAME = "polymarket";
export const POLYMARKET_VENUE_ID = POLYMARKET_VENUE_NAME as unknown as VenueId;
```

Every other line in the adapter uses `POLYMARKET_VENUE_ID`, so applying the patch
below and deleting the cast changes nothing else.

**Exact patch:**

```diff
--- a/src/prediction/types.ts
+++ b/src/prediction/types.ts
@@
-/** Which adapter produced a row. 'fixture' is ALWAYS demo data. */
-export type VenueId = "jupiter" | "fixture";
+/**
+ * Which adapter produced a row. 'fixture' is ALWAYS demo data; 'jupiter' and
+ * 'polymarket' are live venues. 'polymarket' is READ-ONLY: it can never carry a
+ * funded position, because its adapter refuses every order path.
+ */
+export type VenueId = "jupiter" | "fixture" | "polymarket";
```

and, in `docs/contracts/pivot-contracts-v1.md` §3:

```diff
 interface VenueMarket {
   id: string;                    // Chumbucket UUID — the stable id everything references
-  venue: 'jupiter' | 'fixture';  // 'fixture' = demo catalog; MUST be visibly labelled in UI
+  venue: 'jupiter' | 'fixture' | 'polymarket';  // 'fixture' = demo catalog; MUST be
+                                 // visibly labelled in UI. 'polymarket' is a live,
+                                 // READ-ONLY venue: real markets, real resolutions,
+                                 // no trading.
```

**What breaks without it:** nothing at runtime — the cast is sound and every
`VenueId` consumer treats the value as an opaque string. What suffers is honesty:
`grep VenueId` does not tell a reader that a third venue exists, and a future
exhaustive `switch` over `VenueId` would compile while silently missing
Polymarket.

**Risk:** low, but non-zero and worth naming. Two existing expressions become
non-exhaustive in meaning (not in types):

- `PredictionVenue.ts:225` — `venueIsDemo = (v) => v === "fixture"` → correct for
  Polymarket (`false`). No change needed.
- `PredictionService.ts:96` — `get venueId() { return this.venue.capabilities().demo ? "fixture" : "jupiter"; }`
  would report `"jupiter"` for a Polymarket service. **This getter is dead code
  today** (`grep` finds no caller anywhere in `src/` or `tests/`), which is why
  Packet POLY did not touch it. It should be deleted or re-derived from the
  adapter's own `venue` field when this patch lands.

**Mobile:** `ArenaBucketIndex.fromLabel` and the Dart venue vocabulary need the
same member if a Polymarket row is ever rendered. That is Packet C's switch, not
this request's.

---

## 2. `src/config.ts` — let `PREDICTION_VENUE=polymarket` through (REQUIRED for production wiring)

**Why it cannot be avoided:** `loadConfig()` collapses the environment variable to
`'jupiter' | 'fixture'` before `resolvePredictionConfig()` ever sees it:

```ts
// src/config.ts:278 (today)
cfg.predictions = {
  venue: env.PREDICTION_VENUE === "jupiter" && env.JUPITER_API_KEY ? "jupiter" : "fixture",
  ...
};
```

So `PREDICTION_VENUE=polymarket` arrives at Packet B's resolver already rewritten
to `"fixture"`. The workaround, commented in `src/prediction/config.ts`, is that
an explicit `PREDICTION_VENUE=polymarket` **in the environment** wins over the
coerced AppConfig value:

```ts
const asked =
  env.PREDICTION_VENUE === POLYMARKET_VENUE_ID
    ? POLYMARKET_VENUE_ID
    : (fromApp?.venue ?? env.PREDICTION_VENUE);
```

That is correct in production (where `loadConfig(process.env)` and the resolver
read the same environment) but wrong-feeling: the typed config object disagrees
with the venue actually served, and anything constructing an `AppConfig` from an
injected env map (tests, scripts) does not get the venue it asked for.

**Exact patch:**

```diff
--- a/src/config.ts
+++ b/src/config.ts
@@
   predictions?: {
-    venue?: "jupiter" | "fixture";
+    venue?: "jupiter" | "fixture" | "polymarket";
     jupiter?: { baseUrl?: string; apiKey: string; timeoutMs?: number };
+    /**
+     * Polymarket's gamma REST API is PUBLIC, unauthenticated and read-only.
+     * There is no key here and none is accepted. The adapter refuses every
+     * order/position/claim path, so this venue can never hold funded money.
+     */
+    polymarket?: { baseUrl?: string; timeoutMs?: number };
     flags?: { fundedPositions?: boolean };
   };
@@
-  // With no Jupiter key configured the BFF serves the clearly-labelled fixture
-  // catalog rather than failing; funded_positions stays OFF unless enabled.
-  cfg.predictions = {
-    venue: env.PREDICTION_VENUE === "jupiter" && env.JUPITER_API_KEY ? "jupiter" : "fixture",
+  // With no Jupiter key configured the BFF serves the clearly-labelled fixture
+  // catalog rather than failing; funded_positions stays OFF unless enabled.
+  // Polymarket needs no key, so asking for it always works.
+  cfg.predictions = {
+    venue:
+      env.PREDICTION_VENUE === "polymarket"
+        ? "polymarket"
+        : env.PREDICTION_VENUE === "jupiter" && env.JUPITER_API_KEY
+          ? "jupiter"
+          : "fixture",
+    polymarket: {
+      baseUrl: env.POLYMARKET_BASE_URL ?? "https://gamma-api.polymarket.com",
+      timeoutMs: num(env.POLYMARKET_TIMEOUT_MS, 8_000),
+    },
     ...(env.JUPITER_API_KEY
```

Then delete the `env.PREDICTION_VENUE === POLYMARKET_VENUE_ID` branch at the top
of `resolvePredictionConfig()` in `src/prediction/config.ts`; everything else
there already reads `fromApp?.polymarket` first.

**What breaks without it:** `PREDICTION_VENUE=polymarket` still works in a real
deployment, but `loadConfig({ PREDICTION_VENUE: "polymarket" }).predictions.venue`
reads `"fixture"` — a typed config that contradicts the venue actually served.
`tests/polymarketRuntime.test.ts` asserts both halves of that discrepancy, so the
test will need its second assertion updated when the patch lands.

**Risk:** none to existing behaviour. `PREDICTION_VENUE` values other than the
three known ones still fall back to `"fixture"`, and the Jupiter branch is
untouched.

---

## 3. Not an integration request — two follow-ups Packet B owns

Recorded here so they are not lost.

1. **A `VENUE_UNSUPPORTED` error code.** The read-only refusals
   (`createBuyOrder`, `getOrder`, `listPositions`, `closePosition`,
   `createClaim`) currently throw `VENUE_MISCONFIGURED`, which is the closest
   existing member of `VenueErrorCode`: thrown before any network call, not
   retryable, not a circuit fault — all correct. But it reads as "someone
   mis-configured this", when the truth is "this venue never supports that".
   Adding `VENUE_UNSUPPORTED` to `src/prediction/errors.ts` is a one-line,
   Packet-B-owned change; it was left out to keep this packet's diff to the
   files it was scoped to.

2. **Listing defaults are opinionated, and deliberately so.** `listEvents()` with
   no status filter asks gamma for `closed=false`, `end_date_min=<now>`, ordered
   by `volume24hr` descending. Left to gamma's own defaults the first page is
   markets that ended in 2020; ordered by `endDate` ascending it is five-minute
   "Up or Down" crypto ticks and sports totals, none of which are YES/NO binaries
   the frozen types can hold — the page comes back empty. These are orderings of
   the venue's own data, not judgements about it, and a caller who wants settled
   or expired markets reaches them by `status` filter or by id. Revisit if the
   product wants a different front page.

3. **No order-book depth.** gamma publishes `bestBid`/`bestAsk` but no sizes;
   real depth lives on Polymarket's CLOB (`clob.polymarket.com`), which this
   read-only adapter deliberately does not call. `getOrderbook` therefore returns
   **empty** `bids`/`asks` with a real `snapshot` (the venue's own published YES
   price). Fabricating a size at `bestBid` would be precisely the invented number
   this work exists to avoid. If depth is ever needed, it is a second adapter
   against the CLOB read API, not a change here.

---

## 4. What the frozen contract cannot express (for the record)

Three real Polymarket behaviours have no faithful home in §3's vocabulary. Each
is mapped to the safest available member and the venue's own flags are preserved
verbatim in `rawStatus`, so nothing is hidden:

1. **Past `endDate`, still `closed: false` and `acceptingOrders: true`.** Real and
   common (market `1642010` has `endDate` 2025-10-31, `startDate` 2026-03-18 —
   later than its own end date — and is still quoting). It is not OPEN (its
   deadline passed), not CLOSED_PENDING_RESOLUTION (the venue has not closed it),
   and certainly not RESOLVED. Mapped **PAUSED**, the only member that asserts
   nothing about closure or outcome and that §3 describes as "may reopen" —
   which is exactly what happens when Polymarket extends the date.

2. **No `CANCELLED`, ever.** gamma's market payload carries no void/cancel flag.
   A voided market therefore reports CLOSED_PENDING_RESOLUTION with no
   resolution, rather than being guessed as CANCELLED/`VOID`.

3. **`category`.** gamma's taxonomy is tag-based and lives on the *event*; a
   single-market read returns an event stub with an empty `tags` array. The
   adapter uses the requested category when one was passed through as
   `tag_slug`, else the event's first tag slug verbatim, else the sentinel
   `"other"`. It never invents a taxonomy.
