-- ============================================================================
-- VENUE MARKET — admit 'polymarket' as a real, read-only venue.
-- Owner: integration   Created: 2026-09-17
-- Contract: pivot-contracts-v1 §3 (VenueId), §4 (one adapter per venue)
-- ============================================================================
--
-- The Packet B tables were written when the only two venues were 'jupiter' and
-- 'fixture', so four CHECK constraints and one RLS policy hard-code that pair.
-- Polymarket is now a real adapter (src/prediction/PolymarketVenue.ts): a
-- keyless, READ-ONLY public API returning real markets, real prices and real
-- resolutions. Without this migration every polymarket row is refused by a
-- CHECK, so the BFF silently falls back to an in-memory store and nothing
-- durable is written — real data that evaporates on redeploy.
--
-- These are tables this same pivot created four days ago, not legacy ones, and
-- they are empty in production. Widening a CHECK on our own empty table is not
-- the "do not rewrite legacy" case §5 warns about.
--
-- Widening only. Every value that was accepted before is still accepted, so
-- nothing already written can become invalid — and the tables are empty
-- anyway, so this cannot fail on existing data.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. The four CHECK constraints.
-- ---------------------------------------------------------------------------
-- Dropped and re-added rather than altered, because PostgreSQL has no
-- ALTER CONSTRAINT for a CHECK expression. IF EXISTS on the drop so this is
-- re-runnable; the add is guarded so a re-run cannot duplicate it.

ALTER TABLE public.venue_markets      DROP CONSTRAINT IF EXISTS venue_markets_venue_check;
ALTER TABLE public.market_resolutions DROP CONSTRAINT IF EXISTS market_resolutions_venue_check;
ALTER TABLE public.venue_orders       DROP CONSTRAINT IF EXISTS venue_orders_venue_check;
ALTER TABLE public.venue_positions    DROP CONSTRAINT IF EXISTS venue_positions_venue_check;

DO $$
DECLARE
  t TEXT;
  c TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['venue_markets', 'market_resolutions', 'venue_orders', 'venue_positions']
  LOOP
    c := t || '_venue_check';
    IF NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_constraint
       WHERE conrelid = ('public.' || t)::regclass AND conname = c
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (venue IN (%L, %L, %L))',
        t, c, 'jupiter', 'polymarket', 'fixture'
      );
    END IF;
  END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- 2. The public read policy on venue_markets.
-- ---------------------------------------------------------------------------
-- Easy to miss and it would have been the confusing half: with the CHECK
-- widened but this policy left alone, a polymarket market would write fine and
-- then be invisible to every anon and authenticated reader — a market that
-- exists, is public, and cannot be seen.
--
-- Still a real predicate, NOT `USING (true)` (§5). `is_public` remains the
-- withdrawal switch: flipping it hides a market and, through the EXISTS clauses
-- on the child tables, its snapshots and resolutions with it.
--
-- market_snapshots and market_resolutions need no change — their policies
-- already delegate to this one via EXISTS over venue_markets, which is exactly
-- why that indirection was worth having.

DROP POLICY IF EXISTS venue_markets_public_select ON public.venue_markets;
CREATE POLICY venue_markets_public_select ON public.venue_markets
  FOR SELECT
  TO anon, authenticated
  USING (is_public AND venue IN ('jupiter', 'polymarket', 'fixture'));

COMMENT ON COLUMN public.venue_markets.venue IS
  'Which adapter produced this row: jupiter, polymarket (read-only, keyless) or fixture. fixture is ALWAYS demo data and must be visibly labelled in any UI. polymarket is real data but supports no trading through us.';
