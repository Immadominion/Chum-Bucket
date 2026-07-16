-- ============================================================================
-- IDENTITY LINKING — link a Google/X identity to a wallet, enrich display
-- Created: 2026-07-16
-- ============================================================================
--
-- The wallet stays the transaction authority (MWA); Google/X are LINKED social
-- identities that make callers recognizable in the FOMO feed ("@handle" +
-- avatar instead of a 44-char wallet). Flow: the client signs in with Supabase
-- Auth (Google/X, browser flow), the backend verifies that OAuth session AND a
-- wallet signature, then calls link_identity to attach the provider identity to
-- the wallet's user and enrich the user's display fields.
--
-- Identities are network-agnostic (a person is the same on devnet/mainnet).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.link_identity(
  p_wallet TEXT,
  p_provider TEXT,
  p_provider_subject TEXT,
  p_provider_username TEXT DEFAULT NULL,
  p_provider_display_name TEXT DEFAULT NULL,
  p_provider_avatar_url TEXT DEFAULT NULL,
  p_provider_email TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_provider TEXT := lower(coalesce(p_provider, ''));
  v_id UUID;
BEGIN
  IF p_provider_subject IS NULL OR length(trim(p_provider_subject)) = 0 THEN
    RAISE EXCEPTION 'provider subject is required';
  END IF;
  -- Coerce X's various provider names into the allowed set.
  IF v_provider IN ('x', 'x.com', 'twitter.com') THEN v_provider := 'twitter'; END IF;

  v_user_id := public.sync_user_by_wallet(p_wallet);

  INSERT INTO public.linked_identities (
    user_id, provider, provider_subject, provider_username,
    provider_display_name, provider_avatar_url, provider_email, verified_at
  ) VALUES (
    v_user_id, v_provider, trim(p_provider_subject), p_provider_username,
    p_provider_display_name, p_provider_avatar_url, p_provider_email, NOW()
  )
  ON CONFLICT (provider, provider_subject) DO UPDATE
  SET
    user_id = EXCLUDED.user_id,  -- re-link to the wallet the person just proved
    provider_username = COALESCE(EXCLUDED.provider_username, public.linked_identities.provider_username),
    provider_display_name = COALESCE(EXCLUDED.provider_display_name, public.linked_identities.provider_display_name),
    provider_avatar_url = COALESCE(EXCLUDED.provider_avatar_url, public.linked_identities.provider_avatar_url),
    provider_email = COALESCE(EXCLUDED.provider_email, public.linked_identities.provider_email),
    verified_at = NOW(),
    updated_at = NOW()
  RETURNING id INTO v_id;

  -- Enrich the user's display from the identity. X username becomes the handle;
  -- name/avatar/email only fill EMPTY fields so we never clobber a chosen value.
  UPDATE public.users
  SET
    handle = CASE
      WHEN v_provider = 'twitter' AND p_provider_username IS NOT NULL THEN COALESCE(NULLIF(handle, ''), p_provider_username)
      ELSE handle END,
    full_name = COALESCE(NULLIF(full_name, ''), p_provider_display_name, full_name),
    profile_picture = COALESCE(NULLIF(profile_picture, ''), p_provider_avatar_url, profile_picture),
    email = COALESCE(NULLIF(email, ''), p_provider_email, email),
    updated_at = NOW()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('linkedIdentityId', v_id, 'userId', v_user_id, 'provider', v_provider);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- Batch resolve wallet -> display (handle / name / avatar / X handle / verified).
-- The UI renders a feed of wallets, then calls this once to show recognizable
-- names + avatars. Anon-callable; returns only public display data.
CREATE OR REPLACE FUNCTION public.wallet_profiles(p_wallets TEXT[])
RETURNS TABLE (
  wallet_address TEXT,
  handle TEXT,
  display_name TEXT,
  avatar_url TEXT,
  x_handle TEXT,
  verified BOOLEAN
) AS $$
  SELECT
    u.wallet_address,
    u.handle,
    u.full_name,
    u.profile_picture,
    (SELECT li.provider_username FROM public.linked_identities li
       WHERE li.user_id = u.id AND li.provider = 'twitter' AND li.provider_username IS NOT NULL LIMIT 1) AS x_handle,
    EXISTS (SELECT 1 FROM public.linked_identities li
       WHERE li.user_id = u.id AND li.provider IN ('twitter', 'google')) AS verified
  FROM public.users u
  WHERE u.wallet_address = ANY(p_wallets);
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- link_identity is a WRITE => backend/service-role only (backend verifies BOTH
-- the Supabase OAuth session and the wallet signature before calling it).
REVOKE EXECUTE ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Links a verified Google/X identity to a wallet user and enriches display fields. Backend-only.';
COMMENT ON FUNCTION public.wallet_profiles(TEXT[]) IS 'Batch wallet -> public display (handle/name/avatar/x_handle/verified) for feed rendering.';
