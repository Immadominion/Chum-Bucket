-- ============================================================================
-- ATTACH VERIFIED WALLET — a re-proof by the Chumbucket wallet upgrades its label.
-- Owner: fleet/wallet   Created: 2026-10-04
-- Requires: 20261004130000_linked_wallets_chumbucket_type.sql
-- ============================================================================
--
-- attach_verified_wallet_v1 (20260913121500) reaffirms a wallet the same
-- account already holds without touching `wallet_type`. A Chumbucket wallet
-- whose address was first linked under another label (say, by an earlier
-- client) would then keep the wrong label, and the BFF would not pick it as
-- the account's trading wallet. This replaces the function with one change:
-- on reaffirm, p_wallet_type 'chumbucket' sets the label to 'chumbucket'.
-- Nothing else moves: the same ownership rules, outcomes, audit rows and
-- grants. The label is never an authorisation input.
--
-- Function definition only; no table or row is rewritten. Re-runnable.
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
     WHERE conrelid = 'public.linked_wallets'::regclass
       AND conname = 'linked_wallets_wallet_type_check'
       AND pg_get_constraintdef(oid) LIKE '%chumbucket%'
  ) THEN
    RAISE EXCEPTION 'requires 20261004130000_linked_wallets_chumbucket_type.sql';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.attach_verified_wallet_v1(
  p_user_id        UUID,
  p_wallet_address TEXT,
  p_proof_version  SMALLINT,
  p_nonce_id       UUID DEFAULT NULL,
  p_wallet_type    TEXT DEFAULT 'mwa'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_id      UUID;
  v_revoked TIMESTAMPTZ;
  v_exists  BOOLEAN;
  v_primary BOOLEAN;
BEGIN
  IF p_user_id IS NULL OR p_wallet_address IS NULL OR length(trim(p_wallet_address)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  -- 1. Reaffirm. `user_id = p_user_id` lives in the WHERE clause, so if the
  --    address changed hands between here and the caller's proof, this matches
  --    zero rows and falls through — never a read-then-write overwrite.
  UPDATE public.linked_wallets w
     SET siws_proof_version = p_proof_version,
         -- The Chumbucket wallet's own proof upgrades its label (one way: a
         -- 'chumbucket' wallet is never relabelled by another flow).
         wallet_type        = CASE WHEN p_wallet_type = 'chumbucket'
                                   THEN 'chumbucket' ELSE w.wallet_type END,
         verified_at        = NOW(),
         revoked_at         = NULL,   -- they just re-proved it
         last_signed_at     = NOW(),
         updated_at         = NOW()
   WHERE w.wallet_address = p_wallet_address
     AND w.user_id        = p_user_id
  RETURNING w.id INTO v_id;

  IF v_id IS NOT NULL THEN
    INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, to_user_id, nonce_id, reason)
    VALUES (p_wallet_address, 'reaffirmed', p_user_id, p_user_id, p_nonce_id, 'siws proof re-verified');
    RETURN jsonb_build_object('ok', true, 'link_id', v_id, 'outcome', 'reaffirmed');
  END IF;

  -- 2. First active wallet on the account becomes primary; a later one does not
  --    silently steal the flag. (Advisory only — is_primary is a display hint,
  --    never an authorisation input, so a concurrent tie here is harmless.)
  SELECT NOT EXISTS (
    SELECT 1 FROM public.linked_wallets w
     WHERE w.user_id = p_user_id AND w.revoked_at IS NULL
  ) INTO v_primary;

  -- 3. Claim the address. ON CONFLICT DO NOTHING — never DO UPDATE SET user_id,
  --    which is exactly how the legacy path let a wallet slot be stolen. A
  --    losing insert writes nothing and reports why.
  INSERT INTO public.linked_wallets (
    user_id, wallet_address, wallet_type, is_primary,
    first_seen_at, last_signed_at, siws_proof_version, verified_at
  )
  VALUES (
    p_user_id, p_wallet_address, COALESCE(p_wallet_type, 'mwa'), v_primary,
    NOW(), NOW(), p_proof_version, NOW()
  )
  ON CONFLICT (wallet_address) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    INSERT INTO public.wallet_link_audit (wallet_address, action, to_user_id, nonce_id, reason)
    VALUES (p_wallet_address, 'linked', p_user_id, p_nonce_id, 'siws proof verified');
    RETURN jsonb_build_object('ok', true, 'link_id', v_id, 'outcome', 'linked', 'is_primary', v_primary);
  END IF;

  -- 4. Someone else holds the address.
  SELECT true, w.revoked_at INTO v_exists, v_revoked
    FROM public.linked_wallets w
   WHERE w.wallet_address = p_wallet_address;

  IF NOT COALESCE(v_exists, false) THEN
    -- The conflicting row vanished between the insert and this read. Safe to
    -- report as contention rather than guess.
    RETURN jsonb_build_object('ok', false, 'reason', 'link_contention');
  END IF;

  RETURN jsonb_build_object(
    'ok', false,
    'reason', CASE WHEN v_revoked IS NULL
                   THEN 'wallet_owned_by_another_user'
                   ELSE 'wallet_requires_transfer' END
  );
END
$$;


REVOKE EXECUTE ON FUNCTION public.attach_verified_wallet_v1(UUID, TEXT, SMALLINT, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.attach_verified_wallet_v1(UUID, TEXT, SMALLINT, UUID, TEXT)
  TO service_role;
