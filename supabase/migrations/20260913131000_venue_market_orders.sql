-- ============================================================================
-- PACKET B — venue_orders + venue_positions
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §3 (FundingState), §5 (owner-scoped read via
--           current_app_user_id(), service-write only, "a row may only reach
--           FILLED from a reconciliation write"), §7 (funded_positions)
-- ============================================================================
--
-- THE ONE RULE THIS FILE EXISTS FOR
--
--   §3: "FILLED is the only state the word 'funded' may appear for. A tap, a
--   signature and a submitted transaction are all SUBMITTED."
--   §5: "A row may only reach FILLED from a reconciliation write."
--
-- That is encoded here twice, in two mechanisms with different failure modes,
-- because a comment is not an invariant:
--
--   1. A CHECK CONSTRAINT (venue_orders_filled_requires_evidence) makes a FILLED
--      row without confirmed venue evidence structurally unrepresentable. It
--      holds for every writer, every backfill, and every hand-typed UPDATE.
--   2. A BEFORE INSERT/UPDATE TRIGGER additionally polices the TRANSITION: an
--      order may not be INSERTed as FILLED, may only enter FILLED from
--      SUBMITTED or PARTIAL, and may never regress out of FILLED. A CHECK sees
--      only the new row; only a trigger can see that the row used to be QUOTED.
--
-- Both bind service_role, which RLS does not. That matters here more than
-- anywhere else in the schema: SocialStore uses the service-role key for every
-- call (§2), so RLS alone protects nothing against our own backend's bugs.
--
-- DEPENDENCY: public.current_app_user_id() from Packet A's auth-identity
-- migration. §5 requires every new policy to read it. The guard below fails
-- loudly rather than creating a policy that silently references nothing.
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION
      'venue_market_orders requires public.current_app_user_id() (Packet A: *_auth_identity_* migrations). Apply the auth-identity migrations first; contracts §5 requires every new policy to scope on it.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- venue_orders
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.venue_orders (
  -- The BFF/venue order id. Ours to own; it may never change hands.
  order_id TEXT PRIMARY KEY,
  -- Identity is public.users.id (§0.3). A wallet is a linked credential; nothing
  -- authorises on a wallet string, so the RLS scope is user_id, not owner_address.
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- The venue-side account handle the order trades for. Descriptive, never
  -- authoritative.
  owner_address TEXT NOT NULL,
  venue TEXT NOT NULL,
  venue_market_id TEXT NOT NULL,
  market_id UUID REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  side TEXT NOT NULL,
  -- Money is integer base units (§3). NUMERIC(38,0) — never a float.
  amount_base_units NUMERIC(38, 0) NOT NULL,
  filled_base_units NUMERIC(38, 0) NOT NULL DEFAULT 0,
  funding_state TEXT NOT NULL DEFAULT 'QUOTED',

  -- ── confirmed-fill evidence. All of it, or the state is not FILLED. ──
  venue_order_id TEXT,
  fill_tx_signature TEXT,
  fill_evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  reconciliation_source TEXT,
  reconciled_at TIMESTAMPTZ,

  -- ── idempotency: the same key must never create two orders ──
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,

  is_demo BOOLEAN GENERATED ALWAYS AS (venue = 'fixture') STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT venue_orders_venue_check CHECK (venue IN ('jupiter', 'fixture')),
  CONSTRAINT venue_orders_side_check CHECK (side IN ('YES', 'NO')),
  -- The nine FundingState values are frozen (§3).
  CONSTRAINT venue_orders_state_check CHECK (
    funding_state IN ('NONE', 'QUOTED', 'SUBMITTED', 'FILLED', 'PARTIAL', 'FAILED', 'CLOSED', 'CLAIMABLE', 'CLAIMED')
  ),
  -- 'NONE' means "free call" (§3). An order is by definition not a free call,
  -- so this table may never hold one — that is what keeps §0.1 true: a call is
  -- not a trade, and the two never share a row.
  CONSTRAINT venue_orders_never_free CHECK (funding_state <> 'NONE'),
  CONSTRAINT venue_orders_amount_positive CHECK (amount_base_units > 0),
  CONSTRAINT venue_orders_filled_range CHECK (
    filled_base_units >= 0 AND filled_base_units <= amount_base_units
  ),
  CONSTRAINT venue_orders_reconciliation_source_check CHECK (
    reconciliation_source IS NULL OR reconciliation_source = 'reconciliation'
  ),

  -- ★ THE RULE. A FILLED row is only representable with a reconciliation write
  --   carrying a venue order id, a non-zero filled size, a transaction
  --   signature and the payload it was read from.
  CONSTRAINT venue_orders_filled_requires_evidence CHECK (
    funding_state <> 'FILLED'
    OR (
      reconciliation_source = 'reconciliation'
      AND reconciled_at IS NOT NULL
      AND venue_order_id IS NOT NULL
      AND fill_tx_signature IS NOT NULL
      AND filled_base_units > 0
      AND fill_evidence <> '{}'::jsonb
    )
  ),
  -- The same discipline for a partial fill: money moved, so it must be evidenced.
  CONSTRAINT venue_orders_partial_requires_evidence CHECK (
    funding_state <> 'PARTIAL'
    OR (venue_order_id IS NOT NULL AND filled_base_units > 0)
  ),

  -- One (user, idempotency key) is at most one order, forever.
  UNIQUE (user_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_venue_orders_user
  ON public.venue_orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_venue_orders_open
  ON public.venue_orders (funding_state, updated_at)
  WHERE funding_state IN ('QUOTED', 'SUBMITTED', 'PARTIAL');
CREATE INDEX IF NOT EXISTS idx_venue_orders_market
  ON public.venue_orders (market_id);

-- §5 mandatory template.
ALTER TABLE public.venue_orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.venue_orders FROM anon, authenticated;
GRANT ALL ON public.venue_orders TO service_role;

-- Owner-scoped read only. anon gets nothing at all: an order is money.
GRANT SELECT ON public.venue_orders TO authenticated;

DROP POLICY IF EXISTS venue_orders_owner_select ON public.venue_orders;
CREATE POLICY venue_orders_owner_select ON public.venue_orders
  FOR SELECT
  TO authenticated
  USING (user_id = public.current_app_user_id());

-- No INSERT/UPDATE/DELETE policy: service-write only (§5, Packet B).

-- ---------------------------------------------------------------------------
-- venue_positions
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.venue_positions (
  position_id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  owner_address TEXT NOT NULL,
  venue TEXT NOT NULL,
  venue_market_id TEXT NOT NULL,
  market_id UUID REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  -- The order this position came from — the audit trail from "quote" to "money".
  source_order_id TEXT REFERENCES public.venue_orders(order_id) ON DELETE RESTRICT,
  side TEXT NOT NULL,
  size_base_units NUMERIC(38, 0) NOT NULL DEFAULT 0,
  average_probability NUMERIC(9, 8),
  funding_state TEXT NOT NULL,
  claimable_base_units NUMERIC(38, 0) NOT NULL DEFAULT 0,
  resolution TEXT,
  reconciled_at TIMESTAMPTZ,
  is_demo BOOLEAN GENERATED ALWAYS AS (venue = 'fixture') STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT venue_positions_venue_check CHECK (venue IN ('jupiter', 'fixture')),
  CONSTRAINT venue_positions_side_check CHECK (side IN ('YES', 'NO')),
  -- A position never exists in 'NONE' (free call) or 'QUOTED' (nothing signed).
  CONSTRAINT venue_positions_state_check CHECK (
    funding_state IN ('SUBMITTED', 'FILLED', 'PARTIAL', 'FAILED', 'CLOSED', 'CLAIMABLE', 'CLAIMED')
  ),
  CONSTRAINT venue_positions_resolution_check CHECK (
    resolution IS NULL OR resolution IN ('YES', 'NO', 'VOID')
  ),
  CONSTRAINT venue_positions_size_range CHECK (size_base_units >= 0),
  CONSTRAINT venue_positions_claimable_range CHECK (claimable_base_units >= 0),
  CONSTRAINT venue_positions_probability_range CHECK (
    average_probability IS NULL OR (average_probability >= 0 AND average_probability <= 1)
  ),
  -- Same rule as venue_orders: FILLED is a reconciliation outcome, with an order
  -- behind it. A position cannot assert "funded" on its own say-so.
  CONSTRAINT venue_positions_filled_requires_reconciliation CHECK (
    funding_state <> 'FILLED'
    OR (reconciled_at IS NOT NULL AND source_order_id IS NOT NULL AND size_base_units > 0)
  )
);

CREATE INDEX IF NOT EXISTS idx_venue_positions_user
  ON public.venue_positions (user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_venue_positions_market
  ON public.venue_positions (market_id);
CREATE INDEX IF NOT EXISTS idx_venue_positions_claimable
  ON public.venue_positions (user_id)
  WHERE funding_state = 'CLAIMABLE';

ALTER TABLE public.venue_positions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.venue_positions FROM anon, authenticated;
GRANT ALL ON public.venue_positions TO service_role;

GRANT SELECT ON public.venue_positions TO authenticated;

DROP POLICY IF EXISTS venue_positions_owner_select ON public.venue_positions;
CREATE POLICY venue_positions_owner_select ON public.venue_positions
  FOR SELECT
  TO authenticated
  USING (user_id = public.current_app_user_id());

-- ---------------------------------------------------------------------------
-- Transition guard. The CHECK above says what a FILLED row must LOOK like; this
-- says how a row is ALLOWED TO GET THERE. A CHECK cannot see the previous state.
-- New, separately-named function; never CREATE OR REPLACE (§5).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.venue_orders_guard_funding_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- An order is born as a quote or a submission. It is never born funded.
    IF NEW.funding_state = 'FILLED' THEN
      RAISE EXCEPTION
        'venue_orders: an order may not be INSERTed as FILLED. FILLED is reachable only from a reconciliation write against an existing SUBMITTED/PARTIAL order (contracts §5).'
        USING ERRCODE = 'raise_exception';
    END IF;
    RETURN NEW;
  END IF;

  -- Entering FILLED.
  IF NEW.funding_state = 'FILLED' AND OLD.funding_state <> 'FILLED' THEN
    IF OLD.funding_state NOT IN ('SUBMITTED', 'PARTIAL') THEN
      RAISE EXCEPTION
        'venue_orders: FILLED may only follow SUBMITTED or PARTIAL (order % was %). A tap, a signature and a submitted transaction are all SUBMITTED (contracts §3).',
        OLD.order_id, OLD.funding_state
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.reconciliation_source IS DISTINCT FROM 'reconciliation'
       OR NEW.reconciled_at IS NULL
       OR NEW.venue_order_id IS NULL
       OR NEW.fill_tx_signature IS NULL
       OR COALESCE(NEW.filled_base_units, 0) <= 0
       OR NEW.fill_evidence = '{}'::jsonb THEN
      RAISE EXCEPTION
        'venue_orders: order % may not become FILLED without a reconciliation write carrying venue_order_id, fill_tx_signature, filled_base_units > 0 and fill_evidence.',
        OLD.order_id
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  -- Leaving FILLED. Money that arrived does not un-arrive; it can only be
  -- closed out or claimed.
  IF OLD.funding_state = 'FILLED'
     AND NEW.funding_state NOT IN ('FILLED', 'CLOSED', 'CLAIMABLE', 'CLAIMED') THEN
    RAISE EXCEPTION
      'venue_orders: a FILLED order may not regress to % (order %).',
      NEW.funding_state, OLD.order_id
      USING ERRCODE = 'raise_exception';
  END IF;

  -- The evidence itself is immutable once written: a confirmed fill may not be
  -- quietly re-pointed at a different transaction.
  IF OLD.fill_tx_signature IS NOT NULL
     AND NEW.fill_tx_signature IS DISTINCT FROM OLD.fill_tx_signature THEN
    RAISE EXCEPTION
      'venue_orders: fill_tx_signature is immutable once a fill is confirmed (order %).', OLD.order_id
      USING ERRCODE = 'raise_exception';
  END IF;

  -- An order never changes hands.
  IF NEW.user_id <> OLD.user_id OR NEW.idempotency_key <> OLD.idempotency_key THEN
    RAISE EXCEPTION
      'venue_orders: user_id and idempotency_key are immutable (order %).', OLD.order_id
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.venue_orders_guard_funding_state() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.venue_orders_guard_funding_state() TO service_role;

DROP TRIGGER IF EXISTS trg_venue_orders_guard_funding_state ON public.venue_orders;
CREATE TRIGGER trg_venue_orders_guard_funding_state
  BEFORE INSERT OR UPDATE ON public.venue_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.venue_orders_guard_funding_state();

CREATE FUNCTION public.venue_positions_guard_funding_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
BEGIN
  IF NEW.funding_state = 'FILLED' AND NEW.reconciled_at IS NULL THEN
    RAISE EXCEPTION
      'venue_positions: position % may not be FILLED without a reconciliation write.', NEW.position_id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.user_id <> OLD.user_id THEN
    RAISE EXCEPTION
      'venue_positions: user_id is immutable (position %).', OLD.position_id
      USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.venue_positions_guard_funding_state() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.venue_positions_guard_funding_state() TO service_role;

DROP TRIGGER IF EXISTS trg_venue_positions_guard_funding_state ON public.venue_positions;
CREATE TRIGGER trg_venue_positions_guard_funding_state
  BEFORE INSERT OR UPDATE ON public.venue_positions
  FOR EACH ROW
  EXECUTE FUNCTION public.venue_positions_guard_funding_state();

COMMENT ON TABLE public.venue_orders IS
  'Funded venue orders (contracts §3/§5). Owner-scoped SELECT via current_app_user_id(); service-write only. FILLED is reachable ONLY from a reconciliation write, enforced twice: a CHECK on the row shape and a BEFORE INSERT/UPDATE trigger on the transition. Both bind service_role, which RLS does not.';
COMMENT ON COLUMN public.venue_orders.funding_state IS
  'FundingState (§3). FILLED is the only state the word "funded" may appear for; a tap, a signature and a submitted transaction are all SUBMITTED.';
COMMENT ON COLUMN public.venue_orders.idempotency_key IS
  'UNIQUE with user_id: the same key must never create two orders.';
COMMENT ON TABLE public.venue_positions IS
  'Funded venue positions (contracts §5). Owner-scoped SELECT via current_app_user_id(); service-write only. FILLED requires a reconciliation write and the source order it came from.';
