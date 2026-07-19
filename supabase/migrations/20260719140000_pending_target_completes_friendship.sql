-- ============================================================================
-- PENDING TARGET RESOLUTION — actually complete the connection on join
-- Created: 2026-07-19
-- ============================================================================
--
-- Fixes a gap in 20260719120000: when a pending X-handle target resolves in the
-- DELAYED case (the handle links for real, later), the prior hook only marked
-- the target resolved and sent a notification — it never created the friend
-- edge, so the whole promise ("add them now, we'll connect you when they join")
-- silently failed to complete. The eager case (handle already joined) works
-- because the client inserts the friendship inline; the delayed case has no
-- client online, so the completion MUST happen server-side, here.
--
-- By the time this runs, link_identity has already set the joiner's real
-- handle/full_name above, so the creator sees them by their real identity in
-- the friends list — no need to have stored the typed name. Symmetric two-row
-- insert matches exactly what addSupabaseFriend / UnifiedDatabaseService.addFriend
-- do inline; ON CONFLICT makes it idempotent against an already-existing edge.
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
  v_username_norm TEXT;
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

  -- Resolve any pending targets waiting on this exact handle: mark them
  -- resolved, CREATE the symmetric friend edge (the completion the eager path
  -- does inline but the delayed path previously skipped), and notify each
  -- creator. All in one statement so the data-modifying CTEs run exactly once.
  v_username_norm := lower(regexp_replace(trim(coalesce(p_provider_username, '')), '^@', ''));
  IF v_username_norm <> '' THEN
    WITH resolved AS (
      UPDATE public.pending_identity_targets
      SET resolved_wallet_address = trim(p_wallet), resolved_at = NOW()
      WHERE provider = v_provider
        AND provider_username = v_username_norm
        AND resolved_at IS NULL
      RETURNING network, created_by_wallet, provider_username
    ),
    -- The creator's user row (skip self-links and creators without a user row).
    creator_edges AS (
      SELECT DISTINCT cu.id AS creator_id
      FROM resolved r
      JOIN public.users cu ON cu.wallet_address = r.created_by_wallet
      WHERE cu.id <> v_user_id
    ),
    -- Symmetric friendship (both directions), idempotent against an existing edge.
    friend_ins AS (
      INSERT INTO public.friends (user_id, friend_id, status, created_at)
      SELECT creator_id, v_user_id, 'accepted', NOW() FROM creator_edges
      UNION ALL
      SELECT v_user_id, creator_id, 'accepted', NOW() FROM creator_edges
      ON CONFLICT (user_id, friend_id) DO NOTHING
      RETURNING 1
    )
    INSERT INTO public.notification_outbox (
      network, recipient_wallet_address, type, title, body, data
    )
    SELECT
      r.network,
      r.created_by_wallet,
      'PENDING_TARGET_RESOLVED',
      'Someone you added just joined ChumBucket',
      '@' || r.provider_username || ' is now on ChumBucket — you''re connected!',
      jsonb_build_object('resolvedWallet', trim(p_wallet), 'providerUsername', r.provider_username)
    FROM resolved r;
  END IF;

  RETURN jsonb_build_object('linkedIdentityId', v_id, 'userId', v_user_id, 'provider', v_provider);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Links a verified Google/X identity to a wallet user, enriches display fields, and resolves any pending_identity_targets waiting on this handle — completing the friendship (symmetric friends row) and notifying each creator. Backend-only.';
