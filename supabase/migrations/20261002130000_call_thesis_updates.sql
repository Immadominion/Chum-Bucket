-- ============================================================================
-- public.call_thesis_updates: the thesis as an append-only thread
-- Created: 2026-10-02
-- Additive only. Creates one table, one guard function and one trigger. No
-- existing table, column, policy or function is altered.
-- ============================================================================
--
-- WHAT THIS ADDS
--
--   A caller can follow their own call with short, timestamped updates — "the
--   ETF flows are still accelerating", "the funding rate flipped" — the way a
--   thesis on a position grows a thread. The ORIGINAL reason is not touched:
--   calls.thesis stays frozen with the call at locked_at, exactly as
--   calls_guard_immutability already enforces. An update is a separate row,
--   written after the lock, with its own created_at, so a reader can always
--   tell what was said before the result from what was said after it.
--
-- THE RULES, ENFORCED HERE AS WELL AS IN THE BFF
--
--   * author-only    author_user_id must be the call's user_id
--   * append-only    UPDATE and DELETE are refused for EVERY role, the service
--                    role included (a trigger, because RLS does not bind it)
--   * after the lock created_at >= calls.locked_at
--   * not withdrawn  a hidden call takes no NEW update (rows written before the
--                    hide stay, as history does)
--   * bounded        1..280 characters after trimming (the calls.thesis bound),
--                    and at most 20 updates per call, so a thread stays a thread
--
-- WHO MAY READ IT
--
--   Exactly whoever may read the call. The SELECT policy is an EXISTS over
--   public.calls, which is itself subject to calls' RLS for anon and
--   authenticated — so public / followers-only / hidden-to-everyone-but-the-
--   author are inherited rather than restated, and cannot drift out of step.
--
-- WHO MAY WRITE IT
--
--   Only the BFF (service_role), after it has mapped a verified session to
--   public.users.id. No INSERT is granted to anon or authenticated: one write
--   path keeps the per-call cap and the author rule in one place, and the
--   trigger below re-checks them for that path too.
--
-- DEPENDENCIES: public.current_app_user_id() is NOT used (no client policy
-- scopes on the session); public.users and public.calls must exist.
-- ============================================================================

DO $$
BEGIN
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION
      'call_thesis_updates requires public.calls (apply 20260913140000_social_calls_calls.sql first).';
  END IF;
  IF to_regclass('public.users') IS NULL THEN
    RAISE EXCEPTION 'call_thesis_updates requires public.users.';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.call_thesis_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- ON DELETE RESTRICT: a call is never deleted (calls_guard_immutability),
  -- and the thread is part of its history.
  call_id UUID NOT NULL REFERENCES public.calls(id) ON DELETE RESTRICT,

  -- canonical public.users.id, never a wallet.
  author_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

  body TEXT NOT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT call_thesis_updates_body_length CHECK (
    length(btrim(body)) BETWEEN 1 AND 280
  )
);

-- The thread, in order, for one call.
CREATE INDEX IF NOT EXISTS idx_call_thesis_updates_call
  ON public.call_thesis_updates (call_id, created_at, id);

ALTER TABLE public.call_thesis_updates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.call_thesis_updates FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.call_thesis_updates TO service_role;
GRANT SELECT ON public.call_thesis_updates TO anon, authenticated;

-- ── SELECT: exactly as visible as the call. Never USING (true). ──
DROP POLICY IF EXISTS call_thesis_updates_visible_call_select ON public.call_thesis_updates;
CREATE POLICY call_thesis_updates_visible_call_select ON public.call_thesis_updates
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.calls c WHERE c.id = call_thesis_updates.call_id
    )
  );

-- No INSERT, UPDATE or DELETE policy and no such grant to a client role.

-- ---------------------------------------------------------------------------
-- The guard: append-only, author-only, after the lock, not withdrawn, capped.
-- A new, separately-named function; nothing existing is replaced.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.call_thesis_updates_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_author    UUID;
  v_locked_at TIMESTAMPTZ;
  v_hidden_at TIMESTAMPTZ;
  v_count     INTEGER;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION
      'call_thesis_updates is append-only: an update is a timestamped statement. Post a new one instead (call_thesis_updates %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'call_thesis_updates is append-only: an update may never be deleted (call_thesis_updates %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;

  -- Serialise appends to one call so the cap below cannot be raced past.
  SELECT c.user_id, c.locked_at, c.hidden_at
    INTO v_author, v_locked_at, v_hidden_at
    FROM public.calls c
   WHERE c.id = NEW.call_id
     FOR UPDATE;

  IF v_author IS NULL THEN
    RAISE EXCEPTION 'call_thesis_updates: call % does not exist.', NEW.call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.author_user_id <> v_author THEN
    RAISE EXCEPTION
      'call_thesis_updates: only the author of call % may add to its thesis.', NEW.call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.created_at < v_locked_at THEN
    RAISE EXCEPTION
      'call_thesis_updates: an update cannot be dated before its call locked (call %).', NEW.call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  IF v_hidden_at IS NOT NULL THEN
    RAISE EXCEPTION
      'call_thesis_updates: call % was withdrawn, so its thesis takes no new updates.', NEW.call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  SELECT count(*) INTO v_count FROM public.call_thesis_updates u WHERE u.call_id = NEW.call_id;
  IF v_count >= 20 THEN
    RAISE EXCEPTION
      'call_thesis_updates: call % already carries 20 updates, the most one call can.', NEW.call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  NEW.body := btrim(NEW.body);
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.call_thesis_updates_guard() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.call_thesis_updates_guard() TO service_role;

DROP TRIGGER IF EXISTS trg_call_thesis_updates_guard ON public.call_thesis_updates;
CREATE TRIGGER trg_call_thesis_updates_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.call_thesis_updates
  FOR EACH ROW
  EXECUTE FUNCTION public.call_thesis_updates_guard();

COMMENT ON TABLE public.call_thesis_updates IS
  'Append-only, author-only follow-ups to a call''s thesis. The original calls.thesis is immutable; each update is a separate timestamped row after locked_at. As visible as its call. Written only by the BFF (service_role); UPDATE and DELETE are refused for every role.';
COMMENT ON COLUMN public.call_thesis_updates.body IS
  '1..280 characters after trimming, the same bound as calls.thesis.';
