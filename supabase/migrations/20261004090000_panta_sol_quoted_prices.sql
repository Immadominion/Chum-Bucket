-- Panta's SOL-quoted markets: price observations in the market's own quote
-- asset, evidenced by the program account they were read from.
--
-- Panta's partner API lists only USDC markets, so its SOL-quoted markets were
-- missing from Chumbucket (6 of the 12 open on 2026-10-04). The BFF now reads
-- them from the Panta program account (src/prediction/PantaProgram.ts in the
-- API repo) and offers them for free calls only; they are never tradable.
--
-- Additive: this WIDENS two CHECK constraints and rewrites no row. Every row
-- the previous constraints accepted (currency USDC, payloadVersion 1 partner
-- API evidence) is accepted unchanged. A SOL row is accepted only with
-- payloadVersion 2 chain evidence whose quoteAsset says SOL and whose prices
-- equal the snapshot's. Append-only triggers, grants and RLS are untouched.
-- Calls keep pinning their own stored observation (calls_panta_price_guard_v1),
-- which never read the currency.

ALTER TABLE public.market_share_price_snapshots DROP CONSTRAINT panta_snapshot_shape;
ALTER TABLE public.market_share_price_snapshots ADD CONSTRAINT panta_snapshot_shape CHECK ((
  jsonb_typeof(snapshot) = 'object'
  AND snapshot ?& ARRAY['id','marketId','venue','currency','unit','yesPrice','noPrice','observedAt','source','attribution','executable']
  AND (snapshot - ARRAY['id','marketId','venue','currency','unit','yesPrice','noPrice','observedAt','source','attribution','executable']) = '{}'::jsonb
  AND snapshot @> '{"venue":"panta","unit":"per_share","source":"venue","attribution":"Powered by Panta","executable":false}'::jsonb
  AND snapshot->>'currency' IN ('USDC', 'SOL')
  AND snapshot->>'id' = id::text AND snapshot->>'marketId' = market_id::text
  AND jsonb_typeof(snapshot->'observedAt') = 'number'
  AND (snapshot->>'observedAt')::numeric = extract(epoch FROM observed_at) * 1000
  AND (snapshot->>'observedAt')::numeric > 0
  AND mod((snapshot->>'observedAt')::numeric, 1) = 0
  AND (snapshot->>'observedAt')::numeric <= 9007199254740991
  AND (snapshot->'yesPrice' = 'null'::jsonb OR (jsonb_typeof(snapshot->'yesPrice') = 'string' AND snapshot->>'yesPrice' ~ '^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$'))
  AND (snapshot->'noPrice' = 'null'::jsonb OR (jsonb_typeof(snapshot->'noPrice') = 'string' AND snapshot->>'noPrice' ~ '^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$'))
) IS TRUE);

ALTER TABLE public.market_share_price_snapshots DROP CONSTRAINT panta_snapshot_raw_evidence;
ALTER TABLE public.market_share_price_snapshots ADD CONSTRAINT panta_snapshot_raw_evidence CHECK ((
  jsonb_typeof(raw_evidence) = 'object'
  AND raw_evidence->>'venue' = 'panta'
  AND raw_evidence->'fetchedAt' = snapshot->'observedAt'
  AND jsonb_typeof(raw_evidence->'body') = 'object'
  AND raw_evidence->'body' <> '{}'::jsonb
  -- Reject evidence with different observed prices, whichever source it is.
  AND raw_evidence->'body'->'yesPrice' = snapshot->'yesPrice'
  AND raw_evidence->'body'->'noPrice' = snapshot->'noPrice'
  AND (
    -- v1: a Panta partner-API market row (USDC markets only).
    ((raw_evidence->>'payloadVersion')::integer = 1 AND snapshot->>'currency' = 'USDC')
    -- v2: the Panta program account of a SOL-quoted market, as read over RPC.
    OR ((raw_evidence->>'payloadVersion')::integer = 2 AND snapshot->>'currency' = 'SOL'
      AND raw_evidence->'body'->>'source' = 'solana-account'
      AND raw_evidence->'body'->>'quoteAsset' = 'SOL'
      AND raw_evidence->'body'->>'account' = raw_evidence->>'venueMarketId'
      AND jsonb_typeof(raw_evidence->'body'->'data') = 'string')
  )
) IS TRUE);
