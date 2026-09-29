-- Native Panta intent ledger. No legacy table or existing funded row is rewritten.
-- Only the BFF can read/write approvals. A free call remains free and immutable.
CREATE TABLE public.panta_trade_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  call_id UUID NOT NULL REFERENCES public.calls(id) ON DELETE RESTRICT,
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  wallet_address TEXT NOT NULL CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  venue_market_id TEXT NOT NULL,
  side TEXT NOT NULL CHECK (side IN ('YES','NO')),
  amount_base_units NUMERIC(38,0) NOT NULL CHECK (amount_base_units > 0),
  max_slippage_bps INTEGER NOT NULL CHECK (max_slippage_bps BETWEEN 0 AND 500),
  idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  state TEXT NOT NULL DEFAULT 'PREPARING' CHECK (state IN ('PREPARING','QUOTED','SUBMITTED','FILLED','FAILED')),
  provider_order_id TEXT UNIQUE,
  prepared JSONB,
  signed_transaction TEXT CHECK (length(signed_transaction) BETWEEN 1 AND 1644 AND signed_transaction ~ '^[A-Za-z0-9+/]+={0,2}$'),
  signature TEXT UNIQUE CHECK (signature ~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
  fill_evidence JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id,idempotency_key),
  CHECK ((signed_transaction IS NULL) = (signature IS NULL)),
  CHECK (state <> 'PREPARING' OR (prepared IS NULL AND provider_order_id IS NULL)),
  CHECK (state IN ('SUBMITTED','FILLED','FAILED') OR signature IS NULL),
  CHECK ((state = 'FILLED') = (fill_evidence IS NOT NULL)),
  CHECK (state NOT IN ('QUOTED','SUBMITTED','FILLED') OR (prepared IS NOT NULL AND provider_order_id IS NOT NULL)),
  CHECK (state NOT IN ('SUBMITTED','FILLED') OR signature IS NOT NULL),
  CONSTRAINT panta_trade_prepared_binding CHECK ((prepared IS NULL OR (
    jsonb_typeof(prepared) = 'object'
    AND jsonb_typeof(prepared->'order') = 'object'
    AND jsonb_typeof(prepared->'binding') = 'object'
    AND jsonb_typeof(prepared->'review') = 'object'
    AND prepared#>'{binding,unsignedOrder}' = prepared->'order'
    AND prepared#>'{binding,review}' = prepared->'review'
    AND prepared#>>'{order,orderId}' = provider_order_id
    AND prepared#>>'{order,venue}' = 'panta'
    AND prepared#>>'{order,fundingState}' = 'QUOTED'
    AND prepared#>>'{order,owner}' = wallet_address
    AND prepared#>>'{order,venueMarketId}' = venue_market_id
    AND prepared#>>'{order,side}' = side
    AND jsonb_typeof(prepared#>'{order,amountBaseUnits}') = 'string'
    AND prepared#>>'{order,amountBaseUnits}' = amount_base_units::text
    AND prepared#>>'{order,idempotencyKey}' = idempotency_key
    AND prepared#>'{order,demo}' = 'false'::jsonb
    AND prepared#>'{order,quotedProbability}' = 'null'::jsonb
    AND prepared#>>'{order,transaction,venue}' = 'panta'
    AND prepared#>>'{order,transaction,encoding}' = 'solana-tx-base64'
    AND prepared#>>'{order,transaction,payload}' ~ '^[A-Za-z0-9+/]+={0,2}$'
    AND length(prepared#>>'{order,transaction,payload}') BETWEEN 1 AND 1644
    AND prepared#>'{order,transaction,demo}' = 'false'::jsonb
    AND prepared#>>'{binding,canonicalUserId}' = user_id::text
    AND prepared#>>'{binding,providerAttributionUserId}' ~ '^usr_[A-Za-z0-9][A-Za-z0-9_-]*$'
    AND prepared#>>'{binding,owner}' = wallet_address
    AND prepared#>>'{binding,venueMarketId}' = venue_market_id
    AND prepared#>>'{binding,providerOrderId}' = provider_order_id
    AND prepared#>>'{binding,idempotencyKey}' = idempotency_key
    AND prepared#>>'{binding,side}' = side
    AND jsonb_typeof(prepared#>'{binding,amountBaseUnits}') = 'string'
    AND prepared#>>'{binding,amountBaseUnits}' = amount_base_units::text
    AND prepared#>>'{binding,messageHash}' ~ '^[0-9a-f]{64}$'
    AND prepared#>'{binding,signature}' = 'null'::jsonb
    AND prepared#>'{binding,createdAt}' = prepared#>'{order,createdAt}'
    AND prepared#>'{binding,expiresAt}' = prepared#>'{order,expiresAt}'
    AND prepared#>'{order,transaction,expiresAt}' = prepared#>'{order,expiresAt}'
    AND prepared#>>'{review,attribution}' = 'Powered by Panta'
    AND jsonb_typeof(prepared#>'{review,amountBaseUnits}') = 'string'
    AND prepared#>>'{review,amountBaseUnits}' = amount_base_units::text
    AND prepared#>'{binding,amountUsdc}' = prepared#>'{review,amountUsdc}'
    AND prepared#>>'{review,currency}' = 'USDC'
    AND prepared#>>'{review,priceUnit}' = 'USDC/share'
    AND prepared#>'{review,quotedProbability}' = 'null'::jsonb
    AND (prepared#>>'{review,maxSlippageBps}')::integer = max_slippage_bps
  )) IS TRUE),
  CONSTRAINT panta_trade_confirmed_evidence CHECK ((state <> 'FILLED' OR (
    jsonb_typeof(fill_evidence) = 'object'
    AND fill_evidence->>'venue' = 'panta'
    AND fill_evidence->>'fundingState' = 'FILLED'
    AND fill_evidence->>'orderId' = provider_order_id
    AND fill_evidence->>'idempotencyKey' = idempotency_key
    AND fill_evidence->'demo' = 'false'::jsonb
    AND jsonb_typeof(fill_evidence->'amountBaseUnits') = 'string'
    AND fill_evidence->>'amountBaseUnits' = amount_base_units::text
    AND fill_evidence->>'fillTxSignature' = signature
    AND fill_evidence->>'venueOrderId' = provider_order_id
    AND fill_evidence->>'owner' = wallet_address
    AND fill_evidence->>'venueMarketId' = venue_market_id
    AND fill_evidence->>'side' = side
    AND jsonb_typeof(fill_evidence->'filledBaseUnits') = 'string'
    AND fill_evidence->>'filledBaseUnits' = amount_base_units::text
    AND fill_evidence#>>'{fillEvidence,messageHash}' = prepared#>>'{binding,messageHash}'
    AND fill_evidence#>'{fillEvidence,independentlyVerified}' = 'true'::jsonb
    AND fill_evidence#>>'{fillEvidence,providerVerify,status}' = 'confirmed'
    AND fill_evidence#>>'{fillEvidence,providerVerify,orderId}' = provider_order_id
    AND fill_evidence#>>'{fillEvidence,providerVerify,signature}' = signature
    AND fill_evidence#>>'{fillEvidence,providerVerify,marketId}' = venue_market_id
    AND upper(fill_evidence#>>'{fillEvidence,providerVerify,side}') = side
    AND jsonb_typeof(fill_evidence#>'{fillEvidence,providerVerify,amountUsdc}') IN ('string','number')
    AND fill_evidence#>>'{fillEvidence,providerVerify,amountUsdc}' ~ '^[1-9][0-9]{0,19}$'
    AND (fill_evidence#>>'{fillEvidence,providerVerify,amountUsdc}')::numeric = amount_base_units
    AND fill_evidence#>>'{fillEvidence,providerTrade,status}' = 'processed'
    AND fill_evidence#>>'{fillEvidence,providerTrade,kind}' = 'buy'
    AND fill_evidence#>>'{fillEvidence,providerTrade,signature}' = signature
    AND fill_evidence#>>'{fillEvidence,providerTrade,wallet}' = wallet_address
    AND fill_evidence#>>'{fillEvidence,providerTrade,marketId}' = venue_market_id
    AND upper(fill_evidence#>>'{fillEvidence,providerTrade,side}') = side
  )) IS TRUE)
);
CREATE INDEX panta_trade_sessions_user_time ON public.panta_trade_sessions(user_id,created_at DESC);
-- A cold-start or two replicas cannot broadcast two approvals for one call.
-- This MVP funds a call once; a later explicit top-up needs a separate reviewed flow.
CREATE UNIQUE INDEX panta_trade_sessions_one_funding_per_call_wallet
  ON public.panta_trade_sessions(user_id,call_id,wallet_address)
  WHERE state IN ('SUBMITTED','FILLED');
ALTER TABLE public.panta_trade_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.panta_trade_sessions FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON public.panta_trade_sessions TO service_role;
GRANT UPDATE (state,provider_order_id,prepared,signed_transaction,signature,fill_evidence,updated_at)
  ON public.panta_trade_sessions TO service_role;

CREATE FUNCTION public.panta_trade_session_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,public,pg_temp AS $$
DECLARE c public.calls; m public.venue_markets;
BEGIN
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Panta trading history is permanent'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'PREPARING' OR NEW.prepared IS NOT NULL OR NEW.signature IS NOT NULL OR NEW.fill_evidence IS NOT NULL THEN
      RAISE EXCEPTION 'A Panta trade must start as an unfunded intent';
    END IF;
    SELECT * INTO c FROM public.calls WHERE id = NEW.call_id;
    SELECT * INTO m FROM public.venue_markets WHERE id = NEW.market_id;
    IF c.id IS NULL OR c.user_id IS DISTINCT FROM NEW.user_id OR c.market_id IS DISTINCT FROM NEW.market_id
      OR c.side IS DISTINCT FROM NEW.side OR m.venue IS DISTINCT FROM 'panta'
      OR m.venue_market_id IS DISTINCT FROM NEW.venue_market_id THEN
      RAISE EXCEPTION 'Panta intent must belong to the caller and exact called market/side';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['state','provider_order_id','prepared','signed_transaction','signature','fill_evidence','updated_at'])
    IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['state','provider_order_id','prepared','signed_transaction','signature','fill_evidence','updated_at']) THEN
    RAISE EXCEPTION 'Panta trade intent is immutable';
  END IF;
  IF OLD.prepared IS NOT NULL AND (NEW.prepared IS DISTINCT FROM OLD.prepared OR NEW.provider_order_id IS DISTINCT FROM OLD.provider_order_id) THEN
    RAISE EXCEPTION 'Reviewed Panta transaction cannot change';
  END IF;
  IF OLD.signature IS NOT NULL AND (NEW.signature IS DISTINCT FROM OLD.signature OR NEW.signed_transaction IS DISTINCT FROM OLD.signed_transaction) THEN
    RAISE EXCEPTION 'A Panta intent can approve only one transaction';
  END IF;
  IF OLD.state = 'FILLED' AND to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
    RAISE EXCEPTION 'Confirmed Panta fill is immutable';
  END IF;
  IF OLD.state = 'FAILED' AND NEW.state <> 'FAILED' THEN RAISE EXCEPTION 'A failed Panta intent cannot reopen'; END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'PREPARING' AND NEW.state IN ('QUOTED','FAILED')) OR
    (OLD.state = 'QUOTED' AND NEW.state IN ('SUBMITTED','FAILED')) OR
    (OLD.state = 'SUBMITTED' AND NEW.state IN ('FILLED','FAILED'))
  ) THEN RAISE EXCEPTION 'Invalid Panta funding transition'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.panta_trade_session_guard_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.panta_trade_session_guard_v1() TO service_role;
CREATE TRIGGER panta_trade_sessions_guard BEFORE INSERT OR UPDATE OR DELETE ON public.panta_trade_sessions
  FOR EACH ROW EXECUTE FUNCTION public.panta_trade_session_guard_v1();
CREATE TRIGGER panta_trade_sessions_no_truncate BEFORE TRUNCATE ON public.panta_trade_sessions
  FOR EACH STATEMENT EXECUTE FUNCTION public.panta_trade_session_guard_v1();
