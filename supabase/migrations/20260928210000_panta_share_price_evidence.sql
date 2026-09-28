-- Panta's independent USDC/share observations. Additive; no historical rewrite.
-- Apply only after live-schema review and explicit deployment approval.
-- No funded tables are widened: orders/positions still cannot name Panta.
ALTER TABLE public.venue_markets DROP CONSTRAINT venue_markets_venue_check;
ALTER TABLE public.venue_markets ADD CONSTRAINT venue_markets_venue_check
  CHECK (venue IN ('jupiter', 'polymarket', 'fixture', 'panta'));
ALTER TABLE public.market_resolutions DROP CONSTRAINT market_resolutions_venue_check;
ALTER TABLE public.market_resolutions ADD CONSTRAINT market_resolutions_venue_check
  CHECK (venue IN ('jupiter', 'polymarket', 'fixture', 'panta'));
ALTER TABLE public.venue_markets ADD CONSTRAINT panta_market_requires_raw
  CHECK (venue <> 'panta' OR (jsonb_typeof(raw_payload) = 'object' AND raw_payload <> '{}'::jsonb));

CREATE POLICY venue_markets_panta_public_select ON public.venue_markets
  FOR SELECT TO anon, authenticated USING (is_public AND venue = 'panta');

CREATE TABLE public.market_share_price_snapshots (
  id UUID PRIMARY KEY,
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  observed_at TIMESTAMPTZ NOT NULL,
  -- Decimal strings preserve exact provider precision, including prices > 1.
  snapshot JSONB NOT NULL,
  raw_evidence JSONB NOT NULL,
  UNIQUE (market_id, observed_at),
  CONSTRAINT panta_snapshot_shape CHECK ((
    jsonb_typeof(snapshot) = 'object'
    AND snapshot ?& ARRAY['id','marketId','venue','currency','unit','yesPrice','noPrice','observedAt','source','attribution','executable']
    AND (snapshot - ARRAY['id','marketId','venue','currency','unit','yesPrice','noPrice','observedAt','source','attribution','executable']) = '{}'::jsonb
    AND snapshot @> '{"venue":"panta","currency":"USDC","unit":"per_share","source":"venue","attribution":"Powered by Panta","executable":false}'::jsonb
    AND snapshot->>'id' = id::text AND snapshot->>'marketId' = market_id::text
    AND jsonb_typeof(snapshot->'observedAt') = 'number'
    AND (snapshot->>'observedAt')::numeric = extract(epoch FROM observed_at) * 1000
    AND (snapshot->>'observedAt')::numeric > 0
    AND mod((snapshot->>'observedAt')::numeric, 1) = 0
    AND (snapshot->>'observedAt')::numeric <= 9007199254740991
    AND (snapshot->'yesPrice' = 'null'::jsonb OR (jsonb_typeof(snapshot->'yesPrice') = 'string' AND snapshot->>'yesPrice' ~ '^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$'))
    AND (snapshot->'noPrice' = 'null'::jsonb OR (jsonb_typeof(snapshot->'noPrice') = 'string' AND snapshot->>'noPrice' ~ '^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$'))
  ) IS TRUE),
  CONSTRAINT panta_snapshot_raw_evidence CHECK ((
    jsonb_typeof(raw_evidence) = 'object'
    AND raw_evidence->>'venue' = 'panta'
    AND (raw_evidence->>'payloadVersion')::integer = 1
    AND raw_evidence->'fetchedAt' = snapshot->'observedAt'
    AND jsonb_typeof(raw_evidence->'body') = 'object'
    AND raw_evidence->'body' <> '{}'::jsonb
    -- v1 Panta price fields: reject evidence with different observed prices.
    AND raw_evidence->'body'->'yesPrice' = snapshot->'yesPrice'
    AND raw_evidence->'body'->'noPrice' = snapshot->'noPrice'
  ) IS TRUE)
);
CREATE INDEX market_share_price_latest ON public.market_share_price_snapshots(market_id, observed_at DESC);
ALTER TABLE public.market_share_price_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.market_share_price_snapshots FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, market_id, observed_at, snapshot) ON public.market_share_price_snapshots TO anon, authenticated;
GRANT SELECT, INSERT ON public.market_share_price_snapshots TO service_role;
CREATE POLICY panta_prices_public_select ON public.market_share_price_snapshots
  FOR SELECT TO anon, authenticated USING (EXISTS (
    SELECT 1 FROM public.venue_markets m WHERE m.id = market_id AND m.is_public AND m.venue = 'panta'
  ));

CREATE FUNCTION public.panta_price_evidence_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE m public.venue_markets; previous JSONB;
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Panta price evidence is append-only'; END IF;
  SELECT * INTO m FROM public.venue_markets WHERE id = NEW.market_id;
  IF m.venue IS DISTINCT FROM 'panta' OR NEW.raw_evidence->>'venueMarketId' IS DISTINCT FROM m.venue_market_id THEN
    RAISE EXCEPTION 'Panta price evidence market mismatch';
  END IF;
  SELECT snapshot INTO previous FROM public.market_share_price_snapshots WHERE id = NEW.id;
  IF previous IS NOT NULL AND previous IS DISTINCT FROM NEW.snapshot THEN
    RAISE EXCEPTION 'Panta price observation cannot be rewritten';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.panta_price_evidence_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.panta_price_evidence_guard_v1() TO service_role;
CREATE TRIGGER panta_prices_immutable BEFORE INSERT OR UPDATE OR DELETE ON public.market_share_price_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.panta_price_evidence_guard_v1();
CREATE TRIGGER panta_prices_no_truncate BEFORE TRUNCATE ON public.market_share_price_snapshots
  FOR EACH STATEMENT EXECUTE FUNCTION public.panta_price_evidence_guard_v1();

ALTER TABLE public.calls ADD COLUMN share_price_snapshot_id UUID REFERENCES public.market_share_price_snapshots(id) ON DELETE RESTRICT;
ALTER TABLE public.calls ADD COLUMN entry_price JSONB;
-- No client write grant for either column. Existing column-scoped INSERT grants
-- cannot forge Panta evidence; the server is the only writer of a Panta call.
REVOKE INSERT (share_price_snapshot_id, entry_price), UPDATE (share_price_snapshot_id, entry_price)
  ON public.calls FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.calls_panta_price_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE m public.venue_markets; p public.market_share_price_snapshots;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.entry_price IS DISTINCT FROM OLD.entry_price OR NEW.share_price_snapshot_id IS DISTINCT FROM OLD.share_price_snapshot_id THEN
      RAISE EXCEPTION 'Panta entry_price and share_price_snapshot_id are immutable';
    END IF;
    RETURN NEW;
  END IF;
  SELECT * INTO m FROM public.venue_markets WHERE id = NEW.market_id;
  IF m.venue NOT IN ('panta', 'fixture') THEN RAISE EXCEPTION 'New calls use Panta only'; END IF;
  IF m.venue <> 'panta' THEN
    IF NEW.entry_price IS NOT NULL OR NEW.share_price_snapshot_id IS NOT NULL THEN RAISE EXCEPTION 'Non-Panta call cannot carry Panta evidence'; END IF;
    RETURN NEW;
  END IF;
  SELECT * INTO p FROM public.market_share_price_snapshots WHERE id = NEW.share_price_snapshot_id;
  IF p.id IS NULL OR p.market_id IS DISTINCT FROM NEW.market_id OR NEW.entry_price IS DISTINCT FROM p.snapshot THEN
    RAISE EXCEPTION 'Panta call must pin its own stored price observation';
  END IF;
  IF NEW.snapshot_id IS NOT NULL OR NEW.entry_probability IS NOT NULL OR NEW.funding_state <> 'NONE' THEN
    RAISE EXCEPTION 'Panta free calls have share prices, never probability or funded evidence';
  END IF;
  IF p.snapshot->'yesPrice' = 'null'::jsonb OR p.snapshot->'noPrice' = 'null'::jsonb
    OR p.observed_at > NEW.locked_at OR NEW.locked_at - p.observed_at > interval '10 minutes'
    OR abs(extract(epoch FROM (NEW.locked_at - statement_timestamp()))) > 30
    OR abs(extract(epoch FROM (NEW.created_at - statement_timestamp()))) > 30
    OR m.opens_at > statement_timestamp() OR m.closes_at IS NULL THEN
    RAISE EXCEPTION 'Panta call needs fresh prices and a current, bounded call window';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.calls_panta_price_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calls_panta_price_guard_v1() TO service_role;
CREATE TRIGGER calls_panta_price_guard BEFORE INSERT OR UPDATE ON public.calls
  FOR EACH ROW EXECUTE FUNCTION public.calls_panta_price_guard_v1();
