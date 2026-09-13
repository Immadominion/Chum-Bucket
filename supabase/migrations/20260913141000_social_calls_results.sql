-- ============================================================================
-- PACKET D — public.call_results: the service-derived outcome of a call
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §0.2 (the venue is the ONLY source of a
--           result), §3 (CallResult + "the only permitted rule"), §5
--           ("call_results is service-write only")
-- ============================================================================
--
-- §3, verbatim and complete:
--
--     resolution === 'VOID'            -> VOID
--     resolution === call.side         -> CORRECT
--     resolution is the other side     -> INCORRECT
--     no resolution yet                -> PENDING
--
--     "Late resolution stays PENDING. There is no other branch, no admin
--      override, and no client input."
--
-- Four mechanisms encode that here, because "the service does it correctly" is
-- a promise and not an invariant:
--
--   1. DEFAULT-DENY, NO WRITE POLICY. Only service_role writes at all — §5's
--      "service-write only". A client has SELECT and nothing else.
--   2. CHECK CONSTRAINTS make an unevidenced settlement unrepresentable: a
--      non-PENDING row must carry the market_resolutions row it was derived
--      from, and a PENDING row must carry none. There is no shape in which a
--      result exists without the venue evidence behind it.
--   3. A BEFORE INSERT/UPDATE TRIGGER re-derives the outcome from the call's
--      own side and the referenced venue resolution and REFUSES any row that
--      disagrees. It also refuses a resolution belonging to a different market
--      than the call. This binds service_role, which RLS does not — and
--      service_role is what our own BFF uses (§2), so this is the only layer
--      that protects the rule from our own bugs.
--   4. A SETTLED RESULT IS FROZEN. Once outcome <> 'PENDING', the row may only
--      be re-stated identically. That single rule is what makes the resolution
--      synchroniser idempotent at the storage layer (running it twice changes
--      nothing) AND what makes an admin override impossible after the fact.
--
-- PENDING is never a timeout and never an inference. A market that closed long
-- ago, or whose status reads RESOLVED while the venue has published no
-- market_resolutions row, stays PENDING here — forever, if that is how long the
-- venue takes. Absence of evidence is not evidence (§0.2).
--
-- DEPENDENCY: public.calls (this packet) and public.market_resolutions
-- (Packet B). current_app_user_id() is required by §5 for the read policy path.
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_results requires public.current_app_user_id() (Packet A: *_auth_identity_* migrations). Apply the auth-identity migrations first; contracts §5 requires every new policy to scope on it.';
  END IF;
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_results requires public.calls (apply 20260913140000_social_calls_calls.sql first).';
  END IF;
  IF to_regclass('public.market_resolutions') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_results requires public.market_resolutions (Packet B: *_venue_market_* migrations). §0.2 makes venue evidence the ONLY source of a result; without that table there is nothing legitimate to derive from.';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.call_results (
  -- One result per call, forever. The PK is the call id: there is no version,
  -- no revision and no "latest" to pick between.
  call_id UUID PRIMARY KEY REFERENCES public.calls(id) ON DELETE RESTRICT,

  outcome TEXT NOT NULL DEFAULT 'PENDING',

  -- The venue's Resolution this was derived from. NULL means the venue has not
  -- published one — which is the ONLY reason a result is PENDING.
  resolution TEXT,
  resolved_at TIMESTAMPTZ,

  -- The venue evidence this was derived from (§3). Not decorative: a settled
  -- row is unrepresentable without it.
  market_resolution_id UUID REFERENCES public.market_resolutions(id) ON DELETE RESTRICT,

  derived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT call_results_outcome_check CHECK (
    outcome IN ('PENDING', 'CORRECT', 'INCORRECT', 'VOID')
  ),
  CONSTRAINT call_results_resolution_check CHECK (
    resolution IS NULL OR resolution IN ('YES', 'NO', 'VOID')
  ),

  -- PENDING <=> no venue evidence at all. Both directions.
  CONSTRAINT call_results_pending_has_no_evidence CHECK (
    outcome <> 'PENDING'
    OR (resolution IS NULL AND resolved_at IS NULL AND market_resolution_id IS NULL)
  ),
  CONSTRAINT call_results_settled_requires_evidence CHECK (
    outcome = 'PENDING'
    OR (resolution IS NOT NULL AND resolved_at IS NOT NULL AND market_resolution_id IS NOT NULL)
  ),

  -- VOID <=> resolution 'VOID'. A VOID is never a win and never a loss, and a
  -- YES/NO resolution can never produce one. IS NOT DISTINCT FROM keeps this
  -- total: a CHECK that evaluates to NULL passes, so a three-valued comparison
  -- here would be a hole rather than a rule.
  CONSTRAINT call_results_void_iff_void_resolution CHECK (
    (outcome = 'VOID') = (resolution IS NOT DISTINCT FROM 'VOID')
  ),
  -- CORRECT/INCORRECT only ever come from a side resolution.
  CONSTRAINT call_results_sided_outcome_needs_sided_resolution CHECK (
    outcome NOT IN ('CORRECT', 'INCORRECT') OR COALESCE(resolution, '') IN ('YES', 'NO')
  )
);

-- The synchroniser's working set: every call still awaiting venue evidence.
CREATE INDEX IF NOT EXISTS idx_call_results_pending
  ON public.call_results (call_id)
  WHERE outcome = 'PENDING';

-- "Which calls did this venue resolution settle?" — the receipt's back-link.
CREATE INDEX IF NOT EXISTS idx_call_results_evidence
  ON public.call_results (market_resolution_id)
  WHERE market_resolution_id IS NOT NULL;

-- §5 mandatory template.
ALTER TABLE public.call_results ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.call_results FROM anon, authenticated;
GRANT ALL ON public.call_results TO service_role;

-- SELECT only. There is no INSERT, UPDATE or DELETE grant and no write policy
-- for anon or authenticated: §5, "call_results is service-write only".
GRANT SELECT ON public.call_results TO anon, authenticated;

-- A result is exactly as visible as the call it belongs to. The subquery is
-- itself subject to public.calls' RLS for anon/authenticated, so the
-- public/followers rule is inherited rather than restated. Never
-- USING (true) (§5).
DROP POLICY IF EXISTS call_results_visible_call_select ON public.call_results;
CREATE POLICY call_results_visible_call_select ON public.call_results
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (SELECT 1 FROM public.calls c WHERE c.id = call_results.call_id)
  );

-- No INSERT / UPDATE / DELETE policy. Deliberately. (§5)

-- ---------------------------------------------------------------------------
-- THE DERIVATION GUARD — §3's rule, and nothing else.
-- New, separately-named function; never CREATE OR REPLACE (§5).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.call_results_guard_derivation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
DECLARE
  v_side           TEXT;
  v_call_market    UUID;
  v_res_market     UUID;
  v_res_value      TEXT;
  v_res_resolvedat TIMESTAMPTZ;
  v_expected       TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- §3: hiding a call must not rewrite its CallResult or accuracy history.
    -- Deleting the result would do precisely that, so there is no path to it.
    RAISE EXCEPTION
      'call_results: a derived result is never deleted — accuracy history must survive a hidden call (contracts §3).'
      USING ERRCODE = 'raise_exception';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.call_id IS DISTINCT FROM OLD.call_id THEN
      RAISE EXCEPTION 'call_results: call_id is immutable.'
        USING ERRCODE = 'raise_exception';
    END IF;
    -- A settled result is permanent. It may be re-stated identically (which is
    -- what makes the synchroniser safe to run on a loop) and nothing else.
    IF OLD.outcome <> 'PENDING' THEN
      IF NEW.outcome            IS DISTINCT FROM OLD.outcome
         OR NEW.resolution      IS DISTINCT FROM OLD.resolution
         OR NEW.resolved_at     IS DISTINCT FROM OLD.resolved_at
         OR NEW.market_resolution_id IS DISTINCT FROM OLD.market_resolution_id THEN
        RAISE EXCEPTION
          'call_results: call % is already settled % from venue evidence %; a settled result is permanent and there is no admin override (contracts §0.2/§3).',
          OLD.call_id, OLD.outcome, OLD.market_resolution_id
          USING ERRCODE = 'raise_exception';
      END IF;
    END IF;
  END IF;

  SELECT c.side, c.market_id INTO v_side, v_call_market
    FROM public.calls c WHERE c.id = NEW.call_id;

  IF v_side IS NULL THEN
    RAISE EXCEPTION 'call_results: call % does not exist.', NEW.call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.market_resolution_id IS NULL THEN
    -- No venue evidence => PENDING. The only branch that produces PENDING, and
    -- the only outcome that no-evidence may produce.
    v_expected := 'PENDING';
  ELSE
    SELECT r.market_id, r.resolution, r.resolved_at
      INTO v_res_market, v_res_value, v_res_resolvedat
      FROM public.market_resolutions r WHERE r.id = NEW.market_resolution_id;

    IF v_res_market IS NULL THEN
      RAISE EXCEPTION 'call_results: market resolution % does not exist.', NEW.market_resolution_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- Evidence from another market is not evidence about this call.
    IF v_res_market <> v_call_market THEN
      RAISE EXCEPTION
        'call_results: resolution % is for market %, but call % is on market % (contracts §0.2).',
        NEW.market_resolution_id, v_res_market, NEW.call_id, v_call_market
        USING ERRCODE = 'raise_exception';
    END IF;

    -- The row must quote the evidence it cites, verbatim.
    IF NEW.resolution IS DISTINCT FROM v_res_value THEN
      RAISE EXCEPTION
        'call_results: resolution "%" does not match the venue evidence "%" it cites (call %).',
        NEW.resolution, v_res_value, NEW.call_id
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.resolved_at IS DISTINCT FROM v_res_resolvedat THEN
      RAISE EXCEPTION
        'call_results: resolved_at must be the venue''s own resolved_at (call %).', NEW.call_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- ★ §3's rule. The whole of it.
    v_expected := CASE
      WHEN v_res_value = 'VOID' THEN 'VOID'
      WHEN v_res_value = v_side THEN 'CORRECT'
      ELSE 'INCORRECT'
    END;
  END IF;

  IF NEW.outcome IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION
      'call_results: outcome "%" is not what contracts §3 derives for call % (side %, resolution %): expected "%". There is no other branch, no admin override and no client input.',
      NEW.outcome, NEW.call_id, v_side, COALESCE(NEW.resolution, 'none'), v_expected
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.call_results_guard_derivation() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.call_results_guard_derivation() TO service_role;

DROP TRIGGER IF EXISTS trg_call_results_guard_derivation ON public.call_results;
CREATE TRIGGER trg_call_results_guard_derivation
  BEFORE INSERT OR UPDATE OR DELETE ON public.call_results
  FOR EACH ROW
  EXECUTE FUNCTION public.call_results_guard_derivation();

COMMENT ON TABLE public.call_results IS
  'Service-derived call outcomes (contracts §0.2/§3/§5). Service-write only: anon and authenticated hold SELECT and nothing else, and there is no write policy. The §3 derivation is re-computed and enforced by a BEFORE INSERT/UPDATE trigger that binds service_role too, so no admin override exists in any layer. A settled result is permanent and may only be re-stated identically, which is what makes the resolution synchroniser idempotent. PENDING means the venue has published no resolution — never a timeout and never an inference.';
COMMENT ON COLUMN public.call_results.market_resolution_id IS
  'The public.market_resolutions row this outcome was derived from. NULL if and only if the outcome is PENDING: a settled result without venue evidence is not representable.';
COMMENT ON COLUMN public.call_results.outcome IS
  'CallOutcome (§3), derived ONLY as: resolution VOID -> VOID; resolution = call.side -> CORRECT; the other side -> INCORRECT; no resolution -> PENDING.';
