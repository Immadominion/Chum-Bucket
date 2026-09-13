# Chumbucket pivot contracts v1 — FROZEN

**Frozen:** 13 September 2026 · **Owner:** integration · **Gates:** Packets A, B, C

Derived from a full read of both baselines (`cc8acaa` mobile, `ccac2c4` API) and the complete Supabase migration chain. Every claim below cites real identifiers. Packets A, B and C build against **this document**, not against each other.

Change process: a packet that needs a change to a frozen contract raises it to the integration owner; it does not edit this file.

---

## 0. The three invariants everything else serves

1. **A call is not a trade.** A call is a free, immutable, timestamped statement by a person. A funded venue position is an optional, separately-authorised artefact that *references* a call. Neither implies the other.
2. **The venue is the only source of a result.** No client, no admin, no friend and no model may write a resolution. Only the BFF synchroniser, from venue evidence.
3. **Identity is `public.users.id`.** A wallet is a linked credential. `auth.uid()` maps to the canonical user; nothing authorises on a wallet string.

---

## 1. What the baseline already gives us for free

Confirmed by reading, not assumed:

| Seam | Why it matters |
| --- | --- |
| `Bucket = Brand<string,'Bucket'>` (`src/domain/ids.ts:17`) — an open string brand, **not** a `HOME\|DRAW\|AWAY` union | `'YES'` and `'NO'` are already legal Buckets. `CallMade.bucket`, `PotSettled.winningBucket`, `MarketDef.buckets` and `Outcome` accept them with **zero type changes**. |
| `Outcome = Bucket \| 'VOID'` (`src/domain/model.ts:78`) | Already expresses `YES \| NO \| VOID`. Do not invent a new enum. |
| `StoredEvent<E>` / `EventMeta` (`src/domain/events.ts:323`) | Payload-agnostic. New event families replay untouched. |
| `Projection` (`src/core/projections/Projection.ts:9`) — `{ name, apply(event) }` | A new projection is one file. Every existing `apply` is a `switch` with `default: return`, so old projections ignore new events silently. |
| `EventStore.subscribe()` (`EventStore.ts:37`) returns an unsubscribe thunk and is **not exclusive** | A venue-receipt read side can tail the live log entirely outside `ReadModel`. |
| tRPC nesting by object key (`src/api/router.ts:53`) | A sub-router is one added key. No `mergeRouters`, no registry. |
| `ctx.app.config` (`src/api/trpc.ts:14`) | New modules read config without editing `createApp`. |
| `ChumbucketTabs`, `ChumbucketWavySheet`, `ChumbucketAppHeader`, `CallerProfileScreen(walletAddress)` | The social shell is already generic. Reuse verbatim. |
| `_postMutation(procedurePath, input)` (`arena_backend_service.dart:458`) | A new BFF procedure is a ~10-line Dart method on the existing transport. |
| `ArenaFeedMode { global, following }` (`arena_provider.dart:17`) | Feed-mode machinery is one enum + one branch. |

**The single largest free win: `Bucket` is an open string.** The YES/NO generalisation is a data change, not a type migration.

---

## 2. What blocks us (measured, with the decision taken)

| Blocker | Evidence | Decision |
| --- | --- | --- |
| `prediction_positions.match_id` is `NOT NULL`, and `open_tx_signature` is `NOT NULL` | `20260715134226_social_predictions_foundation.sql:207-211` | **Do not reuse this table for calls.** A free call has no fixture and no transaction. New `calls` table. |
| `prediction_markets.match_id` is `NOT NULL` | same migration, `:176-183` | **New `venue_markets` table.** Relaxing a legacy `NOT NULL` is a rewrite, not an addition. |
| Legacy RLS policies are `USING (true)` and PostgreSQL ORs permissive policies together | `prediction_positions_public_select`, `claims_public_select`, `settlement_receipts_public_select`, … | Adding a tight policy beside a `USING (true)` policy is a **no-op**. The pivot therefore lands on **new tables with default-deny**, not on hardened legacy ones. |
| **No `auth.uid()` exists anywhere in the schema.** Nothing links `public.users` to `auth.users`. | grep finds it only in a comment at `database_migrations/001_complete_schema.sql:474` | Packet A's first migration. Everything else depends on it. |
| `ArenaBucketIndex.fromLabel` **throws** on any label outside HOME/DRAW/AWAY/OVER/UNDER | `arena_models.dart:30` | Packet C adds `YES`/`NO` cases. One switch, every bucket-aware model follows. |
| No router, no named routes, no deep-link package. Only intent filter is the Supabase OAuth callback. | `lib/shared/screens/home/home.dart:224` | Deep linking is **new work** in Packet C, not a reuse. Scope it explicitly. |
| `SocialStore` uses the **service-role key** for every call — RLS is bypassed by construction | `src/social/SocialStore.ts:197` | Authorisation must be enforced in the tRPC layer *and* by RLS for direct-from-mobile reads. The two are not interchangeable. |

---

## 3. Normalized vocabulary — frozen

Identical names in TypeScript and Dart. Wire format is JSON; all timestamps are **unix milliseconds (integer, UTC)**; all probabilities are **`number` in `[0,1]`**; all money is **integer base units as a string** on the wire (never a float).

```ts
type Side       = 'YES' | 'NO';
type Resolution = 'YES' | 'NO' | 'VOID';          // VOID = cancelled/abandoned; never a win or a loss

type MarketStatus =
  | 'OPEN'                        // accepting calls and (if funded) orders
  | 'CLOSED_PENDING_RESOLUTION'   // closed, outcome not yet published
  | 'RESOLVED'                    // venue published a Resolution
  | 'CANCELLED'                   // venue voided the market
  | 'PAUSED';                     // venue halted trading, may reopen

type CallOutcome = 'PENDING' | 'CORRECT' | 'INCORRECT' | 'VOID';

type FundingState =
  | 'NONE'       // free call — the default, and the only state the MVP ships
  | 'QUOTED'     // a fresh quote was shown; nothing signed
  | 'SUBMITTED'  // transaction signed and sent; NOT yet money
  | 'FILLED'     // venue CONFIRMED the fill — the only state that may read "funded"
  | 'PARTIAL'
  | 'FAILED'
  | 'CLOSED'
  | 'CLAIMABLE'
  | 'CLAIMED';
```

**Never collapse `MarketStatus`.** `CLOSED_PENDING_RESOLUTION`, `CANCELLED` and `RESOLVED` are three different things and the UI must render them differently.

**`FILLED` is the only state the word "funded" may appear for.** A tap, a signature and a submitted transaction are all `SUBMITTED`.

### Normalized market

```ts
interface VenueMarket {
  id: string;                    // Chumbucket UUID — the stable id everything references
  venue: 'jupiter' | 'fixture';  // 'fixture' = demo catalog; MUST be visibly labelled in UI
  venueEventId: string;
  venueMarketId: string;         // preserved verbatim, never re-encoded
  question: string;              // the exact question shown to the user
  rulesText: string;             // the venue's exact resolution criteria — never paraphrased
  category: string;              // 'crypto' for MVP
  outcomes: { side: Side; label: string }[];
  status: MarketStatus;
  rawStatus: string;             // the venue's own status string, unmapped
  opensAt: number | null;
  closesAt: number | null;
  resolvesAt: number | null;
  resolutionSource: string | null;
  lastSyncedAt: number;
  payloadVersion: number;        // bump when the adapter's normalisation changes
}
```

### Normalized snapshot, call, response, result

```ts
interface MarketSnapshot {
  marketId: string;
  yesProbability: number;        // [0,1]
  observedAt: number;
  source: 'venue' | 'fixture';
}

interface Call {
  id: string;
  userId: string;                // canonical public.users.id — NEVER a wallet
  marketId: string;
  side: Side;
  confidence: number | null;     // [0,1], self-reported, optional
  thesis: string | null;         // <= 280 chars
  entryProbability: number | null;
  snapshotId: string | null;
  visibility: 'public' | 'followers';
  createdAt: number;
  lockedAt: number;              // immutable from this instant
  parentCallId: string | null;   // set when this call came from a Back/Fade
  fundingState: FundingState;    // 'NONE' for a free call
}

interface CallResponse {
  id: string;
  actorUserId: string;
  targetCallId: string;
  kind: 'back' | 'fade' | 'challenge';
  resultingCallId: string | null; // back/fade ALWAYS create the actor's own call
  createdAt: number;
}

interface CallResult {
  callId: string;
  outcome: CallOutcome;
  resolution: Resolution | null;
  resolvedAt: number | null;
  marketResolutionId: string | null;  // the venue evidence this was derived from
  derivedAt: number;
}
```

**Immutable after `lockedAt`:** `marketId`, `side`, `entryProbability`, `snapshotId`, `createdAt`, and the free/funded provenance. Deleting a public call hides it from distribution; it does **not** rewrite `CallResult` or accuracy history.

### Deterministic result derivation — the only permitted rule

```
resolution === 'VOID'            -> VOID
resolution === call.side         -> CORRECT
resolution is the other side     -> INCORRECT
no resolution yet                -> PENDING
```

Late resolution stays `PENDING`. There is no other branch, no admin override, and no client input.

---

## 4. `PredictionVenue` — the only interface that may know a provider's wire shape

```ts
interface PredictionVenue {
  listEvents(filters: EventFilters, cursor?: string): Promise<EventPage>;
  getMarket(venueMarketId: string): Promise<VenueMarket>;
  getOrderbook(venueMarketId: string): Promise<Orderbook>;
  getTradingStatus(): Promise<TradingStatus>;
  createBuyOrder(o: CreateOrderInput): Promise<UnsignedOrder>;   // requires idempotencyKey
  getOrder(orderId: string): Promise<VenueOrder>;
  listPositions(owner: string, cursor?: string): Promise<PositionPage>;
  closePosition(owner: string, positionId: string): Promise<UnsignedOrder>;
  createClaim(owner: string, positionId: string): Promise<UnsignedTransaction>;
  capabilities(): Capabilities;  // { read, trade, liveScores, stream, geoGate, kyc,
                                 //   executionModel, minimumOrder, claimMode }
}
```

Rules:
- Jupiter JSON appears in **exactly one file**. Everything downstream sees `VenueMarket`.
- Store the raw provider payload for debugging **and** the versioned normalized form.
- A schema change must fail loudly at the adapter, never silently corrupt a call or receipt.
- The API key is server-side only. It is never in a response body, a log line, or a client.
- `fixture` venue data must be visibly labelled as demo and can never present as a live result.

---

## 5. Database — additive only, new tables, default-deny

Migration prefix per packet so three agents never collide in one file:

| Packet | Migration name pattern |
| --- | --- |
| A | `2026MMDDHHMMSS_auth_identity_<topic>.sql` |
| B | `2026MMDDHHMMSS_venue_market_<topic>.sql` |
| C | `2026MMDDHHMMSS_social_calls_<topic>.sql` |

### Mandatory template for every new table

```sql
ALTER TABLE public.<t> ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.<t> FROM anon, authenticated;
GRANT ALL ON public.<t> TO service_role;
```

Established at `20260719160000_security_hardening_rls_pii.sql:32-34`. Then add `auth.uid()`-scoped policies on top. **Never** a `USING (true)` policy on a new table.

Every new function:

```sql
CREATE FUNCTION public.<f>(...) RETURNS ...
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED. CREATE OR REPLACE drops this if omitted.
AS $$ ... $$;
REVOKE EXECUTE ON FUNCTION public.<f>(...) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.<f>(...) TO service_role;
```

**Do not `CREATE OR REPLACE` an existing function.** `record_prediction_call` has been redefined three times and the latest redefinition (`20260719170000`) silently reverted a settled-position guard *and* dropped its `search_path` pin. Write new, separately-named functions.

### Tables

**Packet A**
- `ALTER TABLE public.users ADD COLUMN IF NOT EXISTS auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;` + index. Purely additive; touches no policy and no existing column.
- `public.current_app_user_id() RETURNS uuid STABLE SECURITY DEFINER` → `SELECT id FROM public.users WHERE auth_user_id = auth.uid()`. **Every** new policy reads `USING (user_id = public.current_app_user_id())`.
- `wallet_nonces` — hashed nonce (never the plaintext), intended user/address/purpose, domain, uri, network, `expires_at`, `consumed_at`. Single-use, consumed atomically. Service-role only.
- `legacy_identity_claims` — private legacy→canonical mapping with audited state. Service-role only, never client-readable.
- `linked_wallets` additive columns: `siws_proof_version`, `verified_at`, `revoked_at`, plus a partial unique index so one active address maps to one user.

**Packet B**
- `venue_markets`, `market_snapshots`, `market_resolutions` — market data is public-readable; resolutions are **service-write only**.
- `venue_orders`, `venue_positions` — owner-scoped read via `current_app_user_id()`, service-write only. A row may only reach `FILLED` from a reconciliation write.

**Packet C**
- `calls`, `call_responses`, `call_results`.
- `calls`: public rows readable by anyone; a `followers` row readable only by a follower or the author. Insert only as `current_app_user_id()`. **No UPDATE policy on the immutable columns.**
- `call_results` is service-write only.

---

## 6. Ownership — no two packets touch the same file

| | Packet A (identity) | Packet B (venue BFF) | Packet C (mobile slice) |
| --- | --- | --- | --- |
| **API owns** | `src/auth/**`, new `src/api/authRoutes.ts` | new `src/prediction/**`, new `src/api/predictions.ts` | — |
| **Mobile owns** | `lib/features/authentication/**`, wallet-link domain | — | `lib/features/calls/**`, `lib/features/receipts/**`, reusable feed/profile subset |
| **Migrations** | `*_auth_identity_*.sql` | `*_venue_market_*.sql` | `*_social_calls_*.sql` |

**Integration owner alone** touches: `src/app.ts`, `src/api/router.ts`, `src/api/trpc.ts`, `src/config.ts`, `src/domain/**`, `src/core/projections/ReadModel.ts`, `lib/main.dart`, `pubspec.yaml`, `bun.lock`, `lib/shared/screens/home/home.dart`, and bottom navigation.

Packets needing a change in an integration-owned file: write the exact patch into `docs/contracts/integration-requests/<packet>.md` and keep building against a local fixture.

`ReadModel.ts:36-42` is a hardcoded projection array and is **friction, not a seam**. Packet B must not edit it; tail `EventStore.subscribe()` independently instead.

---

## 7. Feature flags

| Flag | Default | Meaning |
| --- | --- | --- |
| `call_receipt_experience` | on | The free social loop. |
| `funded_positions` | **off** | All funded UI and every order/claim route. Server-side kill switch; disabling it must leave reading, free calls and receipts fully usable. |
| `x_login` | off | X OAuth. |

`funded_positions` is enforced **server-side**. A client flag alone is not a kill switch.

---

## 8. Pre-existing security findings that constrain the work

These are **live issues in the current production app**, found while mapping. They are not introduced by the pivot, and none has been touched.

1. `GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated` (`001_complete_schema.sql:587`) with `users_insert WITH CHECK (true)` and `users_update USING (true)`. The July hardening revoked **SELECT only**. Anon can therefore still rewrite any `public.users` row — including repointing `wallet_address` — and insert new ones.
2. `sync_user_by_wallet` is deliberately anon-executable and mints canonical users, upserting `ON CONFLICT (wallet_address) DO UPDATE SET user_id = EXCLUDED.user_id`. Anyone can claim the globally-unique wallet slot for a wallet they do not control. **This must stop being the account-creation path** under Packet A.
3. `notification_outbox` is world-readable (`USING (true)`), and `get_notifications(p_network, p_wallet)` / `unread_notification_count` / `pending_targets_for_wallet` are `SECURITY DEFINER` and were never revoked from anon. Any anon caller reads any wallet's inbox by passing that wallet string.
4. Several tRPC read procedures take `wallet: z.string()` on `publicProcedure` with no proof at all, notifications included.
5. `20260719170000_no_client_forged_verified.sql` re-created `record_prediction_call` from the older body, reverting the settled-position guard (a replayed call can now rewrite a `CLAIMED` position's bucket and stake and reset it to `OPEN`) and dropping its `search_path` pin.
6. `prediction_activity` dedupes on `UNIQUE(network, tx_signature, type)` with `tx_signature` nullable. Postgres treats NULLs as distinct, so off-chain activity never conflicts and duplicates without bound.

**These are why the pivot lands on new default-deny tables rather than on hardened legacy ones.** Fixing 1–3 is a production change requiring founder approval and is tracked separately from packet work.

---

## 9. Verify against the live database before writing migrations

The repository schema is **not** the live schema. The eight `*_remote_baseline.sql` files are two-line placeholders stating the migration was already applied before the repo gained Supabase CLI history, and the Flutter client reads `fcm_tokens`, `user_challenge_summary` and `challenge_stats`, none of which is defined in any SQL file here. Three policies in `002_mwa_wallet_auth.sql` use `CREATE POLICY IF NOT EXISTS`, which is **invalid PostgreSQL** and would have aborted — so whether they exist is unknown.

Before any migration is applied, dump `pg_policies`, `information_schema.columns` and `pg_proc` from the live project and reconcile. Writing additive new tables is safe without this; **altering anything existing is not**.
