-- Native Panta win-claim ledger (funded-position lifecycle, B9).
--
-- Additive only: a new table, a new guard function and its triggers. No legacy
-- table, policy, grant or function is altered, and no existing row is touched.
-- The pattern is panta_trade_sessions' (20260929120000): the reviewed claim
-- transaction is stored before a wallet sees it; the exact signed bytes are
-- stored before broadcast; CONFIRMED requires independent chain evidence that
-- the owner was paid; history is permanent. Only the BFF (service_role) can
-- read or write it. anon/authenticated have no rights at all.
--
-- A claim always belongs to one of the person's own FILLED buys, for the same
-- wallet and market. One wallet claims one market once (Panta's win claim pays
-- out all winning shares), so at most one SUBMITTED/CONFIRMED row may exist per
-- (wallet, market); a FAILED claim never blocks a fresh one.
CREATE TABLE public.panta_claim_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  trade_session_id UUID NOT NULL REFERENCES public.panta_trade_sessions(id) ON DELETE RESTRICT,
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  order_id TEXT NOT NULL CHECK (order_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$'),
  wallet_address TEXT NOT NULL CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  venue_market_id TEXT NOT NULL CHECK (venue_market_id ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  state TEXT NOT NULL DEFAULT 'PREPARING' CHECK (state IN ('PREPARING','BUILT','SUBMITTED','CONFIRMED','FAILED')),
  prepared JSONB,
  signed_transaction TEXT CHECK (length(signed_transaction) BETWEEN 1 AND 1644 AND signed_transaction ~ '^[A-Za-z0-9+/]+={0,2}$'),
  signature TEXT UNIQUE CHECK (signature ~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
  confirm_evidence JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key),
  CHECK ((signed_transaction IS NULL) = (signature IS NULL)),
  CHECK (state <> 'PREPARING' OR prepared IS NULL),
  CHECK (state NOT IN ('BUILT','SUBMITTED','CONFIRMED') OR prepared IS NOT NULL),
  CHECK (state IN ('SUBMITTED','CONFIRMED','FAILED') OR signature IS NULL),
  CHECK (state NOT IN ('SUBMITTED','CONFIRMED') OR signature IS NOT NULL),
  CHECK ((state = 'CONFIRMED') = (confirm_evidence IS NOT NULL)),
  CONSTRAINT panta_claim_prepared_binding CHECK ((prepared IS NULL OR (
    jsonb_typeof(prepared) = 'object'
    AND jsonb_typeof(prepared->'transaction') = 'object'
    AND jsonb_typeof(prepared->'binding') = 'object'
    AND prepared#>>'{transaction,venue}' = 'panta'
    AND prepared#>>'{transaction,encoding}' = 'solana-tx-base64'
    AND prepared#>>'{transaction,payload}' ~ '^[A-Za-z0-9+/]+={0,2}$'
    AND length(prepared#>>'{transaction,payload}') BETWEEN 1 AND 1644
    AND prepared#>'{transaction,demo}' = 'false'::jsonb
    AND prepared#>'{transaction,expiresAt}' = prepared#>'{binding,expiresAt}'
    AND prepared#>'{binding,version}' = '1'::jsonb
    AND prepared#>>'{binding,owner}' = wallet_address
    AND prepared#>>'{binding,venueMarketId}' = venue_market_id
    AND prepared#>>'{binding,programId}' ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'
    AND prepared#>>'{binding,messageHash}' ~ '^[0-9a-f]{64}$'
    AND jsonb_typeof(prepared#>'{binding,lastValidBlockHeight}') = 'number'
    AND jsonb_typeof(prepared#>'{binding,createdAt}') = 'number'
    AND jsonb_typeof(prepared#>'{binding,expiresAt}') = 'number'
    AND (prepared#>>'{binding,expiresAt}')::numeric > (prepared#>>'{binding,createdAt}')::numeric
    AND (prepared#>>'{binding,expiresAt}')::numeric - (prepared#>>'{binding,createdAt}')::numeric <= 300000
    AND prepared#>>'{binding,review,attribution}' = 'Powered by Panta'
    AND prepared#>>'{binding,review,outcome}' IN ('YES','NO')
    AND prepared#>>'{binding,review,winningShares}' ~ '^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$'
  )) IS TRUE),
  CONSTRAINT panta_claim_confirmed_evidence CHECK ((state <> 'CONFIRMED' OR (
    jsonb_typeof(confirm_evidence) = 'object'
    AND confirm_evidence->'independentlyVerified' = 'true'::jsonb
    AND confirm_evidence->>'messageHash' = prepared#>>'{binding,messageHash}'
    AND jsonb_typeof(confirm_evidence->'payoutBaseUnits') = 'string'
    AND confirm_evidence->>'payoutBaseUnits' ~ '^[1-9][0-9]{0,19}$'
    AND jsonb_typeof(confirm_evidence->'slot') = 'number'
    AND (confirm_evidence->'providerTrade' = 'null'::jsonb OR (
      confirm_evidence#>>'{providerTrade,signature}' = signature
      AND confirm_evidence#>>'{providerTrade,status}' = 'processed'
      AND confirm_evidence#>>'{providerTrade,kind}' = 'claim'))
  )) IS TRUE)
);
CREATE INDEX panta_claim_sessions_user_time ON public.panta_claim_sessions(user_id, created_at DESC);
CREATE INDEX panta_claim_sessions_submitted ON public.panta_claim_sessions(updated_at) WHERE state = 'SUBMITTED';
-- One in-flight or settled claim per wallet and market, across every replica.
CREATE UNIQUE INDEX panta_claim_sessions_one_claim_per_wallet_market
  ON public.panta_claim_sessions(wallet_address, venue_market_id)
  WHERE state IN ('SUBMITTED','CONFIRMED');
ALTER TABLE public.panta_claim_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.panta_claim_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.panta_claim_sessions TO service_role;
GRANT UPDATE (state, prepared, signed_transaction, signature, confirm_evidence, updated_at)
  ON public.panta_claim_sessions TO service_role;

CREATE FUNCTION public.panta_claim_session_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE t public.panta_trade_sessions;
BEGIN
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Panta claim history is permanent'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'PREPARING' OR NEW.prepared IS NOT NULL OR NEW.signature IS NOT NULL OR NEW.confirm_evidence IS NOT NULL THEN
      RAISE EXCEPTION 'A Panta claim must start as an unsigned intent';
    END IF;
    SELECT * INTO t FROM public.panta_trade_sessions WHERE id = NEW.trade_session_id;
    IF t.id IS NULL OR t.state IS DISTINCT FROM 'FILLED' OR t.user_id IS DISTINCT FROM NEW.user_id
      OR t.wallet_address IS DISTINCT FROM NEW.wallet_address OR t.venue_market_id IS DISTINCT FROM NEW.venue_market_id
      OR t.market_id IS DISTINCT FROM NEW.market_id OR t.provider_order_id IS DISTINCT FROM NEW.order_id THEN
      RAISE EXCEPTION 'A Panta claim must belong to the caller''s own confirmed position';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['state','prepared','signed_transaction','signature','confirm_evidence','updated_at'])
    IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['state','prepared','signed_transaction','signature','confirm_evidence','updated_at']) THEN
    RAISE EXCEPTION 'Panta claim intent is immutable';
  END IF;
  IF OLD.prepared IS NOT NULL AND NEW.prepared IS DISTINCT FROM OLD.prepared THEN
    RAISE EXCEPTION 'Reviewed Panta claim cannot change';
  END IF;
  IF OLD.signature IS NOT NULL AND (NEW.signature IS DISTINCT FROM OLD.signature OR NEW.signed_transaction IS DISTINCT FROM OLD.signed_transaction) THEN
    RAISE EXCEPTION 'A Panta claim can approve only one transaction';
  END IF;
  IF OLD.state = 'CONFIRMED' AND to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
    RAISE EXCEPTION 'Confirmed Panta claim is immutable';
  END IF;
  IF OLD.state = 'FAILED' AND NEW.state <> 'FAILED' THEN RAISE EXCEPTION 'A failed Panta claim cannot reopen'; END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'PREPARING' AND NEW.state IN ('BUILT','FAILED')) OR
    (OLD.state = 'BUILT' AND NEW.state IN ('SUBMITTED','FAILED')) OR
    (OLD.state = 'SUBMITTED' AND NEW.state IN ('CONFIRMED','FAILED'))
  ) THEN RAISE EXCEPTION 'Invalid Panta claim transition'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.panta_claim_session_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.panta_claim_session_guard_v1() TO service_role;
CREATE TRIGGER panta_claim_sessions_guard BEFORE INSERT OR UPDATE OR DELETE ON public.panta_claim_sessions
  FOR EACH ROW EXECUTE FUNCTION public.panta_claim_session_guard_v1();
CREATE TRIGGER panta_claim_sessions_no_truncate BEFORE TRUNCATE ON public.panta_claim_sessions
  FOR EACH STATEMENT EXECUTE FUNCTION public.panta_claim_session_guard_v1();
