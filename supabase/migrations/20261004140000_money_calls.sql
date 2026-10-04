-- Money calls: a call made with an amount (Chumbucket Money v1, MONEY_CALLS_ENABLED).
--
-- Additive and re-runnable: a new table, a guard function and its triggers.
-- No legacy table, policy, grant or function is altered and no existing row is
-- touched. Requires 20260929120000_panta_trade_sessions.sql.
--
-- One row per call that carries money intent. The call itself stays the
-- immutable statement it always was (calls.funding_state is never rewritten);
-- this row says whether the call is still waiting for its trade (PENDING:
-- owner-only, on no record), was funded by a confirmed fill (FUNDED), was kept
-- as a free call by its owner (FREE), or was never finished (EXPIRED).
--
-- call_id has no foreign key on purpose: the BFF writes this row BEFORE the
-- call, so a call can never exist, even for an instant after a crash, without
-- the intent that keeps it private. An intent whose call never landed expires.
--
-- Funded means filled: FUNDED requires a FILLED panta_trade_sessions row for
-- the same person and call (FILLED itself already needs Panta's confirmation
-- plus an RPC-proven USDC debit). EXPIRED is refused while a trade for the call
-- is SUBMITTED or FILLED. A closed money call (EXPIRED or FREE) is funded only
-- by its own last quote (the current attempt's key) whose life ended before
-- the call's did, and never once discarded. A money call is traded only while
-- PENDING: panta_trade_sessions refuses a new or newly signed trade for any
-- other (the direct pantaTrading route cannot resurrect one).
--
-- Private means private: while a money call is not FUNDED its call is its
-- owner's alone, also through the anon/authenticated keys (a RESTRICTIVE
-- SELECT policy on public.calls; money_call_private_v1 answers it).
--
-- Only the BFF (service_role) reads or writes money_calls; anon and
-- authenticated have no rights. History is permanent.
DO $$
BEGIN
  IF to_regclass('public.panta_trade_sessions') IS NULL THEN
    RAISE EXCEPTION 'money_calls requires 20260929120000_panta_trade_sessions.sql';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.money_calls (
  call_id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  side TEXT NOT NULL CHECK (side IN ('YES','NO')),
  kind TEXT NOT NULL CHECK (kind IN ('own','back','fade')),
  target_call_id UUID REFERENCES public.calls(id) ON DELETE RESTRICT,
  amount_base_units NUMERIC(38,0) NOT NULL CHECK (amount_base_units > 0),
  max_slippage_bps INTEGER NOT NULL CHECK (max_slippage_bps BETWEEN 0 AND 500),
  wallet_address TEXT NOT NULL CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  idempotency_key TEXT NOT NULL CHECK (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9_-]{15,95}$'),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  attempts INTEGER NOT NULL DEFAULT 1 CHECK (attempts BETWEEN 1 AND 1000),
  state TEXT NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','FUNDED','FREE','EXPIRED')),
  ended_reason TEXT CHECK (ended_reason IN ('filled','kept_free','discarded','expired','market_closed','not_created')),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key),
  CONSTRAINT money_calls_target_matches_kind CHECK ((kind = 'own') = (target_call_id IS NULL)),
  CONSTRAINT money_calls_reason_matches_state CHECK (
    (state = 'PENDING' AND ended_reason IS NULL) OR
    (state = 'FUNDED' AND ended_reason = 'filled') OR
    (state = 'FREE' AND ended_reason = 'kept_free') OR
    (state = 'EXPIRED' AND ended_reason IN ('discarded','expired','market_closed','not_created'))
  ),
  CONSTRAINT money_calls_expiry_after_creation CHECK (expires_at > created_at)
);
CREATE INDEX IF NOT EXISTS money_calls_user_time ON public.money_calls(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS money_calls_open ON public.money_calls(expires_at) WHERE state = 'PENDING';
ALTER TABLE public.money_calls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.money_calls FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.money_calls TO service_role;
GRANT UPDATE (state, ended_reason, attempts, wallet_address, expires_at, updated_at) ON public.money_calls TO service_role;

CREATE OR REPLACE FUNCTION public.money_calls_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE t public.calls;
BEGIN
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Money call history is permanent'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'PENDING' OR NEW.ended_reason IS NOT NULL OR NEW.attempts <> 1 THEN
      RAISE EXCEPTION 'A money call starts PENDING';
    END IF;
    IF EXISTS (SELECT 1 FROM public.calls c WHERE c.id = NEW.call_id) THEN
      RAISE EXCEPTION 'A money call is recorded before its call exists';
    END IF;
    IF NEW.target_call_id IS NOT NULL THEN
      SELECT * INTO t FROM public.calls WHERE id = NEW.target_call_id;
      IF t.id IS NULL OR t.user_id = NEW.user_id OR t.market_id IS DISTINCT FROM NEW.market_id
        OR (NEW.kind = 'back' AND t.side IS DISTINCT FROM NEW.side)
        OR (NEW.kind = 'fade' AND t.side = NEW.side) THEN
        RAISE EXCEPTION 'A tail or fade must answer someone else''s call on the same market, on the same or the opposite side';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['state','ended_reason','attempts','wallet_address','expires_at','updated_at'])
    IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['state','ended_reason','attempts','wallet_address','expires_at','updated_at']) THEN
    RAISE EXCEPTION 'A money call''s intent is immutable';
  END IF;
  IF OLD.state = 'FUNDED' THEN RAISE EXCEPTION 'A funded money call is final'; END IF;
  IF NEW.attempts < OLD.attempts THEN RAISE EXCEPTION 'Money call attempts only go up'; END IF;
  IF OLD.state <> 'PENDING' AND (NEW.attempts <> OLD.attempts OR NEW.wallet_address <> OLD.wallet_address
    OR NEW.expires_at <> OLD.expires_at) THEN
    RAISE EXCEPTION 'Only a pending money call can be quoted again';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state THEN
    IF NOT ((OLD.state = 'PENDING' AND NEW.state IN ('FUNDED','FREE','EXPIRED'))
      OR (OLD.state IN ('FREE','EXPIRED') AND NEW.state = 'FUNDED')) THEN
      RAISE EXCEPTION 'Invalid money call transition';
    END IF;
    IF NEW.state = 'FUNDED' AND NOT EXISTS (SELECT 1 FROM public.panta_trade_sessions s
      WHERE s.user_id = NEW.user_id AND s.call_id = NEW.call_id AND s.state = 'FILLED') THEN
      RAISE EXCEPTION 'A money call is funded only by a confirmed fill';
    END IF;
    -- A closed call comes back only for its own last quote, signed in time.
    IF NEW.state = 'FUNDED' AND OLD.state IN ('EXPIRED','FREE') AND (OLD.ended_reason = 'discarded' OR NOT EXISTS (
      SELECT 1 FROM public.panta_trade_sessions s
       WHERE s.user_id = NEW.user_id AND s.call_id = NEW.call_id AND s.state = 'FILLED'
         AND s.idempotency_key = OLD.idempotency_key || '.t' || OLD.attempts
         AND (s.prepared#>>'{order,expiresAt}')::numeric <= extract(epoch FROM OLD.expires_at) * 1000)) THEN
      RAISE EXCEPTION 'A closed money call is funded only by its own last quote, signed in time';
    END IF;
    IF NEW.state = 'EXPIRED' AND EXISTS (SELECT 1 FROM public.panta_trade_sessions s
      WHERE s.user_id = NEW.user_id AND s.call_id = NEW.call_id AND s.state IN ('SUBMITTED','FILLED')) THEN
      RAISE EXCEPTION 'A money call with a trade going through cannot expire';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.money_calls_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.money_calls_guard_v1() TO service_role;
DROP TRIGGER IF EXISTS money_calls_guard ON public.money_calls;
CREATE TRIGGER money_calls_guard BEFORE INSERT OR UPDATE OR DELETE ON public.money_calls
  FOR EACH ROW EXECUTE FUNCTION public.money_calls_guard_v1();
DROP TRIGGER IF EXISTS money_calls_no_truncate ON public.money_calls;
CREATE TRIGGER money_calls_no_truncate BEFORE TRUNCATE ON public.money_calls
  FOR EACH STATEMENT EXECUTE FUNCTION public.money_calls_guard_v1();

-- A money call is traded only while PENDING, through the BFF's money flow:
-- a new or newly signed Panta trade for a call whose money call has ended is
-- refused (additive: a new trigger beside panta_trade_session_guard_v1).
CREATE OR REPLACE FUNCTION public.money_call_trade_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF (TG_OP = 'INSERT' OR (NEW.state = 'SUBMITTED' AND OLD.state IS DISTINCT FROM 'SUBMITTED'))
     AND EXISTS (SELECT 1 FROM public.money_calls m WHERE m.call_id = NEW.call_id AND m.state <> 'PENDING') THEN
    RAISE EXCEPTION 'This money call has ended; it can no longer be traded';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.money_call_trade_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.money_call_trade_guard_v1() TO service_role;
DROP TRIGGER IF EXISTS panta_trade_sessions_money_guard ON public.panta_trade_sessions;
CREATE TRIGGER panta_trade_sessions_money_guard BEFORE INSERT OR UPDATE OF state ON public.panta_trade_sessions
  FOR EACH ROW EXECUTE FUNCTION public.money_call_trade_guard_v1();

-- Whether a call is still private because its money has not landed: true
-- while its money call is anything but FUNDED (PENDING, EXPIRED, or FREE,
-- whose public replacement is a separate free call). Read by RLS as the
-- calling role, so anon and authenticated may execute it; it answers only
-- this yes/no about one call.
CREATE OR REPLACE FUNCTION public.money_call_private_v1(p_call_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM public.money_calls m WHERE m.call_id = p_call_id AND m.state <> 'FUNDED')
$$;
REVOKE ALL ON FUNCTION public.money_call_private_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.money_call_private_v1(uuid) TO anon, authenticated, service_role;

-- RESTRICTIVE: ANDed with every permissive SELECT policy on calls. The
-- author still reads their own; nobody else reads a private money call. The
-- service role bypasses RLS, so the BFF's reads are unchanged.
DROP POLICY IF EXISTS calls_money_private_anon ON public.calls;
CREATE POLICY calls_money_private_anon ON public.calls AS RESTRICTIVE FOR SELECT TO anon
  USING (NOT public.money_call_private_v1(id));
DROP POLICY IF EXISTS calls_money_private_authenticated ON public.calls;
CREATE POLICY calls_money_private_authenticated ON public.calls AS RESTRICTIVE FOR SELECT TO authenticated
  USING (user_id = public.current_app_user_id() OR NOT public.money_call_private_v1(id));
