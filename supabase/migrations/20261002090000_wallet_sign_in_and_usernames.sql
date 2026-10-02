-- Wallet sign-in and usernames — additive.
--
-- One Chumbucket account, reachable by a Solana wallet (Supabase Auth Web3,
-- "Sign in with Solana"), Google or X. The first time, the person claims a
-- @username. Nothing here changes an existing grant, policy, row or function;
-- the lockdown of the old client-writable identity paths is a separate
-- migration, applied after the app stops depending on them.
--
-- Everything below is service-role only. The wallet address passed in is never
-- a client claim: the BFF reads it from the Web3 identity that Supabase Auth
-- created after verifying the wallet's signature.

DO $$
BEGIN
  IF to_regprocedure('public.create_social_person_v1(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'wallet_sign_in_and_usernames requires 20260928100000_social_person_onboarding.sql';
  END IF;
  IF to_regclass('public.wallet_link_audit') IS NULL THEN
    RAISE EXCEPTION 'wallet_sign_in_and_usernames requires 20260913121500_auth_identity_linked_wallets.sql';
  END IF;
  -- The unique index below would fail on duplicates; say so plainly instead.
  IF EXISTS (
    SELECT lower(handle) FROM public.users
    WHERE handle IS NOT NULL GROUP BY lower(handle) HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'public.users has case-insensitive duplicate handles; resolve them before usernames can be unique';
  END IF;
END;
$$;

-- ── usernames are unique, case-insensitively ────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_handle_lower
  ON public.users (lower(handle))
  WHERE handle IS NOT NULL;

-- 'available' | 'invalid' | 'reserved' | 'taken'. Format: 3–20 of a-z, 0-9, _.
CREATE FUNCTION public.handle_status_v1(p_handle TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_handle TEXT := lower(btrim(coalesce(p_handle, '')));
BEGIN
  IF v_handle !~ '^[a-z0-9_]{3,20}$' THEN
    RETURN 'invalid';
  END IF;
  IF v_handle IN (
    'admin', 'administrator', 'chumbucket', 'support', 'help', 'official',
    'team', 'staff', 'mod', 'moderator', 'system', 'root', 'null', 'undefined',
    'panta', 'me', 'you', 'everyone', 'settings', 'profile'
  ) OR v_handle LIKE 'caller\_%' THEN
    RETURN 'reserved';
  END IF;
  IF EXISTS (SELECT 1 FROM public.users u WHERE lower(u.handle) = v_handle) THEN
    RETURN 'taken';
  END IF;
  RETURN 'available';
END;
$$;
REVOKE ALL ON FUNCTION public.handle_status_v1(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_status_v1(TEXT) TO service_role;

-- ── a new account: claim a username, optionally with a verified wallet ──────

CREATE FUNCTION public.create_social_person_v2(
  p_auth_user_id   UUID,
  p_display_name   TEXT,
  p_handle         TEXT,
  p_wallet_address TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_existing UUID;
  v_id       UUID := gen_random_uuid();
  v_name     TEXT := btrim(coalesce(p_display_name, ''));
  v_handle   TEXT := lower(btrim(coalesce(p_handle, '')));
  v_wallet   TEXT := nullif(btrim(coalesce(p_wallet_address, '')), '');
  v_status   TEXT;
BEGIN
  IF p_auth_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_auth_user');
  END IF;

  -- One sign-in, one account: a repeat is the same answer, not a second row.
  SELECT id INTO v_existing FROM public.users WHERE auth_user_id = p_auth_user_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'user_id', v_existing, 'outcome', 'existing');
  END IF;

  IF length(v_name) NOT BETWEEN 1 AND 60 OR v_name ~ '[[:cntrl:]]' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_name');
  END IF;
  v_status := public.handle_status_v1(v_handle);
  IF v_status <> 'available' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'handle_' || v_status);
  END IF;

  -- A wallet that already belongs to an account is carried over, never given
  -- a second one (that is bind_wallet_session_v1's job, behind its own gate).
  IF v_wallet IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.users u WHERE u.wallet_address = v_wallet)
    OR EXISTS (SELECT 1 FROM public.linked_wallets w WHERE w.wallet_address = v_wallet AND w.revoked_at IS NULL)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'wallet_has_profile');
  END IF;

  BEGIN
    INSERT INTO public.users (id, auth_user_id, full_name, handle, wallet_address, created_at, updated_at)
    VALUES (v_id, p_auth_user_id, v_name, v_handle, v_wallet, NOW(), NOW());
  EXCEPTION WHEN unique_violation THEN
    -- Lost a race for the same username, wallet or sign-in. Say which honestly.
    SELECT id INTO v_existing FROM public.users WHERE auth_user_id = p_auth_user_id;
    IF v_existing IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'user_id', v_existing, 'outcome', 'existing');
    END IF;
    IF v_wallet IS NOT NULL AND EXISTS (SELECT 1 FROM public.users u WHERE u.wallet_address = v_wallet) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'wallet_has_profile');
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'handle_taken');
  END;

  IF v_wallet IS NOT NULL THEN
    -- Proven by the Sign-in-with-Solana (v1 format) signature Supabase Auth
    -- verified to create this session.
    INSERT INTO public.linked_wallets (
      user_id, wallet_address, wallet_type, is_primary,
      first_seen_at, last_signed_at, siws_proof_version, verified_at
    ) VALUES (v_id, v_wallet, 'mwa', true, NOW(), NOW(), 1, NOW());
    INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, to_user_id, reason)
    VALUES (v_wallet, 'linked', NULL, v_id, 'new account from wallet sign-in');
  END IF;

  RETURN jsonb_build_object('ok', true, 'user_id', v_id, 'outcome', 'created');
END;
$$;
REVOKE ALL ON FUNCTION public.create_social_person_v2(UUID, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_social_person_v2(UUID, TEXT, TEXT, TEXT) TO service_role;
COMMENT ON FUNCTION public.create_social_person_v2(UUID, TEXT, TEXT, TEXT) IS
  'Service-only onboarding: a verified Supabase subject claims a unique @username; a wallet sign-in attaches its signature-verified wallet. Never claims or merges an existing account.';

-- ── carry an existing account over to a verified wallet session ─────────────
--
-- Trusts public.users.wallet_address, which the old client paths could write.
-- The API calls this only once those paths are closed (and only with an
-- address Supabase Auth verified); until then it is never reached.

CREATE FUNCTION public.bind_wallet_session_v1(p_auth_user_id UUID, p_wallet_address TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_existing UUID;
  v_target   UUID;
  v_owner    UUID;
  v_wallet   TEXT := nullif(btrim(coalesce(p_wallet_address, '')), '');
BEGIN
  IF p_auth_user_id IS NULL OR v_wallet IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;

  SELECT id INTO v_existing FROM public.users WHERE auth_user_id = p_auth_user_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'user_id', v_existing, 'outcome', 'existing');
  END IF;

  SELECT id, auth_user_id INTO v_target, v_owner
    FROM public.users WHERE wallet_address = v_wallet
    FOR UPDATE;
  IF v_target IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_profile');
  END IF;
  IF v_owner IS NOT NULL THEN
    -- Already reachable through another sign-in. Never moved silently.
    RETURN jsonb_build_object('ok', false, 'reason', 'owned');
  END IF;

  UPDATE public.users SET auth_user_id = p_auth_user_id, updated_at = NOW()
   WHERE id = v_target AND auth_user_id IS NULL;

  UPDATE public.linked_wallets
     SET siws_proof_version = 1, verified_at = NOW(), revoked_at = NULL,
         last_signed_at = NOW(), updated_at = NOW()
   WHERE wallet_address = v_wallet AND user_id = v_target;
  IF NOT FOUND THEN
    INSERT INTO public.linked_wallets (
      user_id, wallet_address, wallet_type, is_primary,
      first_seen_at, last_signed_at, siws_proof_version, verified_at
    ) VALUES (v_target, v_wallet, 'mwa',
      NOT EXISTS (SELECT 1 FROM public.linked_wallets w WHERE w.user_id = v_target AND w.revoked_at IS NULL),
      NOW(), NOW(), 1, NOW());
  END IF;
  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, to_user_id, reason)
  VALUES (v_wallet, 'reaffirmed', v_target, v_target, 'existing account carried over to wallet sign-in');

  RETURN jsonb_build_object('ok', true, 'user_id', v_target, 'outcome', 'carried');
END;
$$;
REVOKE ALL ON FUNCTION public.bind_wallet_session_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_wallet_session_v1(UUID, TEXT) TO service_role;
COMMENT ON FUNCTION public.bind_wallet_session_v1(UUID, TEXT) IS
  'Service-only: binds a Supabase Web3 (Solana) sign-in to the existing account whose wallet it is, when that account has no other sign-in. Relies on public.users.wallet_address, so the API keeps it off until the client-writable identity paths are closed.';
