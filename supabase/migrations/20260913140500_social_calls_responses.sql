-- ============================================================================
-- PACKET D — public.call_responses: Back, Fade, Challenge
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §3 (CallResponse: "back/fade ALWAYS create
--           the actor's own call"), §5 (default-deny, no USING (true), pinned
--           search_path, never CREATE OR REPLACE an existing function)
-- ============================================================================
--
-- THE RULE THIS TABLE MAKES STRUCTURAL
--
--   §3, on CallResponse.resultingCallId: "back/fade ALWAYS create the actor's
--   own call".
--
-- That is a CHECK constraint here, not a service-layer convention:
--
--     kind IN ('back','fade')  =>  resulting_call_id IS NOT NULL
--     kind = 'challenge'       =>  resulting_call_id IS NULL
--
-- A back or fade that produced no call is not representable. A challenge that
-- produced one is not representable either.
--
-- AND WHAT A CHALLENGE IS NOT
--
-- There is no amount column, no escrow column, no stake column, no transaction
-- column and no currency column on this table. A challenge is a dare to go on
-- record, not a wager, and the schema is where that is true — a service can be
-- rewritten, a column cannot be filled in if it does not exist. §3 freezes
-- `kind = 'challenge'` but declares no invitation shape, so the invitation the
-- mobile slice renders is derived from this row and carries nothing more.
--
-- DEPENDENCY: public.current_app_user_id() (Packet A) and public.calls
-- (this packet's *_social_calls_calls* migration).
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_responses requires public.current_app_user_id() (Packet A: *_auth_identity_* migrations). Apply the auth-identity migrations first; contracts §5 requires every new policy to scope on it.';
  END IF;
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_responses requires public.calls (apply 20260913140000_social_calls_calls.sql first).';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.call_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- §0.3: canonical public.users.id, never a wallet.
  actor_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

  -- ON DELETE RESTRICT everywhere: a call is never deleted anyway (see the
  -- calls migration), and a response is a timestamped fact about one.
  target_call_id UUID NOT NULL REFERENCES public.calls(id) ON DELETE RESTRICT,

  kind TEXT NOT NULL,

  -- back/fade: the actor's OWN call, which this response created.
  -- challenge:  NULL, always.
  resulting_call_id UUID REFERENCES public.calls(id) ON DELETE RESTRICT,

  -- A challenge may carry a line of trash talk. It may not carry money; there
  -- is no column that could.
  note TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT call_responses_kind_check CHECK (kind IN ('back', 'fade', 'challenge')),
  CONSTRAINT call_responses_note_length CHECK (note IS NULL OR length(note) <= 280),

  -- ★ THE RULE (§3). Back and Fade always mint the actor's own call; a
  --   challenge never does.
  CONSTRAINT call_responses_resulting_call_matches_kind CHECK (
    (kind IN ('back', 'fade') AND resulting_call_id IS NOT NULL)
    OR (kind = 'challenge' AND resulting_call_id IS NULL)
  ),

  -- A response never points its result at the very call it responded to.
  CONSTRAINT call_responses_resulting_is_not_target CHECK (
    resulting_call_id IS NULL OR resulting_call_id <> target_call_id
  ),

  -- One of each kind per actor per target. A repeated tap is the same fact.
  UNIQUE (actor_user_id, target_call_id, kind)
);

-- One resulting call belongs to exactly one response: a call cannot have been
-- minted by two different Backs.
CREATE UNIQUE INDEX IF NOT EXISTS uq_call_responses_resulting_call
  ON public.call_responses (resulting_call_id)
  WHERE resulting_call_id IS NOT NULL;

-- The back/fade counters on a feed row.
CREATE INDEX IF NOT EXISTS idx_call_responses_target
  ON public.call_responses (target_call_id, kind);

-- "My invitations": challenges pointed at calls I made.
CREATE INDEX IF NOT EXISTS idx_call_responses_challenges
  ON public.call_responses (target_call_id, created_at DESC)
  WHERE kind = 'challenge';

CREATE INDEX IF NOT EXISTS idx_call_responses_actor
  ON public.call_responses (actor_user_id, created_at DESC);

-- §5 mandatory template.
ALTER TABLE public.call_responses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.call_responses FROM anon, authenticated;
GRANT ALL ON public.call_responses TO service_role;

GRANT SELECT ON public.call_responses TO anon, authenticated;
GRANT INSERT (actor_user_id, target_call_id, kind, resulting_call_id, note)
  ON public.call_responses TO authenticated;

-- ── SELECT: a response is exactly as visible as the call it is about. ──
-- The EXISTS subquery is itself subject to public.calls' RLS for anon and
-- authenticated, so the public/followers rule is inherited rather than
-- restated (and therefore cannot drift out of step with it). Never
-- USING (true) (§5).
DROP POLICY IF EXISTS call_responses_visible_target_select ON public.call_responses;
CREATE POLICY call_responses_visible_target_select ON public.call_responses
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.calls c WHERE c.id = call_responses.target_call_id
    )
  );

-- The actor always sees their own responses, even if the target has since been
-- hidden by its author.
DROP POLICY IF EXISTS call_responses_actor_select ON public.call_responses;
CREATE POLICY call_responses_actor_select ON public.call_responses
  FOR SELECT
  TO authenticated
  USING (actor_user_id = public.current_app_user_id());

-- ── INSERT: only as yourself, and only against a call you can actually see. ──
DROP POLICY IF EXISTS call_responses_actor_insert ON public.call_responses;
CREATE POLICY call_responses_actor_insert ON public.call_responses
  FOR INSERT
  TO authenticated
  WITH CHECK (
    actor_user_id = public.current_app_user_id()
    AND EXISTS (
      SELECT 1 FROM public.calls c WHERE c.id = call_responses.target_call_id
    )
    AND (
      resulting_call_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.calls rc
        WHERE rc.id = call_responses.resulting_call_id
          AND rc.user_id = public.current_app_user_id()
      )
    )
  );

-- No UPDATE and no DELETE policy: a response is an append-only fact.

-- ---------------------------------------------------------------------------
-- Append-only + cross-row rules a CHECK cannot see.
-- New, separately-named function (§5).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.call_responses_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
DECLARE
  v_target_user   UUID;
  v_target_market UUID;
  v_target_side   TEXT;
  v_result_user   UUID;
  v_result_market UUID;
  v_result_side   TEXT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION
      'call_responses is append-only: a response is a timestamped fact. Insert a new row instead (call_responses %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'call_responses is append-only: a response may never be deleted (call_responses %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;

  SELECT c.user_id, c.market_id, c.side
    INTO v_target_user, v_target_market, v_target_side
    FROM public.calls c WHERE c.id = NEW.target_call_id;

  IF v_target_user IS NULL THEN
    RAISE EXCEPTION 'call_responses: target call % does not exist.', NEW.target_call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  -- You cannot back, fade or challenge yourself. Every one of the three is a
  -- statement about someone ELSE's call.
  IF v_target_user = NEW.actor_user_id THEN
    RAISE EXCEPTION
      'call_responses: you cannot % your own call (call %).', NEW.kind, NEW.target_call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.resulting_call_id IS NOT NULL THEN
    SELECT c.user_id, c.market_id, c.side
      INTO v_result_user, v_result_market, v_result_side
      FROM public.calls c WHERE c.id = NEW.resulting_call_id;

    IF v_result_user IS NULL THEN
      RAISE EXCEPTION 'call_responses: resulting call % does not exist.', NEW.resulting_call_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- "back/fade ALWAYS create the ACTOR'S OWN call" (§3).
    IF v_result_user <> NEW.actor_user_id THEN
      RAISE EXCEPTION
        'call_responses: a % must create the ACTOR''S OWN call — resulting call % belongs to someone else (contracts §3).',
        NEW.kind, NEW.resulting_call_id
        USING ERRCODE = 'raise_exception';
    END IF;

    IF v_result_market <> v_target_market THEN
      RAISE EXCEPTION
        'call_responses: a % must be on the same market as the call it responds to.', NEW.kind
        USING ERRCODE = 'raise_exception';
    END IF;

    -- Back = same side. Fade = the other side. Those are the words' meanings.
    IF NEW.kind = 'back' AND v_result_side <> v_target_side THEN
      RAISE EXCEPTION
        'call_responses: a back must take the SAME side as the call it backs (% vs %).', v_result_side, v_target_side
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.kind = 'fade' AND v_result_side = v_target_side THEN
      RAISE EXCEPTION
        'call_responses: a fade must take the OPPOSITE side to the call it fades (both are %).', v_target_side
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.call_responses_guard() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.call_responses_guard() TO service_role;

DROP TRIGGER IF EXISTS trg_call_responses_guard ON public.call_responses;
CREATE TRIGGER trg_call_responses_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.call_responses
  FOR EACH ROW
  EXECUTE FUNCTION public.call_responses_guard();

COMMENT ON TABLE public.call_responses IS
  'Back / Fade / Challenge (contracts §3). Back and Fade ALWAYS carry the actor''s own resulting call; a challenge NEVER does — enforced by a CHECK, not a convention. There is no amount, escrow, stake or transaction column: a challenge is a dare to go on record, not a wager, and the absence of the column is the enforcement. Append-only; as visible as the call it is about.';
COMMENT ON COLUMN public.call_responses.resulting_call_id IS
  'The actor''s OWN call, minted by a back (same side) or a fade (opposite side). NULL for a challenge, by CHECK.';
COMMENT ON COLUMN public.call_responses.note IS
  'Optional trash talk on a challenge. The only free-text a response carries, and the only thing it carries beyond the three ids.';
