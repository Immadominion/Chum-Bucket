-- USDC transfers the BFF builds for a person's own wallet (Chumbucket Money v1,
-- MONEY_CALLS_ENABLED): cash outs from the trading wallet to any Solana
-- address, and top-ups from one of the account's linked wallets into the
-- trading wallet.
--
-- Additive and re-runnable: a new table, a guard function and its triggers.
-- No legacy table, policy, grant or function is altered and no row is touched.
--
-- The trade ledger's discipline (20260929120000_panta_trade_sessions.sql):
-- the reviewed unsigned transaction is stored before any wallet sees it; the
-- exact signed bytes are stored before broadcast, once; CONFIRMED requires
-- independent chain evidence that exactly this amount moved; FAILED and
-- CONFIRMED are final. At most one transfer per source wallet is in flight
-- (BUILT or SUBMITTED). Only the BFF (service_role) reads or writes it.
CREATE TABLE IF NOT EXISTS public.wallet_transfers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  kind TEXT NOT NULL CHECK (kind IN ('cash_out','deposit')),
  from_wallet TEXT NOT NULL CHECK (from_wallet ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  to_wallet TEXT NOT NULL CHECK (to_wallet ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  amount_base_units NUMERIC(38,0) NOT NULL CHECK (amount_base_units > 0),
  idempotency_key TEXT NOT NULL CHECK (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9_-]{15,95}$'),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  state TEXT NOT NULL DEFAULT 'BUILT' CHECK (state IN ('BUILT','SUBMITTED','CONFIRMED','FAILED')),
  prepared JSONB NOT NULL,
  signed_transaction TEXT CHECK (length(signed_transaction) BETWEEN 1 AND 1644 AND signed_transaction ~ '^[A-Za-z0-9+/]+={0,2}$'),
  signature TEXT UNIQUE CHECK (signature ~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
  confirm_evidence JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key),
  CONSTRAINT wallet_transfers_not_to_self CHECK (from_wallet <> to_wallet),
  CONSTRAINT wallet_transfers_signed_pair CHECK ((signed_transaction IS NULL) = (signature IS NULL)),
  CONSTRAINT wallet_transfers_signature_state CHECK (
    (state = 'BUILT' AND signature IS NULL) OR
    (state IN ('SUBMITTED','CONFIRMED') AND signature IS NOT NULL) OR
    state = 'FAILED'
  ),
  CONSTRAINT wallet_transfers_evidence_state CHECK ((state = 'CONFIRMED') = (confirm_evidence IS NOT NULL)),
  CONSTRAINT wallet_transfers_prepared_binding CHECK ((
    jsonb_typeof(prepared) = 'object'
    AND prepared->'version' = '1'::jsonb
    AND prepared->>'from' = from_wallet
    AND prepared->>'to' = to_wallet
    AND jsonb_typeof(prepared->'amountBaseUnits') = 'string'
    AND prepared->>'amountBaseUnits' = amount_base_units::text
    AND prepared->>'mint' = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'
    AND prepared->>'encoding' = 'solana-tx-base64'
    AND prepared->>'transaction' ~ '^[A-Za-z0-9+/]+={0,2}$'
    AND length(prepared->>'transaction') BETWEEN 1 AND 1644
    AND prepared->>'messageHash' ~ '^[0-9a-f]{64}$'
    AND prepared->>'recentBlockhash' ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'
    AND jsonb_typeof(prepared->'lastValidBlockHeight') = 'number'
    AND jsonb_typeof(prepared->'createsAccount') = 'boolean'
    AND jsonb_typeof(prepared->'createdAt') = 'number'
    AND jsonb_typeof(prepared->'expiresAt') = 'number'
    AND (prepared->>'expiresAt')::numeric > (prepared->>'createdAt')::numeric
    AND (prepared->>'expiresAt')::numeric - (prepared->>'createdAt')::numeric <= 120000
  ) IS TRUE),
  CONSTRAINT wallet_transfers_confirmed_evidence CHECK ((state <> 'CONFIRMED' OR (
    jsonb_typeof(confirm_evidence) = 'object'
    AND confirm_evidence->'independentlyVerified' = 'true'::jsonb
    AND confirm_evidence->>'messageHash' = prepared->>'messageHash'
    AND confirm_evidence->>'signature' = signature
    AND jsonb_typeof(confirm_evidence->'amountBaseUnits') = 'string'
    AND confirm_evidence->>'amountBaseUnits' = amount_base_units::text
    AND jsonb_typeof(confirm_evidence->'slot') = 'number'
  )) IS TRUE)
);
CREATE INDEX IF NOT EXISTS wallet_transfers_user_time ON public.wallet_transfers(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS wallet_transfers_submitted ON public.wallet_transfers(updated_at) WHERE state = 'SUBMITTED';
-- At most one transfer in flight per source wallet: a reviewed (BUILT) or
-- sent (SUBMITTED) one. The BFF retires an expired review (BUILT -> FAILED)
-- before building the next.
CREATE UNIQUE INDEX IF NOT EXISTS wallet_transfers_one_in_flight_per_wallet
  ON public.wallet_transfers(from_wallet) WHERE state IN ('BUILT','SUBMITTED');
ALTER TABLE public.wallet_transfers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_transfers FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.wallet_transfers TO service_role;
GRANT UPDATE (state, signed_transaction, signature, confirm_evidence, updated_at) ON public.wallet_transfers TO service_role;

CREATE OR REPLACE FUNCTION public.wallet_transfers_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Wallet transfer history is permanent'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'BUILT' OR NEW.signature IS NOT NULL OR NEW.confirm_evidence IS NOT NULL THEN
      RAISE EXCEPTION 'A wallet transfer starts as an unsigned review';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['state','signed_transaction','signature','confirm_evidence','updated_at'])
    IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['state','signed_transaction','signature','confirm_evidence','updated_at']) THEN
    RAISE EXCEPTION 'A reviewed wallet transfer cannot change';
  END IF;
  IF OLD.signature IS NOT NULL AND (NEW.signature IS DISTINCT FROM OLD.signature
    OR NEW.signed_transaction IS DISTINCT FROM OLD.signed_transaction) THEN
    RAISE EXCEPTION 'A wallet transfer can approve only one transaction';
  END IF;
  IF OLD.state IN ('CONFIRMED','FAILED') AND to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
    RAISE EXCEPTION 'A settled wallet transfer is final';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'BUILT' AND NEW.state IN ('SUBMITTED','FAILED')) OR
    (OLD.state = 'SUBMITTED' AND NEW.state IN ('CONFIRMED','FAILED'))
  ) THEN RAISE EXCEPTION 'Invalid wallet transfer transition'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.wallet_transfers_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_transfers_guard_v1() TO service_role;
DROP TRIGGER IF EXISTS wallet_transfers_guard ON public.wallet_transfers;
CREATE TRIGGER wallet_transfers_guard BEFORE INSERT OR UPDATE OR DELETE ON public.wallet_transfers
  FOR EACH ROW EXECUTE FUNCTION public.wallet_transfers_guard_v1();
DROP TRIGGER IF EXISTS wallet_transfers_no_truncate ON public.wallet_transfers;
CREATE TRIGGER wallet_transfers_no_truncate BEFORE TRUNCATE ON public.wallet_transfers
  FOR EACH STATEMENT EXECUTE FUNCTION public.wallet_transfers_guard_v1();
