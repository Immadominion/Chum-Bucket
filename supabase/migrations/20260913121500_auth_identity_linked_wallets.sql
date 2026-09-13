-- ============================================================================
-- AUTH IDENTITY 4/4 — linked_wallets: proof provenance + one-active-owner.
-- Packet: A (identity)   Created: 2026-09-13
-- Contract: pivot-contracts-v1 §5 (additive columns + partial unique index so
--           one active address maps to exactly one user).
-- ============================================================================
--
-- Strictly additive to public.linked_wallets: three new nullable columns and
-- one new index. No existing column is dropped, retyped or renamed; no existing
-- constraint, policy or function is altered.
--
-- Pre-existing state this file deliberately does NOT touch (contract §2/§6):
--   * `linked_wallets_wallet_address_key` — a FULL UNIQUE on wallet_address,
--     created in 20260715134226. It already implies "one address, one row", so
--     the partial index below is currently implied by it. Both are kept: the
--     partial index is the constraint that still holds if the legacy full
--     unique is ever relaxed to let revoked history rows accumulate, and it is
--     what contract §5 asks for by name. Dropping the legacy constraint is a
--     production change, not a packet change.
--   * `linked_wallets_public_select ... USING (true)` — the table is world-
--     readable today. Adding a tight policy beside a permissive one is a no-op
--     (contract §2), so none is added here. The three new columns are a proof
--     version and two timestamps: no PII, no secret, nothing that widens that
--     pre-existing exposure. Writes are already service-role only — RLS is on
--     and there is no INSERT/UPDATE/DELETE policy at all.
-- ============================================================================

ALTER TABLE public.linked_wallets
  ADD COLUMN IF NOT EXISTS siws_proof_version SMALLINT,
  ADD COLUMN IF NOT EXISTS verified_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS revoked_at         TIMESTAMPTZ;

COMMENT ON COLUMN public.linked_wallets.siws_proof_version IS
  'Version of the SIWS message format whose signature verified this link. NULL = pre-pivot row linked without a server nonce; treat as unproven and re-verify before trusting it for anything.';
COMMENT ON COLUMN public.linked_wallets.verified_at IS
  'When a server-issued, single-use nonce was last redeemed for this address by this user. NULL = never proven.';
COMMENT ON COLUMN public.linked_wallets.revoked_at IS
  'When this link stopped being active. NULL = active. A revoked row is retained as history, never deleted.';

-- ---------------------------------------------------------------------------
-- One ACTIVE address maps to exactly one user (contract §5).
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_linked_wallets_active_address
  ON public.linked_wallets (wallet_address)
  WHERE revoked_at IS NULL;

-- Owner-scoped active lookup — the shape every read below uses.
CREATE INDEX IF NOT EXISTS idx_linked_wallets_active_user
  ON public.linked_wallets (user_id)
  WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- wallet_link_audit — why an address changed hands.
-- ---------------------------------------------------------------------------
-- "Without an explicit audited transfer" needs somewhere for the audit to live.
-- One row per attach / reaffirm / revoke / transfer. Append-only by convention;
-- nothing in this file ever updates or deletes a row here.
CREATE TABLE IF NOT EXISTS public.wallet_link_audit (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_address TEXT NOT NULL,
  action         TEXT NOT NULL,
  from_user_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
  to_user_id     UUID REFERENCES public.users(id) ON DELETE SET NULL,
  -- The redeemed wallet_nonces row that proved it, when there was one.
  -- Deliberately NOT a foreign key: wallet_nonces is swept on a retention
  -- schedule, and the audit trail must outlive the challenge that produced it.
  nonce_id       UUID,
  actor          TEXT NOT NULL DEFAULT 'service',
  reason         TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT wallet_link_audit_action_check CHECK (
    action IN ('linked', 'reaffirmed', 'revoked', 'transferred')
  ),
  CONSTRAINT wallet_link_audit_address_not_empty CHECK (length(trim(wallet_address)) > 0),
  -- A transfer is the one action that must name both sides, and they must differ.
  CONSTRAINT wallet_link_audit_transfer_shape CHECK (
    action <> 'transferred'
    OR (from_user_id IS NOT NULL AND to_user_id IS NOT NULL AND from_user_id <> to_user_id)
  )
);

CREATE INDEX IF NOT EXISTS idx_wallet_link_audit_address
  ON public.wallet_link_audit (wallet_address, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_link_audit_to_user
  ON public.wallet_link_audit (to_user_id);

-- ── Mandatory default-deny template (contract §5) ───────────────────────────
ALTER TABLE public.wallet_link_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_link_audit FROM anon, authenticated;
GRANT ALL ON public.wallet_link_audit TO service_role;

COMMENT ON TABLE public.wallet_link_audit IS
  'Append-only trail of every wallet link, reaffirmation, revocation and transfer. Default-deny: RLS on, zero policies, service_role only.';

-- ---------------------------------------------------------------------------
-- attach_verified_wallet_v1 — the ONLY sanctioned link path.
-- ---------------------------------------------------------------------------
-- Called only after the BFF has verified a SIWS signature AND atomically
-- consumed the matching nonce. It never takes a signature or a nonce plaintext:
-- by the time control reaches here, proof has already happened.
--
-- Outcomes:
--   ok   / 'linked'                    a new active link
--   ok   / 'reaffirmed'                same user re-proving an address it
--                                      already holds — idempotent
--   fail / 'wallet_owned_by_another_user'
--                                      the address is actively linked elsewhere.
--                                      NOT repointed. This is the duplicate-
--                                      wallet guard; moving it requires
--                                      transfer_verified_wallet_v1.
--   fail / 'wallet_requires_transfer'  the address has history under a
--                                      different account (a revoked row). Still
--                                      a transfer, still audited.
--
-- Contrast with the legacy path this replaces: sync_user_by_wallet upserts
-- `ON CONFLICT (wallet_address) DO UPDATE SET user_id = EXCLUDED.user_id`, i.e.
-- last writer wins the wallet (contract §8 finding 2). Here, the first active
-- owner wins and every change of hands is recorded.
CREATE FUNCTION public.attach_verified_wallet_v1(
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

-- ---------------------------------------------------------------------------
-- revoke_verified_wallet_v1 — deactivate without losing history.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.revoke_verified_wallet_v1(
  p_user_id        UUID,
  p_wallet_address TEXT,
  p_reason         TEXT DEFAULT NULL,
  p_actor          TEXT DEFAULT 'service'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_id UUID;
BEGIN
  -- Atomic: only an ACTIVE row owned by this user is revocable, checked in the
  -- WHERE clause rather than by a prior read.
  UPDATE public.linked_wallets w
     SET revoked_at = NOW(),
         updated_at = NOW()
   WHERE w.wallet_address = p_wallet_address
     AND w.user_id        = p_user_id
     AND w.revoked_at    IS NULL
  RETURNING w.id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_active_link_for_user');
  END IF;

  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, actor, reason)
  VALUES (p_wallet_address, 'revoked', p_user_id, COALESCE(p_actor, 'service'), p_reason);

  RETURN jsonb_build_object('ok', true, 'link_id', v_id, 'outcome', 'revoked');
END
$$;

REVOKE EXECUTE ON FUNCTION public.revoke_verified_wallet_v1(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.revoke_verified_wallet_v1(UUID, TEXT, TEXT, TEXT)
  TO service_role;

-- ---------------------------------------------------------------------------
-- transfer_verified_wallet_v1 — the EXPLICIT audited transfer.
-- ---------------------------------------------------------------------------
-- The only way an address changes owner. Deliberately ceremonious:
--   * the caller must name the CURRENT owner (p_from_user_id). A guess that is
--     wrong moves nothing — the check is in the UPDATE's WHERE clause, so there
--     is no read-then-write window for an owner change to slip through.
--   * a fresh SIWS proof by the NEW owner must already have been verified and
--     its nonce consumed; pass that nonce id.
--   * a human-readable reason is mandatory — a transfer with no stated cause is
--     rejected, so the audit trail can never be empty of intent.
--
-- The legacy full UNIQUE on wallet_address means an address is one row, so the
-- transfer reassigns that row rather than stacking a second active one. The
-- partial unique index enforces the same invariant independently.
CREATE FUNCTION public.transfer_verified_wallet_v1(
  p_wallet_address TEXT,
  p_from_user_id   UUID,
  p_to_user_id     UUID,
  p_reason         TEXT,
  p_proof_version  SMALLINT,
  p_nonce_id       UUID DEFAULT NULL,
  p_actor          TEXT DEFAULT 'service'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_from_user_id IS NULL OR p_to_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  IF p_from_user_id = p_to_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'same_user');
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reason_required');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_to_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  UPDATE public.linked_wallets w
     SET user_id            = p_to_user_id,
         is_primary         = false,
         siws_proof_version = p_proof_version,
         verified_at        = NOW(),
         revoked_at         = NULL,
         last_signed_at     = NOW(),
         updated_at         = NOW()
   WHERE w.wallet_address = p_wallet_address
     AND w.user_id        = p_from_user_id
  RETURNING w.id INTO v_id;

  IF v_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_owned_by_from_user');
  END IF;

  INSERT INTO public.wallet_link_audit (
    wallet_address, action, from_user_id, to_user_id, nonce_id, actor, reason
  )
  VALUES (
    p_wallet_address, 'transferred', p_from_user_id, p_to_user_id, p_nonce_id,
    COALESCE(p_actor, 'service'), p_reason
  );

  RETURN jsonb_build_object('ok', true, 'link_id', v_id, 'outcome', 'transferred');
END
$$;

REVOKE EXECUTE ON FUNCTION public.transfer_verified_wallet_v1(TEXT, UUID, UUID, TEXT, SMALLINT, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.transfer_verified_wallet_v1(TEXT, UUID, UUID, TEXT, SMALLINT, UUID, TEXT)
  TO service_role;
