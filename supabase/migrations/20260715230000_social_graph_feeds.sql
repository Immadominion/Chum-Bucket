-- ============================================================================
-- SOCIAL GRAPH + FEEDS  (the FOMO layer)
-- Version: 1.0
-- Created: 2026-07-15
-- ============================================================================
--
-- Turns the prediction read model into a social network: an asymmetric FOLLOW
-- graph (follow sharp callers you don't know — the FOMO "follow top traders"
-- primitive), a following feed that unions follows + the existing mutual
-- friends, per-fixture "who called what", and a record/PnL leaderboard.
--
-- Trust boundary: WRITE rpcs (follow/unfollow) are service-role only — the
-- backend calls them after verifying the follower's wallet SIGNATURE, so a
-- client can't spam the graph on someone else's behalf. READ rpcs return only
-- public data and are anon-callable.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  follower_wallet TEXT NOT NULL,
  followee_wallet TEXT NOT NULL,
  follower_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  followee_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT follows_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT follows_not_self CHECK (trim(follower_wallet) <> trim(followee_wallet)),
  CONSTRAINT follows_follower_not_empty CHECK (length(trim(follower_wallet)) > 0),
  CONSTRAINT follows_followee_not_empty CHECK (length(trim(followee_wallet)) > 0),
  UNIQUE (network, follower_wallet, followee_wallet)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON public.follows(network, follower_wallet);
CREATE INDEX IF NOT EXISTS idx_follows_followee ON public.follows(network, followee_wallet);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS follows_public_select ON public.follows;
CREATE POLICY follows_public_select ON public.follows FOR SELECT USING (true);

COMMENT ON TABLE public.follows IS 'Asymmetric follow graph for the social prediction feed (FOMO-style). Writes go through the backend after wallet-signature verification.';

-- ---------------------------------------------------------------------------
-- WRITES (service-role only; backend verifies the wallet signature first).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.follow_wallet(
  p_network TEXT,
  p_follower TEXT,
  p_followee TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_id UUID;
  v_follower_uid UUID;
  v_followee_uid UUID;
BEGIN
  IF trim(p_follower) = trim(p_followee) THEN
    RAISE EXCEPTION 'cannot follow self';
  END IF;
  -- Ensure the follower has a user row; resolve the followee if it exists.
  v_follower_uid := public.sync_user_by_wallet(p_follower);
  SELECT id INTO v_followee_uid FROM public.users WHERE wallet_address = trim(p_followee);

  INSERT INTO public.follows (network, follower_wallet, followee_wallet, follower_user_id, followee_user_id)
  VALUES (p_network, trim(p_follower), trim(p_followee), v_follower_uid, v_followee_uid)
  ON CONFLICT (network, follower_wallet, followee_wallet) DO UPDATE
  SET
    follower_user_id = COALESCE(EXCLUDED.follower_user_id, public.follows.follower_user_id),
    followee_user_id = COALESCE(EXCLUDED.followee_user_id, public.follows.followee_user_id)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'following', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.unfollow_wallet(
  p_network TEXT,
  p_follower TEXT,
  p_followee TEXT
)
RETURNS JSONB AS $$
BEGIN
  DELETE FROM public.follows
  WHERE network = p_network
    AND follower_wallet = trim(p_follower)
    AND followee_wallet = trim(p_followee);
  RETURN jsonb_build_object('following', false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ---------------------------------------------------------------------------
-- READS (anon-callable; return only public data).
-- ---------------------------------------------------------------------------

-- The following feed: public activity from wallets p_wallet follows, UNION the
-- activity of its accepted mutual friends. This is the FOMO home feed.
CREATE OR REPLACE FUNCTION public.feed_following(
  p_network TEXT,
  p_wallet TEXT,
  p_limit INTEGER DEFAULT 50
)
RETURNS SETOF public.prediction_activity AS $$
  SELECT a.*
  FROM public.prediction_activity a
  WHERE a.network = p_network
    AND a.visibility = 'public'
    AND (
      a.actor_wallet_address IN (
        SELECT followee_wallet FROM public.follows
        WHERE network = p_network AND follower_wallet = trim(p_wallet)
      )
      OR a.actor_user_id IN (
        SELECT f.friend_id
        FROM public.friends f
        JOIN public.users u ON u.id = f.user_id
        WHERE u.wallet_address = trim(p_wallet) AND f.status = 'accepted'
      )
    )
  ORDER BY a.created_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.follow_counts(
  p_network TEXT,
  p_wallet TEXT
)
RETURNS JSONB AS $$
  SELECT jsonb_build_object(
    'followers', (SELECT count(*) FROM public.follows WHERE network = p_network AND followee_wallet = trim(p_wallet)),
    'following', (SELECT count(*) FROM public.follows WHERE network = p_network AND follower_wallet = trim(p_wallet))
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Is p_viewer following p_target? (Powers the follow/unfollow button state.)
CREATE OR REPLACE FUNCTION public.is_following(
  p_network TEXT,
  p_viewer TEXT,
  p_target TEXT
)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.follows
    WHERE network = p_network AND follower_wallet = trim(p_viewer) AND followee_wallet = trim(p_target)
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Who called what on a fixture (the match "callers" board).
CREATE OR REPLACE FUNCTION public.match_callers(
  p_network TEXT,
  p_match_id TEXT,
  p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
  wallet_address TEXT,
  handle TEXT,
  bucket TEXT,
  stake_base_units NUMERIC,
  status TEXT,
  payout_base_units NUMERIC,
  placed_at TIMESTAMPTZ
) AS $$
  SELECT p.wallet_address, u.handle, p.bucket, p.stake_base_units, p.status, p.payout_base_units, p.placed_at
  FROM public.prediction_positions p
  LEFT JOIN public.users u ON u.id = p.user_id
  WHERE p.network = p_network AND p.match_id = p_match_id
  ORDER BY p.placed_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Record/PnL leaderboard from settled stats. p_by: 'pnl' | 'streak' | 'winrate'.
CREATE OR REPLACE FUNCTION public.social_leaderboard(
  p_by TEXT DEFAULT 'pnl',
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  wallet_address TEXT,
  handle TEXT,
  display_name TEXT,
  calls_made INTEGER,
  calls_won INTEGER,
  calls_lost INTEGER,
  calls_voided INTEGER,
  pnl_base_units NUMERIC,
  current_streak INTEGER,
  best_streak INTEGER,
  win_rate NUMERIC
) AS $$
  SELECT
    s.wallet_address,
    u.handle,
    u.full_name,
    s.calls_made,
    s.calls_won,
    s.calls_lost,
    s.calls_voided,
    s.pnl_base_units,
    s.current_streak,
    s.best_streak,
    CASE WHEN (s.calls_won + s.calls_lost) > 0
      THEN round(s.calls_won::numeric / (s.calls_won + s.calls_lost), 4)
      ELSE 0 END AS win_rate
  FROM public.user_stats s
  LEFT JOIN public.users u ON u.id = s.user_id
  WHERE s.calls_made > 0
  ORDER BY
    CASE WHEN p_by = 'streak'  THEN s.current_streak END DESC NULLS LAST,
    CASE WHEN p_by = 'winrate' THEN (CASE WHEN (s.calls_won + s.calls_lost) > 0 THEN s.calls_won::numeric / (s.calls_won + s.calls_lost) ELSE 0 END) END DESC NULLS LAST,
    CASE WHEN p_by NOT IN ('streak', 'winrate') THEN s.pnl_base_units END DESC NULLS LAST,
    s.calls_won DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ---------------------------------------------------------------------------
-- GRANTS: writes are backend-only (service role); reads return public data.
-- ---------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION
  public.follow_wallet(TEXT, TEXT, TEXT),
  public.unfollow_wallet(TEXT, TEXT, TEXT)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.follow_wallet(TEXT, TEXT, TEXT),
  public.unfollow_wallet(TEXT, TEXT, TEXT)
TO service_role;

COMMENT ON FUNCTION public.feed_following(TEXT, TEXT, INTEGER) IS 'FOMO home feed: public activity from followed wallets + accepted friends, newest first.';
COMMENT ON FUNCTION public.social_leaderboard(TEXT, INTEGER) IS 'Record/PnL leaderboard from settled user_stats. p_by = pnl | streak | winrate.';
