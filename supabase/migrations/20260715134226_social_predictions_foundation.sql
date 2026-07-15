-- ============================================================================
-- CHUMBUCKET SOCIAL PREDICTIONS FOUNDATION
-- Version: 1.0 - Production social identity + canonical activity read models
-- Created: 2026-07-15
-- ============================================================================
--
-- Goal:
--   Chumbucket is wallet-authorized through MWA, but socially identified through
--   linked identities such as Google and X. Prediction calls/challenges must be
--   durable server-side activity, not local device history.
--
-- Source of truth split:
--   - MWA wallet signatures prove wallet ownership and sign value-moving txs.
--   - On-chain programs remain the money/escrow source of truth.
--   - TxLINE remains the sports-result/proof source of truth.
--   - Supabase/Postgres is the social read model and activity feed.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- USERS: tolerate the newer Flutter MWA sync call that passes an SNS/display
-- domain without breaking older one-arg callers.
-- ---------------------------------------------------------------------------

ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS sns_domain TEXT,
ADD COLUMN IF NOT EXISTS handle TEXT,
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_sns_domain ON public.users(sns_domain);
CREATE INDEX IF NOT EXISTS idx_users_handle ON public.users(handle);

-- ---------------------------------------------------------------------------
-- IDENTITY: reusable account graph for Chumbucket + future apps.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.linked_wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  wallet_address TEXT NOT NULL UNIQUE,
  wallet_type TEXT NOT NULL DEFAULT 'mwa',
  is_primary BOOLEAN NOT NULL DEFAULT false,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_signed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT linked_wallets_wallet_type_check CHECK (wallet_type IN ('mwa', 'embedded', 'imported')),
  CONSTRAINT linked_wallets_wallet_address_not_empty CHECK (length(trim(wallet_address)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_linked_wallets_user_id ON public.linked_wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_linked_wallets_primary ON public.linked_wallets(user_id, is_primary);

CREATE TABLE IF NOT EXISTS public.linked_identities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  provider_subject TEXT NOT NULL,
  provider_username TEXT,
  provider_display_name TEXT,
  provider_avatar_url TEXT,
  provider_email TEXT,
  verified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT linked_identities_provider_check CHECK (provider IN ('google', 'x', 'twitter', 'apple', 'email', 'wallet')),
  CONSTRAINT linked_identities_provider_subject_not_empty CHECK (length(trim(provider_subject)) > 0),
  UNIQUE(provider, provider_subject)
);

CREATE INDEX IF NOT EXISTS idx_linked_identities_user_id ON public.linked_identities(user_id);
CREATE INDEX IF NOT EXISTS idx_linked_identities_provider ON public.linked_identities(provider);

-- Drop every pre-existing overload before recreating: the live DB historically
-- carried sync_user_by_wallet(TEXT) RETURNS VOID (001/002) and was later hand-
-- patched in the SQL editor to sync_user_by_wallet(TEXT, TEXT) RETURNS VOID so the
-- app could pass p_sns_domain. CREATE OR REPLACE cannot change a return type, so we
-- must DROP both signatures first. The app calls this via .rpc() and ignores the
-- return value, so promoting VOID -> UUID is safe.
DROP FUNCTION IF EXISTS public.sync_user_by_wallet(TEXT);
DROP FUNCTION IF EXISTS public.sync_user_by_wallet(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.sync_user_by_wallet(
  p_wallet_address TEXT,
  p_sns_domain TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_user_id UUID;
BEGIN
  IF p_wallet_address IS NULL OR length(trim(p_wallet_address)) = 0 THEN
    RAISE EXCEPTION 'wallet address is required';
  END IF;

  SELECT id INTO v_user_id
  FROM public.users
  WHERE wallet_address = trim(p_wallet_address);

  IF v_user_id IS NULL THEN
    INSERT INTO public.users (
      wallet_address,
      sns_domain,
      full_name,
      handle,
      created_at,
      updated_at,
      last_seen_at
    ) VALUES (
      trim(p_wallet_address),
      NULLIF(trim(COALESCE(p_sns_domain, '')), ''),
      NULLIF(trim(COALESCE(p_sns_domain, '')), ''),
      NULLIF(trim(COALESCE(p_sns_domain, '')), ''),
      NOW(),
      NOW(),
      NOW()
    )
    RETURNING id INTO v_user_id;
  ELSE
    UPDATE public.users
    SET
      sns_domain = COALESCE(NULLIF(trim(COALESCE(p_sns_domain, '')), ''), sns_domain),
      full_name = COALESCE(full_name, NULLIF(trim(COALESCE(p_sns_domain, '')), '')),
      handle = COALESCE(handle, NULLIF(trim(COALESCE(p_sns_domain, '')), '')),
      updated_at = NOW(),
      last_seen_at = NOW()
    WHERE id = v_user_id;
  END IF;

  INSERT INTO public.linked_wallets (
    user_id,
    wallet_address,
    wallet_type,
    is_primary,
    first_seen_at,
    last_signed_at
  ) VALUES (
    v_user_id,
    trim(p_wallet_address),
    'mwa',
    true,
    NOW(),
    NOW()
  )
  ON CONFLICT (wallet_address) DO UPDATE
  SET
    user_id = EXCLUDED.user_id,
    last_signed_at = NOW(),
    is_primary = public.linked_wallets.is_primary OR EXCLUDED.is_primary,
    updated_at = NOW();

  RETURN v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.sync_user_by_wallet(TEXT, TEXT) IS
'Gets or creates a wallet-based Chumbucket user and records the MWA wallet link. Optional p_sns_domain is display metadata.';

-- Backfill wallet links for existing wallet-based users.
INSERT INTO public.linked_wallets (user_id, wallet_address, wallet_type, is_primary, first_seen_at, last_signed_at)
SELECT id, wallet_address, 'mwa', true, COALESCE(created_at, NOW()), COALESCE(last_seen_at, updated_at, NOW())
FROM public.users
WHERE wallet_address IS NOT NULL
  AND length(trim(wallet_address)) > 0
ON CONFLICT (wallet_address) DO NOTHING;

-- ---------------------------------------------------------------------------
-- MARKETS AND POSITIONS: query-friendly read models for Arena + challenges.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.prediction_markets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  market_id TEXT NOT NULL,
  match_id TEXT NOT NULL,
  market_kind TEXT NOT NULL DEFAULT 'RESULT',
  title TEXT NOT NULL,
  competition TEXT,
  stage TEXT,
  home TEXT,
  away TEXT,
  kickoff_at TIMESTAMPTZ,
  txline_fixture_id BIGINT,
  status TEXT NOT NULL DEFAULT 'OPEN',
  winning_bucket TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  opened_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT prediction_markets_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT prediction_markets_status_check CHECK (status IN ('OPEN', 'LOCKED', 'RESOLVED', 'VOIDED')),
  UNIQUE(network, market_id)
);

CREATE INDEX IF NOT EXISTS idx_prediction_markets_match_id ON public.prediction_markets(network, match_id);
CREATE INDEX IF NOT EXISTS idx_prediction_markets_status ON public.prediction_markets(network, status, kickoff_at);
CREATE INDEX IF NOT EXISTS idx_prediction_markets_txline ON public.prediction_markets(txline_fixture_id);

CREATE TABLE IF NOT EXISTS public.prediction_positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  wallet_address TEXT NOT NULL,
  market_id TEXT NOT NULL,
  match_id TEXT NOT NULL,
  position_address TEXT,
  bucket TEXT NOT NULL,
  stake_base_units NUMERIC(30, 0) NOT NULL,
  stake_decimals INTEGER NOT NULL DEFAULT 6,
  open_tx_signature TEXT NOT NULL,
  open_slot BIGINT,
  status TEXT NOT NULL DEFAULT 'PENDING',
  payout_base_units NUMERIC(30, 0),
  pnl_base_units NUMERIC(30, 0),
  settlement_tx_signature TEXT,
  claim_tx_signature TEXT,
  claimed_at TIMESTAMPTZ,
  placed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  settled_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT prediction_positions_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT prediction_positions_status_check CHECK (status IN ('PENDING', 'OPEN', 'WON', 'LOST', 'VOIDED', 'CLAIMABLE', 'CLAIMED', 'FAILED')),
  UNIQUE(network, open_tx_signature)
);

CREATE INDEX IF NOT EXISTS idx_prediction_positions_wallet ON public.prediction_positions(network, wallet_address, placed_at DESC);
CREATE INDEX IF NOT EXISTS idx_prediction_positions_market ON public.prediction_positions(network, market_id);
CREATE INDEX IF NOT EXISTS idx_prediction_positions_match ON public.prediction_positions(network, match_id);
CREATE INDEX IF NOT EXISTS idx_prediction_positions_status ON public.prediction_positions(network, status);

-- ---------------------------------------------------------------------------
-- ACTIVITY: the social feed source of truth.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.prediction_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  actor_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  actor_wallet_address TEXT NOT NULL,
  type TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'public',
  market_id TEXT,
  match_id TEXT,
  position_id UUID REFERENCES public.prediction_positions(id) ON DELETE SET NULL,
  challenge_id TEXT,
  bucket TEXT,
  stake_base_units NUMERIC(30, 0),
  tx_signature TEXT,
  slot BIGINT,
  status TEXT NOT NULL DEFAULT 'PENDING',
  title TEXT,
  body TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT prediction_activity_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT prediction_activity_visibility_check CHECK (visibility IN ('public', 'friends', 'private')),
  CONSTRAINT prediction_activity_type_check CHECK (
    type IN (
      'CALL_PLACED',
      'CALL_COPIED',
      'CHALLENGE_CREATED',
      'CHALLENGE_ACCEPTED',
      'MATCH_LOCKED',
      'CALL_SETTLED',
      'CHALLENGE_SETTLED',
      'CLAIM_AVAILABLE',
      'CLAIMED',
      'FRIEND_JOINED'
    )
  ),
  CONSTRAINT prediction_activity_status_check CHECK (status IN ('PENDING', 'VERIFIED', 'SETTLED', 'FAILED')),
  UNIQUE(network, tx_signature, type)
);

CREATE INDEX IF NOT EXISTS idx_prediction_activity_feed ON public.prediction_activity(network, visibility, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prediction_activity_actor ON public.prediction_activity(network, actor_wallet_address, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prediction_activity_match ON public.prediction_activity(network, match_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_prediction_activity_type ON public.prediction_activity(network, type, created_at DESC);

CREATE TABLE IF NOT EXISTS public.settlement_receipts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  market_id TEXT NOT NULL,
  match_id TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'txline',
  winning_bucket TEXT,
  score_home INTEGER,
  score_away INTEGER,
  settlement_tx_signature TEXT,
  txline_fixture_id BIGINT,
  txline_seq BIGINT,
  proof_ref TEXT,
  proof JSONB,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT settlement_receipts_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  UNIQUE(network, market_id, source)
);

CREATE INDEX IF NOT EXISTS idx_settlement_receipts_match ON public.settlement_receipts(network, match_id);
CREATE INDEX IF NOT EXISTS idx_settlement_receipts_txline ON public.settlement_receipts(txline_fixture_id, txline_seq);

CREATE TABLE IF NOT EXISTS public.claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  wallet_address TEXT NOT NULL,
  position_id UUID REFERENCES public.prediction_positions(id) ON DELETE SET NULL,
  claim_tx_signature TEXT NOT NULL,
  amount_base_units NUMERIC(30, 0),
  status TEXT NOT NULL DEFAULT 'PENDING',
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT claims_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT claims_status_check CHECK (status IN ('PENDING', 'CONFIRMED', 'FAILED')),
  UNIQUE(network, claim_tx_signature)
);

CREATE INDEX IF NOT EXISTS idx_claims_wallet ON public.claims(network, wallet_address, created_at DESC);

CREATE TABLE IF NOT EXISTS public.user_stats (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  wallet_address TEXT,
  calls_made INTEGER NOT NULL DEFAULT 0,
  calls_won INTEGER NOT NULL DEFAULT 0,
  calls_lost INTEGER NOT NULL DEFAULT 0,
  calls_voided INTEGER NOT NULL DEFAULT 0,
  challenges_created INTEGER NOT NULL DEFAULT 0,
  challenges_won INTEGER NOT NULL DEFAULT 0,
  challenges_lost INTEGER NOT NULL DEFAULT 0,
  stake_base_units NUMERIC(30, 0) NOT NULL DEFAULT 0,
  pnl_base_units NUMERIC(30, 0) NOT NULL DEFAULT 0,
  current_streak INTEGER NOT NULL DEFAULT 0,
  best_streak INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_stats_wallet ON public.user_stats(wallet_address);
CREATE INDEX IF NOT EXISTS idx_user_stats_pnl ON public.user_stats(pnl_base_units DESC);

CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  recipient_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  recipient_wallet_address TEXT,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT notification_outbox_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT notification_outbox_status_check CHECK (status IN ('pending', 'sent', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_notification_outbox_pending
ON public.notification_outbox(status, next_attempt_at)
WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS public.indexer_cursors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  source TEXT NOT NULL,
  cursor_key TEXT NOT NULL,
  last_signature TEXT,
  last_slot BIGINT,
  last_seen_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT indexer_cursors_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  UNIQUE(network, source, cursor_key)
);

CREATE TABLE IF NOT EXISTS public.indexer_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  network TEXT NOT NULL DEFAULT 'devnet',
  source TEXT NOT NULL,
  signature TEXT NOT NULL,
  slot BIGINT,
  event_type TEXT NOT NULL DEFAULT 'transaction',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT indexer_events_network_check CHECK (network IN ('devnet', 'mainnet-beta')),
  UNIQUE(network, source, signature, event_type)
);

CREATE INDEX IF NOT EXISTS idx_indexer_events_signature
ON public.indexer_events(network, signature);

-- ---------------------------------------------------------------------------
-- WRITE HELPERS: backend/indexer can call these through PostgREST RPC.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_prediction_call(
  p_network TEXT,
  p_wallet_address TEXT,
  p_match_id TEXT,
  p_market_id TEXT,
  p_bucket TEXT,
  p_stake_base_units NUMERIC,
  p_tx_signature TEXT,
  p_position_address TEXT DEFAULT NULL,
  p_slot BIGINT DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID AS $$
DECLARE
  v_user_id UUID;
  v_position_id UUID;
  v_existing_position_id UUID;
BEGIN
  IF p_tx_signature IS NULL OR length(trim(p_tx_signature)) = 0 THEN
    RAISE EXCEPTION 'tx signature is required';
  END IF;

  v_user_id := public.sync_user_by_wallet(p_wallet_address);

  SELECT id INTO v_existing_position_id
  FROM public.prediction_positions
  WHERE network = p_network
    AND open_tx_signature = trim(p_tx_signature);

  IF v_existing_position_id IS NULL THEN
    INSERT INTO public.prediction_positions (
      network,
      user_id,
      wallet_address,
      market_id,
      match_id,
      position_address,
      bucket,
      stake_base_units,
      open_tx_signature,
      open_slot,
      status,
      metadata
    ) VALUES (
      p_network,
      v_user_id,
      trim(p_wallet_address),
      p_market_id,
      p_match_id,
      p_position_address,
      upper(p_bucket),
      p_stake_base_units,
      trim(p_tx_signature),
      p_slot,
      CASE WHEN p_slot IS NULL THEN 'PENDING' ELSE 'OPEN' END,
      COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id INTO v_position_id;
  ELSE
    UPDATE public.prediction_positions
    SET
      user_id = v_user_id,
      wallet_address = trim(p_wallet_address),
      market_id = p_market_id,
      match_id = p_match_id,
      position_address = COALESCE(p_position_address, position_address),
      bucket = upper(p_bucket),
      stake_base_units = p_stake_base_units,
      open_slot = COALESCE(p_slot, open_slot),
      status = CASE WHEN p_slot IS NULL THEN status ELSE 'OPEN' END,
      metadata = metadata || COALESCE(p_metadata, '{}'::jsonb),
      updated_at = NOW()
    WHERE id = v_existing_position_id
    RETURNING id INTO v_position_id;
  END IF;

  INSERT INTO public.prediction_activity (
    network,
    actor_user_id,
    actor_wallet_address,
    type,
    visibility,
    market_id,
    match_id,
    position_id,
    bucket,
    stake_base_units,
    tx_signature,
    slot,
    status,
    title,
    body,
    metadata
  ) VALUES (
    p_network,
    v_user_id,
    trim(p_wallet_address),
    'CALL_PLACED',
    'public',
    p_market_id,
    p_match_id,
    v_position_id,
    upper(p_bucket),
    p_stake_base_units,
    trim(p_tx_signature),
    p_slot,
    CASE WHEN p_slot IS NULL THEN 'PENDING' ELSE 'VERIFIED' END,
    'Call placed',
    upper(p_bucket),
    COALESCE(p_metadata, '{}'::jsonb)
  )
  ON CONFLICT (network, tx_signature, type) DO UPDATE
  SET
    actor_user_id = EXCLUDED.actor_user_id,
    actor_wallet_address = EXCLUDED.actor_wallet_address,
    position_id = EXCLUDED.position_id,
    slot = COALESCE(EXCLUDED.slot, public.prediction_activity.slot),
    status = CASE WHEN EXCLUDED.slot IS NULL THEN public.prediction_activity.status ELSE 'VERIFIED' END,
    metadata = public.prediction_activity.metadata || EXCLUDED.metadata,
    updated_at = NOW();

  IF v_existing_position_id IS NULL THEN
    INSERT INTO public.user_stats (user_id, wallet_address, calls_made, stake_base_units, updated_at)
    VALUES (v_user_id, trim(p_wallet_address), 1, p_stake_base_units, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET
      wallet_address = EXCLUDED.wallet_address,
      calls_made = public.user_stats.calls_made + 1,
      stake_base_units = public.user_stats.stake_base_units + EXCLUDED.stake_base_units,
      updated_at = NOW();
  END IF;

  RETURN v_position_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.record_prediction_call(TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, BIGINT, JSONB) IS
'Idempotently records a user call after MWA returns a transaction signature. Backend/indexer later verifies slot/account data.';

CREATE OR REPLACE FUNCTION public.confirm_prediction_signature(
  p_network TEXT,
  p_source TEXT,
  p_tx_signature TEXT,
  p_slot BIGINT DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB AS $$
DECLARE
  v_position_count INTEGER := 0;
  v_activity_count INTEGER := 0;
BEGIN
  IF p_tx_signature IS NULL OR length(trim(p_tx_signature)) = 0 THEN
    RAISE EXCEPTION 'tx signature is required';
  END IF;

  INSERT INTO public.indexer_events (
    network,
    source,
    signature,
    slot,
    event_type,
    payload,
    processed_at
  ) VALUES (
    p_network,
    p_source,
    trim(p_tx_signature),
    p_slot,
    'transaction_confirmed',
    COALESCE(p_payload, '{}'::jsonb),
    NOW()
  )
  ON CONFLICT (network, source, signature, event_type) DO UPDATE
  SET
    slot = COALESCE(EXCLUDED.slot, public.indexer_events.slot),
    payload = public.indexer_events.payload || EXCLUDED.payload,
    processed_at = NOW();

  UPDATE public.prediction_positions
  SET
    open_slot = COALESCE(p_slot, open_slot),
    status = CASE
      WHEN status = 'PENDING' THEN 'OPEN'
      ELSE status
    END,
    metadata = metadata || jsonb_build_object(
      'lastIndexerSource', p_source,
      'lastIndexerSeenAt', NOW()
    ),
    updated_at = NOW()
  WHERE network = p_network
    AND open_tx_signature = trim(p_tx_signature);

  GET DIAGNOSTICS v_position_count = ROW_COUNT;

  UPDATE public.prediction_activity
  SET
    slot = COALESCE(p_slot, slot),
    status = CASE
      WHEN status = 'PENDING' THEN 'VERIFIED'
      ELSE status
    END,
    metadata = metadata || jsonb_build_object(
      'lastIndexerSource', p_source,
      'lastIndexerSeenAt', NOW()
    ),
    updated_at = NOW()
  WHERE network = p_network
    AND tx_signature = trim(p_tx_signature)
    AND type = 'CALL_PLACED';

  GET DIAGNOSTICS v_activity_count = ROW_COUNT;

  INSERT INTO public.indexer_cursors (
    network,
    source,
    cursor_key,
    last_signature,
    last_slot,
    last_seen_at
  ) VALUES (
    p_network,
    p_source,
    'latest',
    trim(p_tx_signature),
    p_slot,
    NOW()
  )
  ON CONFLICT (network, source, cursor_key) DO UPDATE
  SET
    last_signature = EXCLUDED.last_signature,
    last_slot = COALESCE(EXCLUDED.last_slot, public.indexer_cursors.last_slot),
    last_seen_at = NOW(),
    updated_at = NOW();

  RETURN jsonb_build_object(
    'signature', trim(p_tx_signature),
    'positionsUpdated', v_position_count,
    'activityUpdated', v_activity_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.confirm_prediction_signature(TEXT, TEXT, TEXT, BIGINT, JSONB) IS
'Idempotently records an indexer/webhook sighting and upgrades matching pending call activity by transaction signature.';

-- ---------------------------------------------------------------------------
-- RLS: backend service role writes; clients can read public social data.
-- ---------------------------------------------------------------------------

ALTER TABLE public.linked_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.linked_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prediction_markets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prediction_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prediction_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlement_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.indexer_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.indexer_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS linked_wallets_public_select ON public.linked_wallets;
CREATE POLICY linked_wallets_public_select ON public.linked_wallets
FOR SELECT USING (true);

DROP POLICY IF EXISTS linked_identities_public_select ON public.linked_identities;
CREATE POLICY linked_identities_public_select ON public.linked_identities
FOR SELECT USING (provider IN ('x', 'twitter', 'wallet'));

DROP POLICY IF EXISTS prediction_markets_public_select ON public.prediction_markets;
CREATE POLICY prediction_markets_public_select ON public.prediction_markets
FOR SELECT USING (true);

DROP POLICY IF EXISTS prediction_positions_public_select ON public.prediction_positions;
CREATE POLICY prediction_positions_public_select ON public.prediction_positions
FOR SELECT USING (true);

DROP POLICY IF EXISTS prediction_activity_public_select ON public.prediction_activity;
CREATE POLICY prediction_activity_public_select ON public.prediction_activity
FOR SELECT USING (visibility = 'public');

DROP POLICY IF EXISTS settlement_receipts_public_select ON public.settlement_receipts;
CREATE POLICY settlement_receipts_public_select ON public.settlement_receipts
FOR SELECT USING (true);

DROP POLICY IF EXISTS claims_public_select ON public.claims;
CREATE POLICY claims_public_select ON public.claims
FOR SELECT USING (true);

DROP POLICY IF EXISTS user_stats_public_select ON public.user_stats;
CREATE POLICY user_stats_public_select ON public.user_stats
FOR SELECT USING (true);

-- Outbox and cursors are backend-only; service role bypasses RLS.

-- ---------------------------------------------------------------------------
-- COMMENTS
-- ---------------------------------------------------------------------------

COMMENT ON TABLE public.linked_wallets IS 'Wallet links for reusable identity. MWA wallets prove transaction authority.';
COMMENT ON TABLE public.linked_identities IS 'Social/OAuth identities linked to a Chumbucket user: Google, X, Apple, email, wallet.';
COMMENT ON TABLE public.prediction_markets IS 'Query-friendly market/fixture read model for social prediction feeds.';
COMMENT ON TABLE public.prediction_positions IS 'Server-indexed user prediction positions, reconciled from on-chain transactions.';
COMMENT ON TABLE public.prediction_activity IS 'Canonical social feed: calls, challenges, settlements, claims, friend joins.';
COMMENT ON TABLE public.settlement_receipts IS 'TxLINE/on-chain proof receipts for settled markets.';
COMMENT ON TABLE public.notification_outbox IS 'Durable notification jobs derived from activity/settlement events.';
COMMENT ON TABLE public.indexer_cursors IS 'Backfill/realtime cursor state for Solana and TxLINE indexers.';
COMMENT ON TABLE public.indexer_events IS 'Idempotent raw transaction sightings from webhooks/backfills.';
