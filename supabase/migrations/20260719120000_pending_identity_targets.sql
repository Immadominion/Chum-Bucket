-- ============================================================================
-- PENDING IDENTITY TARGETS — follow an X handle who hasn't joined yet
-- Created: 2026-07-19
-- ============================================================================
--
-- Venmo's "send to a number that isn't registered yet" pattern, applied to the
-- social graph: a wallet can add an X handle as a pending target before that
-- person has ever touched ChumBucket. The handle is stored as an UNVERIFIED
-- LABEL ONLY — it becomes a real connection only once that exact handle is
-- later linked through the already-verified link_identity path (Supabase
-- Auth OAuth on mobile, Privy on web). No Twitter API access needed or used.
--
-- Flow: create_pending_target records the intent (rate-limited — this is a
-- real harassment/spam vector for an unverified-handle feature). If the
-- handle already belongs to a joined user, it resolves immediately. Otherwise
-- link_identity's resolution hook below catches it the moment that handle
-- ever links, and notifies whoever was waiting.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.pending_identity_targets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_username TEXT NOT NULL, -- normalized: lowercased, no leading '@'
  created_by_wallet TEXT NOT NULL,
  target_type TEXT NOT NULL DEFAULT 'follow' CHECK (target_type = 'follow'), -- scope: follow/friend-add only for this pass
  target_ref TEXT,
  resolved_wallet_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  CONSTRAINT pending_identity_targets_network_check CHECK (network IN ('devnet', 'mainnet-beta'))
);

-- One outstanding (unresolved) pending target per wallet+handle+network — adding
-- the same handle twice while it's still pending is a no-op, not a duplicate row.
CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_target_unresolved
ON public.pending_identity_targets (network, provider, provider_username, created_by_wallet)
WHERE resolved_at IS NULL;

-- The resolution hook's lookup path (by provider+username, across all creators).
CREATE INDEX IF NOT EXISTS idx_pending_target_lookup
ON public.pending_identity_targets (provider, provider_username)
WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pending_target_creator
ON public.pending_identity_targets (created_by_wallet, created_at DESC);

-- ---------------------------------------------------------------------------
-- Create a pending target. Rate-limited per wallet; resolves immediately if
-- the handle already belongs to a joined user instead of sitting pending
-- forever (the resolution hook below only fires on a NEW link_identity call).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_pending_target(
  p_network TEXT,
  p_wallet TEXT,
  p_provider TEXT,
  p_provider_username TEXT,
  p_target_type TEXT DEFAULT 'follow'
)
RETURNS JSONB AS $$
DECLARE
  v_provider TEXT := lower(coalesce(p_provider, ''));
  v_username TEXT := lower(regexp_replace(trim(coalesce(p_provider_username, '')), '^@', ''));
  v_wallet TEXT := trim(coalesce(p_wallet, ''));
  v_recent_count INTEGER;
  v_existing_user_id UUID;
  v_existing_wallet TEXT;
  v_id UUID;
BEGIN
  IF v_username = '' THEN
    RAISE EXCEPTION 'a handle is required';
  END IF;
  IF v_wallet = '' THEN
    RAISE EXCEPTION 'wallet address is required';
  END IF;
  -- Coerce X's various provider names into the allowed set (mirrors link_identity).
  IF v_provider IN ('x', 'x.com', 'twitter.com') THEN v_provider := 'twitter'; END IF;
  IF v_provider <> 'twitter' THEN
    RAISE EXCEPTION 'unsupported provider: %', p_provider;
  END IF;
  IF p_target_type <> 'follow' THEN
    RAISE EXCEPTION 'unsupported target type: %', p_target_type;
  END IF;

  -- Rate limit: at most 20 pending targets created per wallet per rolling hour.
  SELECT count(*) INTO v_recent_count
  FROM public.pending_identity_targets
  WHERE created_by_wallet = v_wallet AND created_at > NOW() - INTERVAL '1 hour';
  IF v_recent_count >= 20 THEN
    RAISE EXCEPTION 'too many pending targets created recently — try again later';
  END IF;

  -- Already joined? Resolve immediately rather than creating a target that
  -- would otherwise sit pending forever.
  SELECT li.user_id INTO v_existing_user_id
  FROM public.linked_identities li
  WHERE li.provider = v_provider AND lower(li.provider_username) = v_username
  LIMIT 1;
  IF v_existing_user_id IS NOT NULL THEN
    SELECT wallet_address INTO v_existing_wallet FROM public.users WHERE id = v_existing_user_id;
  END IF;

  INSERT INTO public.pending_identity_targets (
    network, provider, provider_username, created_by_wallet, target_type,
    resolved_wallet_address, resolved_at
  ) VALUES (
    p_network, v_provider, v_username, v_wallet, p_target_type,
    v_existing_wallet, CASE WHEN v_existing_wallet IS NOT NULL THEN NOW() ELSE NULL END
  )
  ON CONFLICT (network, provider, provider_username, created_by_wallet) WHERE resolved_at IS NULL
  DO UPDATE SET created_at = public.pending_identity_targets.created_at -- no-op; just return the existing row
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'resolvedWalletAddress', v_existing_wallet,
    'alreadyResolved', v_existing_wallet IS NOT NULL
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- Everything a wallet has added, resolved or not — for rendering "@handle ·
-- not joined yet" in the friends list. Read-only public display data (no
-- email/subject), same anon-readable posture as wallet_profiles.
CREATE OR REPLACE FUNCTION public.pending_targets_for_wallet(
  p_network TEXT,
  p_wallet TEXT,
  p_limit INTEGER DEFAULT 50
)
RETURNS SETOF public.pending_identity_targets AS $$
  SELECT *
  FROM public.pending_identity_targets
  WHERE network = p_network AND created_by_wallet = trim(p_wallet)
  ORDER BY created_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- create_pending_target is a WRITE => backend/service-role only (the backend
-- wallet-sig-authenticates the caller before invoking it, same as follow_wallet).
REVOKE EXECUTE ON FUNCTION public.create_pending_target(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_pending_target(TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON TABLE public.pending_identity_targets IS 'An unverified "follow this X handle once they join" intent — resolves via link_identity, never implies the target is aware or participating until they actually link.';
COMMENT ON FUNCTION public.create_pending_target(TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Rate-limited: creates (or resolves immediately if already joined) a pending follow target. Backend-only.';
COMMENT ON FUNCTION public.pending_targets_for_wallet(TEXT, TEXT, INTEGER) IS 'A wallet''s pending + resolved identity targets, newest first.';

-- ---------------------------------------------------------------------------
-- Resolution hook: the moment a handle that someone was waiting on actually
-- links, resolve every matching pending target and notify whoever added it.
-- Additive to link_identity's existing body — the identity-link itself stays
-- exactly as before; this only runs when the newly-linked handle has waiters.
-- ---------------------------------------------------------------------------

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

  -- Resolve any pending targets waiting on this exact handle, and notify
  -- whoever added them.
  v_username_norm := lower(regexp_replace(trim(coalesce(p_provider_username, '')), '^@', ''));
  IF v_username_norm <> '' THEN
    WITH resolved AS (
      UPDATE public.pending_identity_targets
      SET resolved_wallet_address = trim(p_wallet), resolved_at = NOW()
      WHERE provider = v_provider
        AND provider_username = v_username_norm
        AND resolved_at IS NULL
      RETURNING network, created_by_wallet, provider_username
    )
    INSERT INTO public.notification_outbox (
      network, recipient_wallet_address, type, title, body, data
    )
    SELECT
      r.network,
      r.created_by_wallet,
      'PENDING_TARGET_RESOLVED',
      'Someone you added just joined ChumBucket',
      '@' || r.provider_username || ' is now on ChumBucket — say hi!',
      jsonb_build_object('resolvedWallet', trim(p_wallet), 'providerUsername', r.provider_username)
    FROM resolved r;
  END IF;

  RETURN jsonb_build_object('linkedIdentityId', v_id, 'userId', v_user_id, 'provider', v_provider);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

REVOKE EXECUTE ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION public.link_identity(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) IS 'Links a verified Google/X identity to a wallet user, enriches display fields, and resolves any pending_identity_targets waiting on this handle. Backend-only.';
