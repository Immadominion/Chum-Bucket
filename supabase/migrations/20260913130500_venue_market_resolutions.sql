-- ============================================================================
-- PACKET B — market_resolutions: the venue evidence a result is derived from
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §0.2 (the venue is the only source of a
--           result), §3 (Resolution), §5 (service-write only, default-deny)
-- ============================================================================
--
-- This is the most safety-critical table in Packet B. Invariant §0.2: "No
-- client, no admin, no friend and no model may write a resolution. Only the BFF
-- synchroniser, from venue evidence."
--
-- Three mechanisms enforce that, not one:
--   1. DEFAULT-DENY + no write policy  -> only service_role can write at all.
--   2. APPEND-ONLY TRIGGER             -> even service_role cannot UPDATE or
--      DELETE a recorded resolution. A restatement is a NEW row pointing at the
--      one it supersedes, so the history of what the venue said, and when, is
--      permanent. (RLS does not apply to service_role; a trigger does. That
--      asymmetry is the whole reason the trigger exists.)
--   3. EVIDENCE REQUIRED               -> raw_evidence must be non-empty, so a
--      resolution can never be conjured without the payload it was read from.
--
-- What this rules out, concretely: the §8.5 failure mode where a redefined
-- function silently reverted a settled-position guard. Here there is no
-- function to redefine and no UPDATE path to revert to.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.market_resolutions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- ON DELETE RESTRICT: evidence outlives convenience. A market cannot be
  -- deleted out from under the resolution that settles calls against it.
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE RESTRICT,
  venue TEXT NOT NULL,
  venue_market_id TEXT NOT NULL,
  -- Resolution = 'YES' | 'NO' | 'VOID' (§3). VOID is cancelled/abandoned —
  -- never a win and never a loss.
  resolution TEXT NOT NULL,
  resolved_at TIMESTAMPTZ NOT NULL,
  -- The venue's own resolution-source string, verbatim.
  evidence_source TEXT NOT NULL,
  -- The provider payload the resolution was read out of. Non-empty by CHECK.
  raw_evidence JSONB NOT NULL,
  -- A venue restatement is a NEW row pointing at the row it replaces. Nothing
  -- is ever edited in place.
  supersedes_id UUID REFERENCES public.market_resolutions(id) ON DELETE RESTRICT,
  is_demo BOOLEAN GENERATED ALWAYS AS (venue = 'fixture') STORED,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT market_resolutions_venue_check CHECK (venue IN ('jupiter', 'fixture')),
  CONSTRAINT market_resolutions_value_check CHECK (resolution IN ('YES', 'NO', 'VOID')),
  -- A resolution with no evidence is a guess. §0.2 forbids guesses.
  CONSTRAINT market_resolutions_requires_evidence CHECK (raw_evidence <> '{}'::jsonb),
  CONSTRAINT market_resolutions_no_self_supersede CHECK (supersedes_id IS DISTINCT FROM id)
);

-- One ORIGINAL resolution per market. A replayed poll that tries to insert the
-- same resolution again hits this and the synchroniser's ON CONFLICT DO NOTHING
-- — which is what makes the resolution poll idempotent. A genuine venue
-- restatement carries supersedes_id and is therefore outside this index.
CREATE UNIQUE INDEX IF NOT EXISTS uq_market_resolutions_original
  ON public.market_resolutions (market_id)
  WHERE supersedes_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_market_resolutions_market
  ON public.market_resolutions (market_id, recorded_at DESC);

-- §5 mandatory template.
ALTER TABLE public.market_resolutions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.market_resolutions FROM anon, authenticated;
GRANT ALL ON public.market_resolutions TO service_role;

-- Resolutions are public evidence — a receipt everyone can check. SELECT only,
-- and only for a market that is itself public. No USING (true) (§5).
GRANT SELECT ON public.market_resolutions TO anon, authenticated;

DROP POLICY IF EXISTS market_resolutions_public_select ON public.market_resolutions;
CREATE POLICY market_resolutions_public_select ON public.market_resolutions
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.venue_markets m
      WHERE m.id = market_resolutions.market_id
        AND m.is_public
    )
  );

-- No INSERT/UPDATE/DELETE policy: service-write only (§5, Packet B).

-- ---------------------------------------------------------------------------
-- Append-only enforcement. RLS is bypassed by service_role; a trigger is not.
-- This is what stops an admin-override from ever existing, in code or by hand.
-- New, separately-named function — never CREATE OR REPLACE on an existing one
-- (§5: record_prediction_call was redefined three times and silently lost a
-- guard and its search_path pin).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.market_resolutions_append_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION
      'market_resolutions is append-only: a recorded venue resolution may never be updated. Insert a new row with supersedes_id instead.'
      USING ERRCODE = 'raise_exception';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'market_resolutions is append-only: a recorded venue resolution may never be deleted.'
      USING ERRCODE = 'raise_exception';
  END IF;
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.market_resolutions_append_only() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.market_resolutions_append_only() TO service_role;

DROP TRIGGER IF EXISTS trg_market_resolutions_append_only ON public.market_resolutions;
CREATE TRIGGER trg_market_resolutions_append_only
  BEFORE UPDATE OR DELETE ON public.market_resolutions
  FOR EACH ROW
  EXECUTE FUNCTION public.market_resolutions_append_only();

COMMENT ON TABLE public.market_resolutions IS
  'Venue-published resolutions (contracts §0.2/§3). Service-write only, append-only by trigger (which binds service_role too, unlike RLS). A restatement is a new row with supersedes_id. raw_evidence is required: there is no path to a resolution without the payload it was read from.';
COMMENT ON COLUMN public.market_resolutions.is_demo IS
  'Generated from venue. TRUE = fixture catalog. A demo resolution can never be presented as a live result.';
