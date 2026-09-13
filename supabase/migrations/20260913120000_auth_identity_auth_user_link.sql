-- ============================================================================
-- AUTH IDENTITY 1/4 — link public.users to auth.users, and the canonical
--                     "who am I" function every new RLS policy reads.
-- Packet: A (identity)   Created: 2026-09-13
-- Contract: pivot-contracts-v1 §2 (blocker: no auth.uid() anywhere in the
--           schema), §5 (additive only, default-deny, pinned search_path).
-- ============================================================================
--
-- Invariant 3 of the pivot: identity IS public.users.id. A wallet is a linked
-- credential, never an authorisation. Today nothing in the schema connects a
-- Supabase Auth session to a canonical row, so no policy can be written at all.
-- This migration adds that single missing edge.
--
-- Purely additive:
--   * one new nullable column on public.users
--   * one new index
--   * one new function
-- No existing column is dropped or retyped; no existing policy is touched; no
-- existing function is redefined (contract §5 — record_prediction_call is the
-- cautionary tale).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. public.users.auth_user_id
-- ---------------------------------------------------------------------------
-- Nullable on purpose: every pre-existing row keeps working unlinked, and a
-- deleted auth user degrades the app account to "no session" rather than
-- cascading away real social history (ON DELETE SET NULL).

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS auth_user_id UUID;

-- Constraints added separately and idempotently: `ADD COLUMN IF NOT EXISTS ...
-- UNIQUE REFERENCES` silently skips the constraints when the column already
-- exists (a re-run, or a column hand-added in the SQL editor — contract §9
-- warns the repo schema is not the live schema).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
     WHERE conrelid = 'public.users'::regclass
       AND conname  = 'users_auth_user_id_key'
  ) THEN
    ALTER TABLE public.users ADD CONSTRAINT users_auth_user_id_key UNIQUE (auth_user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
     WHERE conrelid = 'public.users'::regclass
       AND conname  = 'users_auth_user_id_fkey'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_auth_user_id_fkey
      FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END
$$;

-- The UNIQUE constraint's index answers `auth_user_id = $1`. This partial index
-- is the one that stays small and is what the linked-account audit/backfill
-- sweeps ("which app users have a session yet?") actually scan.
CREATE INDEX IF NOT EXISTS idx_users_auth_user_id
  ON public.users (auth_user_id)
  WHERE auth_user_id IS NOT NULL;

COMMENT ON COLUMN public.users.auth_user_id IS
  'Supabase auth.users.id for this canonical account. UNIQUE: one session identity maps to exactly one public.users row. NULL = legacy account with no Supabase session yet. Never client-writable (see the column grants below).';

-- ---------------------------------------------------------------------------
-- 2. Fence the new column off from anon/authenticated writes.
-- ---------------------------------------------------------------------------
-- Contract §8 finding 1 is live: 001_complete_schema.sql:587 granted ALL on
-- every public table to anon/authenticated, and users_insert/users_update are
-- `WITH CHECK (true)` / `USING (true)`. Anon can therefore still rewrite any
-- public.users row. Fixing THAT is a production change requiring founder
-- approval and is explicitly out of packet scope — but it must not be widened:
-- an anon-writable auth_user_id would let anyone repoint any account at their
-- own session and take it over. That would be a new, packet-introduced hole.
--
-- A column-level REVOKE is a no-op while a table-level grant is held (proved
-- live in 20260719161500). The established correction is: revoke the table
-- grant, re-grant every OTHER column. Done dynamically so that columns present
-- only in the live database (contract §9) keep exactly the access they had.
--
-- Net effect: behaviour for every pre-existing column is unchanged; the new
-- column is service-role-only; a FUTURE users column is fail-closed, matching
-- the precedent set by 20260719161500.
DO $$
DECLARE
  v_cols TEXT;
BEGIN
  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
    INTO v_cols
    FROM information_schema.columns c
   WHERE c.table_schema = 'public'
     AND c.table_name   = 'users'
     AND c.column_name <> 'auth_user_id';

  EXECUTE 'REVOKE INSERT, UPDATE ON public.users FROM anon, authenticated';

  IF v_cols IS NOT NULL THEN
    EXECUTE format('GRANT INSERT (%s) ON public.users TO anon, authenticated', v_cols);
    EXECUTE format('GRANT UPDATE (%s) ON public.users TO anon, authenticated', v_cols);
  END IF;
END
$$;

GRANT ALL ON public.users TO service_role;

-- ---------------------------------------------------------------------------
-- 3. public.current_app_user_id() — the one authorisation primitive
-- ---------------------------------------------------------------------------
-- Contract §5: EVERY new policy reads `USING (user_id = public.current_app_user_id())`.
--
-- Takes no argument, so it cannot be used to probe another account: it returns
-- the caller's own canonical id or NULL. NULL is the safe value — `user_id =
-- NULL` is NULL, which a policy treats as "no rows", so an unauthenticated
-- caller sees nothing rather than everything.
--
-- STABLE (not VOLATILE): the mapping cannot change inside one statement, so the
-- planner may evaluate it once per query instead of once per row.
--
-- SECURITY DEFINER because public.users SELECT is column-restricted for
-- anon/authenticated (20260719161500) and will be restricted further; the
-- lookup must not depend on the caller's own read grants.
CREATE FUNCTION public.current_app_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
  SELECT u.id
    FROM public.users u
   WHERE u.auth_user_id = auth.uid()
$$;

COMMENT ON FUNCTION public.current_app_user_id() IS
  'The canonical public.users.id for the current Supabase session, or NULL when there is no session. The only identity primitive new RLS policies may use. Argument-free by design: it can never be pointed at another account.';

-- Grants. This is the one documented deviation from the contract §5 function
-- template, and it is forced by contract §5 itself:
--
--   §5 template says: REVOKE EXECUTE FROM PUBLIC, anon, authenticated.
--   §5 tables rule says: every new policy reads current_app_user_id().
--
-- An RLS policy expression is evaluated AS THE CALLING ROLE. If `authenticated`
-- cannot EXECUTE this function, every policy that uses it raises
-- "permission denied for function current_app_user_id" and the tables are
-- unreadable rather than default-deny. So `authenticated` MUST hold EXECUTE.
--
-- This is safe precisely because the function is argument-free and derived
-- wholly from auth.uid(): granting it leaks nothing but the caller's own id.
-- `anon` is NOT granted — anon has no auth.uid(), so it would only ever get
-- NULL, and withholding it keeps the blast radius minimal.
REVOKE EXECUTE ON FUNCTION public.current_app_user_id() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.current_app_user_id() TO authenticated, service_role;
