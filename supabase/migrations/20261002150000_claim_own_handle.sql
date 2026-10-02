-- Claim a @username for an account that has none — additive.
--
-- Accounts made before usernames existed, and existing wallet profiles carried
-- over to wallet sign-in (bind_wallet_session_v1), have handle NULL. Every
-- surface then shows a placeholder (`user-xxxxxxxx`). This lets the BFF set the
-- caller's OWN handle, once:
--
--   * the account is found by the verified Supabase subject (auth_user_id),
--     never by a user id or wallet the client names;
--   * a handle that is already set is never changed here (renaming is a
--     separate, unbuilt decision) — asking again for the same one is a no-op;
--   * the rules are handle_status_v1's (3–20 of a-z 0-9 _, reserved words) and
--     uniqueness is the uq_users_handle_lower index, so a lost race is
--     "taken", not a duplicate.
--
-- Service-role only, like every identity function. Nothing existing changes.

DO $$
BEGIN
  IF to_regprocedure('public.handle_status_v1(text)') IS NULL THEN
    RAISE EXCEPTION 'claim_own_handle requires 20261002090000_wallet_sign_in_and_usernames.sql';
  END IF;
  IF to_regclass('public.uq_users_handle_lower') IS NULL THEN
    RAISE EXCEPTION 'claim_own_handle requires the unique lower(handle) index (uq_users_handle_lower)';
  END IF;
END;
$$;

-- ok / 'claimed'             the handle is now the account's
-- ok / 'unchanged'           the account already has exactly this handle
-- fail / 'unknown_user'      no account reaches this sign-in
-- fail / 'handle_already_set' the account has a different handle; not renamed
-- fail / 'handle_invalid' | 'handle_reserved' | 'handle_taken'
CREATE FUNCTION public.claim_own_handle_v1(p_auth_user_id UUID, p_handle TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user    UUID;
  v_current TEXT;
  v_handle  TEXT := lower(btrim(coalesce(p_handle, '')));
  v_status  TEXT;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  -- Locks the row: two claims for the same account serialise here.
  SELECT id, handle INTO v_user, v_current
    FROM public.users WHERE auth_user_id = p_auth_user_id
    FOR UPDATE;
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  IF v_current IS NOT NULL THEN
    IF lower(v_current) = v_handle THEN
      RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'handle', v_current, 'outcome', 'unchanged');
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'handle_already_set');
  END IF;

  v_status := public.handle_status_v1(v_handle);
  IF v_status <> 'available' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'handle_' || v_status);
  END IF;

  BEGIN
    UPDATE public.users
       SET handle = v_handle, updated_at = NOW()
     WHERE id = v_user AND handle IS NULL;
  EXCEPTION WHEN unique_violation THEN
    -- Another account claimed it between the check and the write.
    RETURN jsonb_build_object('ok', false, 'reason', 'handle_taken');
  END;

  RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'handle', v_handle, 'outcome', 'claimed');
END;
$$;
REVOKE ALL ON FUNCTION public.claim_own_handle_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_own_handle_v1(UUID, TEXT) TO service_role;
COMMENT ON FUNCTION public.claim_own_handle_v1(UUID, TEXT) IS
  'Service-only: the account reached by this verified Supabase subject claims a @username, only while it has none. Never renames, never acts on another account.';
