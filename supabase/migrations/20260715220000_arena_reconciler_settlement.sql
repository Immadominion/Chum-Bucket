-- ============================================================================
-- ARENA RECONCILER + SETTLEMENT PIPELINE
-- Version: 1.0
-- Created: 2026-07-15
-- ============================================================================
--
-- Adds the write helpers the on-chain reconciler needs so that positions,
-- settlements, claims, stats, notifications, and the activity feed are all
-- driven by ON-CHAIN truth (the chumbucket_arena program) rather than by the
-- mobile app mirroring signatures.
--
-- Every function is idempotent:
--   - settlement transitions are gated on status IN ('PENDING','OPEN'), so a
--     re-run (or a chain reorg replaying the same settle tx) settles nothing new
--     and never double-counts stats or re-emits notifications;
--   - receipts/claims/activity upsert on their unique keys;
--   - the cursor is a monotonic bookmark.
--
-- Payout math mirrors the on-chain parimutuel claim exactly:
--   winner payout = stake + floor(distributable * stake / winners_stake)
--   loser  payout = 0
--   void   payout = stake                       (winners_stake = 0 => refund all)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- advance_indexer_cursor — monotonic resume bookmark for a poll source.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.advance_indexer_cursor(
  p_network TEXT,
  p_source TEXT,
  p_cursor_key TEXT,
  p_signature TEXT,
  p_slot BIGINT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO public.indexer_cursors (network, source, cursor_key, last_signature, last_slot, last_seen_at)
  VALUES (p_network, p_source, p_cursor_key, p_signature, p_slot, NOW())
  ON CONFLICT (network, source, cursor_key) DO UPDATE
  SET
    last_signature = EXCLUDED.last_signature,
    last_slot = COALESCE(EXCLUDED.last_slot, public.indexer_cursors.last_slot),
    last_seen_at = NOW(),
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.advance_indexer_cursor(TEXT, TEXT, TEXT, TEXT, BIGINT) IS
'Upserts a poll cursor (last processed signature/slot) for a given source+key.';

-- ---------------------------------------------------------------------------
-- apply_settlement — settle every open position for a market from on-chain
-- Pot state (winning bucket + parimutuel distributable/winners_stake), write
-- the settlement receipt + market-level activity, bump stats, and queue
-- claim-available notifications for winners. Idempotent.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_settlement(
  p_network TEXT,
  p_market_id TEXT,
  p_match_id TEXT,
  p_winning_bucket TEXT,           -- 'HOME' | 'DRAW' | 'AWAY'
  p_settle_tx TEXT,
  p_slot BIGINT DEFAULT NULL,
  p_distributable NUMERIC DEFAULT 0,
  p_winners_stake NUMERIC DEFAULT 0,
  p_score_home INTEGER DEFAULT NULL,
  p_score_away INTEGER DEFAULT NULL,
  p_fixture_id BIGINT DEFAULT NULL,
  p_seq BIGINT DEFAULT NULL,
  p_proof_ref TEXT DEFAULT NULL,
  p_proof JSONB DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_win   TEXT    := upper(COALESCE(p_winning_bucket, ''));
  v_void  BOOLEAN := COALESCE(p_winners_stake, 0) = 0;
  -- On a thin-pool void the on-chain Pot keeps winning_bucket = 0 (HOME) as
  -- garbage — never record that as the "winner". Void => NULL winning bucket.
  v_win_stored TEXT := CASE WHEN COALESCE(p_winners_stake, 0) = 0 THEN NULL ELSE upper(COALESCE(p_winning_bucket, '')) END;
  v_market_status TEXT := CASE WHEN COALESCE(p_winners_stake, 0) = 0 THEN 'VOIDED' ELSE 'RESOLVED' END;
  v_receipt_id UUID;
  v_settled INTEGER := 0;
  v_winners INTEGER := 0;
BEGIN
  IF p_settle_tx IS NULL OR length(trim(p_settle_tx)) = 0 THEN
    RAISE EXCEPTION 'settle tx signature is required';
  END IF;

  -- 1. Settlement receipt (one per market+source; the verifiable "receipt").
  INSERT INTO public.settlement_receipts (
    network, market_id, match_id, source, winning_bucket,
    score_home, score_away, settlement_tx_signature,
    txline_fixture_id, txline_seq, proof_ref, proof, verified_at
  ) VALUES (
    p_network, p_market_id, p_match_id, 'onchain', v_win_stored,
    p_score_home, p_score_away, trim(p_settle_tx),
    p_fixture_id, p_seq, COALESCE(p_proof_ref, trim(p_settle_tx)), p_proof, NOW()
  )
  ON CONFLICT (network, market_id, source) DO UPDATE
  SET
    winning_bucket = EXCLUDED.winning_bucket,
    score_home = COALESCE(EXCLUDED.score_home, public.settlement_receipts.score_home),
    score_away = COALESCE(EXCLUDED.score_away, public.settlement_receipts.score_away),
    settlement_tx_signature = EXCLUDED.settlement_tx_signature,
    txline_fixture_id = COALESCE(EXCLUDED.txline_fixture_id, public.settlement_receipts.txline_fixture_id),
    txline_seq = COALESCE(EXCLUDED.txline_seq, public.settlement_receipts.txline_seq),
    proof_ref = COALESCE(EXCLUDED.proof_ref, public.settlement_receipts.proof_ref),
    proof = COALESCE(EXCLUDED.proof, public.settlement_receipts.proof),
    verified_at = NOW()
  RETURNING id INTO v_receipt_id;

  -- 2. Mark the market resolved (upsert so a chain-only market still records).
  INSERT INTO public.prediction_markets (
    network, market_id, match_id, title, status, winning_bucket, txline_fixture_id, resolved_at
  ) VALUES (
    p_network, p_market_id, p_match_id, p_match_id, v_market_status, v_win_stored, p_fixture_id, NOW()
  )
  ON CONFLICT (network, market_id) DO UPDATE
  SET
    status = v_market_status,
    winning_bucket = v_win_stored,
    txline_fixture_id = COALESCE(EXCLUDED.txline_fixture_id, public.prediction_markets.txline_fixture_id),
    resolved_at = NOW(),
    updated_at = NOW();

  -- 3. Transition open/pending positions to their outcome, bump per-user stats,
  --    and queue claim-available notifications — all from the ONE batch of
  --    positions that actually transitioned (gated on PENDING/OPEN => idempotent).
  WITH transitioned AS (
    UPDATE public.prediction_positions p
    SET
      status = CASE
        WHEN v_void THEN 'CLAIMABLE'             -- refund is claimable
        WHEN p.bucket = v_win THEN 'CLAIMABLE'   -- winner claims payout
        ELSE 'LOST'
      END,
      payout_base_units = CASE
        WHEN v_void THEN p.stake_base_units
        WHEN p.bucket = v_win THEN p.stake_base_units + div(p_distributable * p.stake_base_units, NULLIF(p_winners_stake, 0))
        ELSE 0
      END,
      pnl_base_units = CASE
        WHEN v_void THEN 0
        WHEN p.bucket = v_win THEN div(p_distributable * p.stake_base_units, NULLIF(p_winners_stake, 0))
        ELSE -p.stake_base_units
      END,
      settlement_tx_signature = trim(p_settle_tx),
      settled_at = NOW(),
      updated_at = NOW()
    WHERE p.network = p_network
      AND p.match_id = p_match_id
      -- Filter by fixture (match_id) only. A fixture has exactly one RESULT market,
      -- and a mobile-mirrored position may still carry market_id='RESULT' until the
      -- reconciler repairs it to the fixture id — settle it regardless (finding [7]).
      AND p.status IN ('PENDING', 'OPEN')
    RETURNING p.id, p.user_id, p.wallet_address, p.status AS new_status, p.payout_base_units, p.pnl_base_units
  ),
  stats AS (
    INSERT INTO public.user_stats (user_id, wallet_address, calls_won, calls_lost, calls_voided, pnl_base_units, current_streak, best_streak, updated_at)
    SELECT
      t.user_id,
      max(t.wallet_address),
      count(*) FILTER (WHERE t.new_status = 'CLAIMABLE' AND NOT v_void),
      count(*) FILTER (WHERE t.new_status = 'LOST'),
      count(*) FILTER (WHERE v_void),
      COALESCE(sum(t.pnl_base_units), 0),
      -- seed streak correctly on the INSERT path too (row usually pre-exists via
      -- record_prediction_call, but don't depend on it): a loss in the batch zeroes it.
      CASE WHEN count(*) FILTER (WHERE t.new_status = 'LOST') > 0 THEN 0 ELSE count(*) FILTER (WHERE t.new_status = 'CLAIMABLE' AND NOT v_void) END,
      CASE WHEN count(*) FILTER (WHERE t.new_status = 'LOST') > 0 THEN 0 ELSE count(*) FILTER (WHERE t.new_status = 'CLAIMABLE' AND NOT v_void) END,
      NOW()
    FROM transitioned t
    WHERE t.user_id IS NOT NULL
    GROUP BY t.user_id
    ON CONFLICT (user_id) DO UPDATE
    SET
      calls_won = public.user_stats.calls_won + EXCLUDED.calls_won,
      calls_lost = public.user_stats.calls_lost + EXCLUDED.calls_lost,
      calls_voided = public.user_stats.calls_voided + EXCLUDED.calls_voided,
      pnl_base_units = public.user_stats.pnl_base_units + EXCLUDED.pnl_base_units,
      current_streak = CASE WHEN EXCLUDED.calls_lost > 0 THEN 0 ELSE public.user_stats.current_streak + EXCLUDED.calls_won END,
      best_streak = GREATEST(
        public.user_stats.best_streak,
        CASE WHEN EXCLUDED.calls_lost > 0 THEN 0 ELSE public.user_stats.current_streak + EXCLUDED.calls_won END
      ),
      updated_at = NOW()
    RETURNING 1
  ),
  notes AS (
    INSERT INTO public.notification_outbox (network, recipient_user_id, recipient_wallet_address, type, title, body, data)
    SELECT
      p_network, t.user_id, t.wallet_address, 'CLAIM_AVAILABLE',
      'Winnings ready to claim',
      'Your call on ' || p_match_id || ' settled — ' || t.payout_base_units::text || ' base units claimable.',
      jsonb_build_object('marketId', p_market_id, 'matchId', p_match_id, 'positionId', t.id, 'payoutBaseUnits', t.payout_base_units::text)
    FROM transitioned t
    WHERE t.new_status = 'CLAIMABLE' AND t.payout_base_units > 0
    RETURNING 1
  )
  SELECT count(*), count(*) FILTER (WHERE t.new_status = 'CLAIMABLE' AND t.payout_base_units > 0)
  INTO v_settled, v_winners
  FROM transitioned t;

  -- 4. One market-level settlement activity for the social feed (idempotent).
  INSERT INTO public.prediction_activity (
    network, actor_wallet_address, type, visibility, market_id, match_id,
    bucket, tx_signature, slot, status, title, body, metadata
  ) VALUES (
    p_network, 'onchain', 'CALL_SETTLED', 'public', p_market_id, p_match_id,
    v_win_stored, trim(p_settle_tx), p_slot, 'SETTLED',
    CASE WHEN v_void THEN 'Match voided — stakes refunded' ELSE v_win || ' won' END,
    CASE WHEN p_score_home IS NOT NULL AND p_score_away IS NOT NULL
      THEN p_score_home::text || '-' || p_score_away::text ELSE NULL END,
    jsonb_build_object('settleTx', trim(p_settle_tx), 'fixtureId', p_fixture_id, 'void', v_void)
  )
  ON CONFLICT (network, tx_signature, type) DO UPDATE
  SET
    status = 'SETTLED',
    bucket = v_win_stored,
    slot = COALESCE(EXCLUDED.slot, public.prediction_activity.slot),
    metadata = public.prediction_activity.metadata || EXCLUDED.metadata,
    updated_at = NOW();

  RETURN jsonb_build_object(
    'receiptId', v_receipt_id,
    'positionsSettled', v_settled,
    'winners', v_winners,
    'void', v_void
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.apply_settlement(TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, NUMERIC, NUMERIC, INTEGER, INTEGER, BIGINT, BIGINT, TEXT, JSONB) IS
'Idempotently settles all open positions for a market from on-chain Pot state, writes the receipt, bumps stats, and queues claim notifications.';

-- ---------------------------------------------------------------------------
-- apply_claim_fact — a winner (or refund) pulled their payout on-chain. Mark
-- the position CLAIMED, record the claim, and emit a CLAIMED activity. Match by
-- the Position PDA address. Idempotent.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.apply_claim_fact(
  p_network TEXT,
  p_wallet TEXT,
  p_position_address TEXT,
  p_claim_tx TEXT,
  p_amount NUMERIC DEFAULT NULL,
  p_slot BIGINT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_pos_id UUID;
  v_user_id UUID;
  v_pos_status TEXT;
BEGIN
  IF p_claim_tx IS NULL OR length(trim(p_claim_tx)) = 0 THEN
    RAISE EXCEPTION 'claim tx signature is required';
  END IF;

  IF p_position_address IS NOT NULL AND length(trim(p_position_address)) > 0 THEN
    SELECT id, user_id, status INTO v_pos_id, v_user_id, v_pos_status
    FROM public.prediction_positions
    WHERE network = p_network AND position_address = trim(p_position_address)
    LIMIT 1;
  END IF;

  IF v_pos_id IS NOT NULL THEN
    -- A winner/refund (CLAIMABLE) goes -> CLAIMED. A loser may ALSO call claim to
    -- reclaim the Position account's rent (payout 0); record the tx for audit but
    -- do NOT mislabel a loss as a won claim (finding [8]) — LOST stays LOST.
    UPDATE public.prediction_positions
    SET
      status = CASE WHEN status = 'CLAIMABLE' THEN 'CLAIMED' ELSE status END,
      claim_tx_signature = COALESCE(claim_tx_signature, trim(p_claim_tx)),
      claimed_at = CASE WHEN status = 'CLAIMABLE' THEN NOW() ELSE claimed_at END,
      payout_base_units = COALESCE(payout_base_units, p_amount),
      updated_at = NOW()
    WHERE id = v_pos_id AND status <> 'CLAIMED';
  END IF;

  INSERT INTO public.claims (
    network, user_id, wallet_address, position_id, claim_tx_signature, amount_base_units, status, claimed_at
  ) VALUES (
    p_network, v_user_id, trim(p_wallet), v_pos_id, trim(p_claim_tx), p_amount, 'CONFIRMED', NOW()
  )
  ON CONFLICT (network, claim_tx_signature) DO UPDATE
  SET
    position_id = COALESCE(public.claims.position_id, EXCLUDED.position_id),
    amount_base_units = COALESCE(EXCLUDED.amount_base_units, public.claims.amount_base_units),
    status = 'CONFIRMED',
    claimed_at = NOW();

  -- Only a real winning/refund claim earns a "Winnings claimed" feed event — a
  -- loser's rent-reclaim (v_pos_status = 'LOST') is recorded in claims but not
  -- surfaced as a claim in the social feed.
  IF v_pos_status = 'CLAIMABLE' THEN
    INSERT INTO public.prediction_activity (
      network, actor_user_id, actor_wallet_address, type, visibility, position_id, tx_signature, slot, status, title, body, metadata
    ) VALUES (
      p_network, v_user_id, trim(p_wallet), 'CLAIMED', 'public', v_pos_id, trim(p_claim_tx), p_slot, 'SETTLED',
      'Winnings claimed', COALESCE(p_amount::text, ''), jsonb_build_object('positionAddress', p_position_address)
    )
    ON CONFLICT (network, tx_signature, type) DO UPDATE
    SET
      status = 'SETTLED',
      slot = COALESCE(EXCLUDED.slot, public.prediction_activity.slot),
      position_id = COALESCE(public.prediction_activity.position_id, EXCLUDED.position_id),
      updated_at = NOW();
  END IF;

  RETURN jsonb_build_object('positionId', v_pos_id, 'matched', v_pos_id IS NOT NULL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION public.apply_claim_fact(TEXT, TEXT, TEXT, TEXT, NUMERIC, BIGINT) IS
'Idempotently marks a position CLAIMED from an on-chain claim tx (matched by Position PDA) and records the claim + activity.';

-- ---------------------------------------------------------------------------
-- record_prediction_call — harden the UPDATE path so a re-processed place_call
-- (reorg replay, cursor reset, or the reconciler running it for EVERY place_call
-- to backfill position_address) can NEVER resurrect a settled/claimed position.
-- Status only advances PENDING -> OPEN; terminal states are frozen; and the
-- outcome-relevant fields (bucket/stake/market/match) are only mutated while the
-- position is still PENDING/OPEN. position_address/slot still backfill always.
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
      network, user_id, wallet_address, market_id, match_id, position_address,
      bucket, stake_base_units, open_tx_signature, open_slot, status, metadata
    ) VALUES (
      p_network, v_user_id, trim(p_wallet_address), p_market_id, p_match_id, p_position_address,
      upper(p_bucket), p_stake_base_units, trim(p_tx_signature), p_slot,
      CASE WHEN p_slot IS NULL THEN 'PENDING' ELSE 'OPEN' END,
      COALESCE(p_metadata, '{}'::jsonb)
    )
    RETURNING id INTO v_position_id;
  ELSE
    UPDATE public.prediction_positions
    SET
      user_id = v_user_id,
      wallet_address = trim(p_wallet_address),
      market_id = CASE WHEN status IN ('PENDING', 'OPEN') THEN p_market_id ELSE market_id END,
      match_id = CASE WHEN status IN ('PENDING', 'OPEN') THEN p_match_id ELSE match_id END,
      position_address = COALESCE(p_position_address, position_address),
      bucket = CASE WHEN status IN ('PENDING', 'OPEN') THEN upper(p_bucket) ELSE bucket END,
      stake_base_units = CASE WHEN status IN ('PENDING', 'OPEN') THEN p_stake_base_units ELSE stake_base_units END,
      open_slot = COALESCE(p_slot, open_slot),
      status = CASE WHEN status = 'PENDING' AND p_slot IS NOT NULL THEN 'OPEN' ELSE status END,
      metadata = metadata || COALESCE(p_metadata, '{}'::jsonb),
      updated_at = NOW()
    WHERE id = v_existing_position_id
    RETURNING id INTO v_position_id;
  END IF;

  INSERT INTO public.prediction_activity (
    network, actor_user_id, actor_wallet_address, type, visibility, market_id, match_id,
    position_id, bucket, stake_base_units, tx_signature, slot, status, title, body, metadata
  ) VALUES (
    p_network, v_user_id, trim(p_wallet_address), 'CALL_PLACED', 'public', p_market_id, p_match_id,
    v_position_id, upper(p_bucket), p_stake_base_units, trim(p_tx_signature), p_slot,
    CASE WHEN p_slot IS NULL THEN 'PENDING' ELSE 'VERIFIED' END,
    'Call placed', upper(p_bucket), COALESCE(p_metadata, '{}'::jsonb)
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

-- ---------------------------------------------------------------------------
-- Lock the write RPCs to the backend service role. They are SECURITY DEFINER
-- (they bypass RLS), so the default PUBLIC execute grant would let ANY anon
-- client call apply_settlement / record_prediction_call / etc. directly via
-- PostgREST and corrupt the read model or fake settlements. The mobile app
-- reaches these only through the backend (which uses the service-role key).
-- sync_user_by_wallet is deliberately left PUBLIC — the mobile calls it directly
-- with the anon key at login, and it only upserts a profile row (no money).
-- ---------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION
  public.record_prediction_call(TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, BIGINT, JSONB),
  public.confirm_prediction_signature(TEXT, TEXT, TEXT, BIGINT, JSONB),
  public.apply_settlement(TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, NUMERIC, NUMERIC, INTEGER, INTEGER, BIGINT, BIGINT, TEXT, JSONB),
  public.apply_claim_fact(TEXT, TEXT, TEXT, TEXT, NUMERIC, BIGINT),
  public.advance_indexer_cursor(TEXT, TEXT, TEXT, TEXT, BIGINT)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION
  public.record_prediction_call(TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, BIGINT, JSONB),
  public.confirm_prediction_signature(TEXT, TEXT, TEXT, BIGINT, JSONB),
  public.apply_settlement(TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, NUMERIC, NUMERIC, INTEGER, INTEGER, BIGINT, BIGINT, TEXT, JSONB),
  public.apply_claim_fact(TEXT, TEXT, TEXT, TEXT, NUMERIC, BIGINT),
  public.advance_indexer_cursor(TEXT, TEXT, TEXT, TEXT, BIGINT)
TO service_role;
