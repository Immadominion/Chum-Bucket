-- ============================================================================
-- TRUTH — a client can no longer forge a VERIFIED call in the public feed
-- Created: 2026-07-19
-- ============================================================================
--
-- record_prediction_call is the OPTIMISTIC mirror the client calls right after
-- submitting its on-chain place_call. It previously set the public-feed
-- CALL_PLACED activity to status='VERIFIED' whenever the client passed a
-- non-null slot — but slot / tx_signature are client-supplied and never checked
-- against the chain here, so anyone owning a wallet could POST a fabricated call
-- with a made-up signature + slot and have it display as VERIFIED ("smart money")
-- in everyone's feed.
--
-- Fix: the optimistic mirror now ALWAYS records the activity as PENDING. The
-- ONLY path to VERIFIED is confirm_prediction_signature (service-role, driven by
-- the Helius webhook + reconciler from real observed chain events) — i.e.
-- VERIFIED now means "seen on chain", never "the client claimed so". A real
-- call still flips to VERIFIED within seconds when Helius confirms its signature.
--
-- Money truth was never affected (settled/won/claimable come only from
-- apply_settlement, chain-driven); this closes the FEED-badge trust hole only.
-- Position status (PENDING/OPEN) is intentionally left as-is: a fake OPEN
-- position is inert (settlement matches real on-chain Pot state, so it can never
-- win), and only its own author ever sees it.
--
-- Body is verbatim from 20260715134226 (confirmed to match the live definition)
-- with exactly two lines changed — the two marked below.
-- ============================================================================

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
    'PENDING',  -- CHANGED: optimistic mirror is always PENDING; VERIFIED only via confirm_prediction_signature (chain evidence)
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
    status = public.prediction_activity.status,  -- CHANGED: never let the optimistic re-submit force VERIFIED; keep whatever confirm/reconciler set
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

-- Re-assert: this is a WRITE, backend/service-role only (the tRPC layer
-- wallet-sig-authenticates the caller first). CREATE OR REPLACE preserves ACLs,
-- but state it explicitly so the posture can't silently regress.
REVOKE EXECUTE ON FUNCTION public.record_prediction_call(TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, BIGINT, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_prediction_call(TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, BIGINT, JSONB) TO service_role;
