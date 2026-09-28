-- Existing-profile bootstrap. Additive and deliberately EMPTY: never copy
-- users.wallet_address or linked_wallets into this trusted registry. Their old
-- client-writable mappings are NOT historical ownership evidence.
-- An operator must review a private pre-incident inventory/independent evidence
-- and approve a cohort before enabling EXISTING_ACCOUNT_CLAIMS_ENABLED.

CREATE TABLE public.existing_account_anchors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  wallet_address TEXT NOT NULL CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  network TEXT NOT NULL CHECK (network IN ('devnet', 'mainnet-beta')),
  evidence_sha256 TEXT NOT NULL CHECK (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  review_ref TEXT NOT NULL CHECK (length(trim(review_ref)) BETWEEN 1 AND 200),
  reviewed_by TEXT NOT NULL CHECK (length(trim(reviewed_by)) BETWEEN 1 AND 200),
  reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  UNIQUE (network, wallet_address)
);
ALTER TABLE public.existing_account_anchors ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.existing_account_anchors FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON public.existing_account_anchors TO service_role;
GRANT UPDATE (revoked_at) ON public.existing_account_anchors TO service_role;

CREATE TABLE public.existing_account_proofs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Intentionally not canonical user_id: the verified auth subject is still
  -- unlinked. No FK cascade from deleting an auth user can erase claim history.
  auth_user_id UUID NOT NULL,
  wallet_address TEXT NOT NULL CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  network TEXT NOT NULL CHECK (network IN ('devnet', 'mainnet-beta')),
  nonce_hash TEXT NOT NULL UNIQUE CHECK (nonce_hash ~ '^[0-9a-f]{64}$'),
  message_hash TEXT NOT NULL UNIQUE CHECK (message_hash ~ '^[0-9a-f]{64}$'),
  purpose TEXT NOT NULL DEFAULT 'claim_account' CHECK (purpose = 'claim_account'),
  issued_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  consumed_reason TEXT CHECK (consumed_reason IN ('redeemed', 'superseded')),
  CHECK (expires_at >= issued_at + interval '30 seconds' AND expires_at <= issued_at + interval '15 minutes'),
  CHECK ((consumed_at IS NULL) = (consumed_reason IS NULL))
);
CREATE INDEX existing_account_proofs_subject_time ON public.existing_account_proofs(auth_user_id, issued_at);
ALTER TABLE public.existing_account_proofs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.existing_account_proofs FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.existing_account_proofs TO service_role;

CREATE TABLE public.existing_account_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  auth_user_id UUID NOT NULL,
  anchor_id UUID NOT NULL REFERENCES public.existing_account_anchors(id) ON DELETE RESTRICT,
  proof_id UUID NOT NULL UNIQUE REFERENCES public.existing_account_proofs(id) ON DELETE RESTRICT,
  proof_version INTEGER NOT NULL CHECK (proof_version = 1),
  claimed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.existing_account_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.existing_account_claims FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.existing_account_claims TO service_role;

CREATE FUNCTION public.existing_account_anchor_guard_v1()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF (to_jsonb(NEW) - 'revoked_at') IS DISTINCT FROM (to_jsonb(OLD) - 'revoked_at')
     OR OLD.revoked_at IS NOT NULL OR NEW.revoked_at IS NULL THEN
    RAISE EXCEPTION 'account anchors may only be revoked once';
  END IF;
  RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION public.existing_account_anchor_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.existing_account_anchor_guard_v1() TO service_role;
CREATE TRIGGER existing_account_anchor_guard BEFORE UPDATE ON public.existing_account_anchors
  FOR EACH ROW EXECUTE FUNCTION public.existing_account_anchor_guard_v1();

CREATE FUNCTION public.existing_account_history_guard_v1()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'account claim history is immutable';
END $$;
REVOKE EXECUTE ON FUNCTION public.existing_account_history_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.existing_account_history_guard_v1() TO service_role;
CREATE TRIGGER existing_account_anchor_no_delete BEFORE DELETE ON public.existing_account_anchors
  FOR EACH ROW EXECUTE FUNCTION public.existing_account_history_guard_v1();
CREATE TRIGGER existing_account_anchor_no_truncate BEFORE TRUNCATE ON public.existing_account_anchors
  FOR EACH STATEMENT EXECUTE FUNCTION public.existing_account_history_guard_v1();
CREATE TRIGGER existing_account_claims_no_edit BEFORE UPDATE OR DELETE ON public.existing_account_claims
  FOR EACH ROW EXECUTE FUNCTION public.existing_account_history_guard_v1();
CREATE TRIGGER existing_account_claims_no_truncate BEFORE TRUNCATE ON public.existing_account_claims
  FOR EACH STATEMENT EXECUTE FUNCTION public.existing_account_history_guard_v1();

CREATE FUNCTION public.issue_existing_account_proof_v1(
  p_auth_user_id UUID, p_wallet_address TEXT, p_network TEXT,
  p_nonce_hash TEXT, p_message_hash TEXT, p_issued_at TIMESTAMPTZ, p_expires_at TIMESTAMPTZ
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_now TIMESTAMPTZ;
BEGIN
  IF p_auth_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'claim_unavailable');
  END IF;
  -- Serialize issue/redemption per auth subject, including rate limits. The
  -- unique users.auth_user_id constraint separately protects other writers.
  PERFORM pg_advisory_xact_lock(hashtextextended('existing-account:' || p_auth_user_id::text, 0));
  v_now := clock_timestamp();
  IF p_issued_at IS NULL OR p_expires_at IS NULL
     OR p_issued_at < v_now - interval '30 seconds' OR p_issued_at > v_now + interval '30 seconds'
     OR p_expires_at <= v_now THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_expired');
  END IF;
  IF (SELECT count(*) FROM public.existing_account_proofs
       WHERE auth_user_id = p_auth_user_id AND issued_at > v_now - interval '1 minute') >= 10 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
  END IF;
  UPDATE public.existing_account_proofs SET consumed_at = v_now, consumed_reason = 'superseded'
    WHERE auth_user_id = p_auth_user_id AND consumed_at IS NULL;
  INSERT INTO public.existing_account_proofs
    (auth_user_id, wallet_address, network, nonce_hash, message_hash, issued_at, expires_at)
  VALUES (p_auth_user_id, p_wallet_address, p_network, p_nonce_hash, p_message_hash, p_issued_at, p_expires_at);
  RETURN jsonb_build_object('ok', true);
END $$;
REVOKE EXECUTE ON FUNCTION public.issue_existing_account_proof_v1(UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_existing_account_proof_v1(UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO service_role;

-- Called ONLY after GoTrue authentication and cryptographic SIWS verification.
-- All binding/eligibility/conflict checks, consumption, mapping and evidence
-- commit in one transaction. There is no create-person or wallet-transfer path.
CREATE FUNCTION public.claim_existing_account_v1(
  p_auth_user_id UUID, p_wallet_address TEXT, p_network TEXT, p_nonce_hash TEXT, p_message_hash TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_proof public.existing_account_proofs%ROWTYPE;
  v_anchor public.existing_account_anchors%ROWTYPE;
  v_owner UUID;
  v_existing UUID;
  v_outcome TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('existing-account:' || p_auth_user_id::text, 0));
  SELECT * INTO v_proof FROM public.existing_account_proofs WHERE nonce_hash = p_nonce_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'nonce_unknown'); END IF;
  IF v_proof.auth_user_id IS DISTINCT FROM p_auth_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_user_mismatch');
  END IF;
  IF v_proof.wallet_address IS DISTINCT FROM p_wallet_address
     OR v_proof.network IS DISTINCT FROM p_network OR v_proof.message_hash IS DISTINCT FROM p_message_hash THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_unknown');
  END IF;
  IF v_proof.consumed_reason = 'superseded' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_reused');
  END IF;
  IF v_proof.expires_at <= clock_timestamp() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_expired');
  END IF;
  SELECT * INTO v_anchor FROM public.existing_account_anchors
    WHERE wallet_address = p_wallet_address AND network = p_network FOR SHARE;
  IF NOT FOUND OR v_anchor.revoked_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'claim_unavailable');
  END IF;
  -- Row lock prevents two signed-in users claiming the same historical person.
  SELECT auth_user_id INTO v_owner FROM public.users WHERE id = v_anchor.user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'claim_unavailable'); END IF;
  -- Waiting for the anchor/person locks must not extend the proof lifetime.
  IF v_proof.expires_at <= clock_timestamp() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_expired');
  END IF;
  SELECT id INTO v_existing FROM public.users WHERE auth_user_id = p_auth_user_id;
  IF (v_owner IS NOT NULL AND v_owner IS DISTINCT FROM p_auth_user_id)
     OR (v_existing IS NOT NULL AND v_existing IS DISTINCT FROM v_anchor.user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'claim_conflict');
  END IF;
  IF v_proof.consumed_at IS NOT NULL THEN
    -- A retry may read its own committed result, never execute the claim twice.
    IF v_owner = p_auth_user_id AND EXISTS (
      SELECT 1 FROM public.existing_account_claims
       WHERE proof_id = v_proof.id AND user_id = v_anchor.user_id AND auth_user_id = p_auth_user_id
    ) THEN
      RETURN jsonb_build_object('ok', true, 'user_id', v_anchor.user_id, 'outcome', 'already_claimed');
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_reused');
  END IF;
  v_outcome := CASE WHEN v_owner = p_auth_user_id THEN 'already_claimed' ELSE 'claimed' END;
  BEGIN
    UPDATE public.users SET auth_user_id = p_auth_user_id WHERE id = v_anchor.user_id;
    UPDATE public.existing_account_proofs SET consumed_at = clock_timestamp(), consumed_reason = 'redeemed'
      WHERE id = v_proof.id;
    INSERT INTO public.existing_account_claims(user_id, auth_user_id, anchor_id, proof_id, proof_version)
      VALUES (v_anchor.user_id, p_auth_user_id, v_anchor.id, v_proof.id, 1);
  EXCEPTION WHEN unique_violation THEN
    -- Another trusted identity writer won. The subtransaction rolls back ALL
    -- three writes, including nonce consumption. Never merge or partially bind.
    RETURN jsonb_build_object('ok', false, 'reason', 'claim_conflict');
  END;
  RETURN jsonb_build_object('ok', true, 'user_id', v_anchor.user_id, 'outcome', v_outcome);
END $$;
REVOKE EXECUTE ON FUNCTION public.claim_existing_account_v1(UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_existing_account_v1(UUID, TEXT, TEXT, TEXT, TEXT) TO service_role;

COMMENT ON TABLE public.existing_account_anchors IS
  'Private reviewed historical wallet-to-person bindings. Empty on migration; never backfill from client-writable mappings. No client approval API.';
COMMENT ON TABLE public.existing_account_proofs IS
  'Auth-subject-bound claim proofs; only hashes are stored. Full message hash binds domain, URI, purpose, wallet, network and exact timestamps.';
