-- ============================================================================
-- AUTH IDENTITY 3/4 — legacy_identity_claims: the private legacy→canonical map.
-- Packet: A (identity)   Created: 2026-09-13
-- Contract: pivot-contracts-v1 §5 (new table + default-deny template, audited
--           migration state, service-role only, never client-readable).
-- ============================================================================
--
-- The problem this closes. Contract §8 finding 2: sync_user_by_wallet is
-- deliberately anon-executable and upserts `ON CONFLICT (wallet_address) DO
-- UPDATE SET user_id = EXCLUDED.user_id`, so anyone can claim the globally
-- unique slot for a wallet they do not control. That must stop being the
-- account-creation path. Migrating a legacy Privy/wallet account onto a
-- canonical, session-backed public.users row therefore needs a record that is:
--
--   * private          — a legacy Privy DID is an identifier for a real person;
--                        it is never client-readable, in either direction.
--   * evidence-bound   — a claim carries WHAT proved it, and the permitted
--                        values are all server-verified. There is no
--                        'client_asserted' value, so an unverified claim cannot
--                        even be represented, let alone stored.
--   * idempotent       — replaying a claim is a no-op, not a second row and not
--                        a silent repoint.
--   * audited          — every state change appends to an immutable-by-
--                        convention trail with who/when/why.
--
-- Nothing in this file grants a client any access. There is no policy, so the
-- table is default-deny for every role; service_role bypasses RLS and is the
-- only reader. No function here is executable by anon or authenticated.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.legacy_identity_claims (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Which legacy namespace the subject lives in.
  legacy_provider      TEXT NOT NULL,
  -- The legacy identifier itself: a Privy DID, a pre-pivot public.users.id, or
  -- a wallet address that was the account key under the old scheme.
  legacy_subject       TEXT NOT NULL,

  -- Where it lands. Identity is public.users.id (invariant 3).
  user_id              UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  state                TEXT NOT NULL DEFAULT 'PENDING',

  -- HOW this was proven. Every permitted value is something the SERVER checked.
  evidence             TEXT NOT NULL,
  -- A non-secret pointer to that check (a Privy user id, an auth.users id, a
  -- wallet_nonces.id). NEVER a token, JWT, signature or key.
  evidence_ref         TEXT,

  -- The Supabase session that made the claim, when there was one.
  claimed_by_auth_user_id UUID,

  claimed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verified_at          TIMESTAMPTZ,
  migrated_at          TIMESTAMPTZ,
  rejected_at          TIMESTAMPTZ,

  -- Append-only trail of every transition: [{at, from, to, actor, note}, ...].
  audit_trail          JSONB NOT NULL DEFAULT '[]'::jsonb,

  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One legacy subject resolves to at most one canonical account, ever. This is
  -- the constraint that makes a double claim a no-op instead of a fork.
  CONSTRAINT legacy_identity_claims_subject_unique UNIQUE (legacy_provider, legacy_subject),

  CONSTRAINT legacy_identity_claims_provider_check CHECK (
    legacy_provider IN ('privy', 'legacy_user_id', 'wallet')
  ),
  CONSTRAINT legacy_identity_claims_subject_not_empty CHECK (
    length(trim(legacy_subject)) > 0
  ),
  CONSTRAINT legacy_identity_claims_state_check CHECK (
    state IN ('PENDING', 'VERIFIED', 'MIGRATED', 'REJECTED')
  ),
  -- The whitelist IS the "no unverified client input" rule, enforced by the
  -- database rather than by remembering to check in application code.
  CONSTRAINT legacy_identity_claims_evidence_check CHECK (
    evidence IN ('privy_session', 'supabase_jwt', 'siws_proof', 'operator_manual')
  ),
  CONSTRAINT legacy_identity_claims_audit_is_array CHECK (
    jsonb_typeof(audit_trail) = 'array'
  ),
  -- State and its timestamp cannot disagree.
  CONSTRAINT legacy_identity_claims_state_timestamps CHECK (
    (state <> 'VERIFIED' OR verified_at IS NOT NULL)
    AND (state <> 'MIGRATED' OR migrated_at IS NOT NULL)
    AND (state <> 'REJECTED' OR rejected_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_legacy_identity_claims_user_id
  ON public.legacy_identity_claims (user_id);
CREATE INDEX IF NOT EXISTS idx_legacy_identity_claims_state
  ON public.legacy_identity_claims (state);

-- ── Mandatory default-deny template (contract §5) ───────────────────────────
ALTER TABLE public.legacy_identity_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.legacy_identity_claims FROM anon, authenticated;
GRANT ALL ON public.legacy_identity_claims TO service_role;

COMMENT ON TABLE public.legacy_identity_claims IS
  'PRIVATE legacy->canonical identity map with audited migration state. RLS enabled with ZERO policies: not readable or writable by anon or authenticated under any circumstance. service_role only. Never expose a row, or the existence of a row, to a client.';
COMMENT ON COLUMN public.legacy_identity_claims.evidence IS
  'What the SERVER verified before the claim was recorded. The CHECK whitelist has no client-asserted value by design — an unverified claim cannot be represented.';
COMMENT ON COLUMN public.legacy_identity_claims.evidence_ref IS
  'Non-secret pointer to the verification (provider user id / auth user id / nonce id). Never a token, signature, JWT or key.';

-- ---------------------------------------------------------------------------
-- claim_legacy_identity_v1 — idempotent, evidence-bound claim.
-- ---------------------------------------------------------------------------
-- Outcomes, all in one statement plus one read:
--   ok / 'claimed'            first claim, row created in PENDING
--   ok / 'already_claimed'    same subject already mapped to the same user —
--                             a genuine no-op: nothing is written, no timestamp
--                             moves, the audit trail is not appended to
--   fail / 'claimed_by_another_user'
--                             the subject already belongs to a different
--                             canonical account. NOT repointed. Resolving it is
--                             an operator action, deliberately not an API one.
--   fail / 'unverified_evidence'
--                             the caller passed an evidence kind outside the
--                             server-verified whitelist.
--
-- ON CONFLICT DO NOTHING (not DO UPDATE) is the whole point: the legacy
-- sync_user_by_wallet path used DO UPDATE SET user_id = EXCLUDED.user_id, which
-- is precisely how a wallet slot gets stolen (contract §8 finding 2).
CREATE FUNCTION public.claim_legacy_identity_v1(
  p_legacy_provider  TEXT,
  p_legacy_subject   TEXT,
  p_user_id          UUID,
  p_evidence         TEXT,
  p_evidence_ref     TEXT DEFAULT NULL,
  p_auth_user_id     UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_id       UUID;
  v_existing public.legacy_identity_claims%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_user');
  END IF;

  -- Defence in depth: the CHECK constraint would reject this anyway, but a
  -- clean reason beats a constraint-violation 500 at the BFF boundary.
  IF p_evidence IS NULL
     OR p_evidence NOT IN ('privy_session', 'supabase_jwt', 'siws_proof', 'operator_manual') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unverified_evidence');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  INSERT INTO public.legacy_identity_claims (
    legacy_provider, legacy_subject, user_id, state,
    evidence, evidence_ref, claimed_by_auth_user_id, audit_trail
  )
  VALUES (
    p_legacy_provider, p_legacy_subject, p_user_id, 'PENDING',
    p_evidence, p_evidence_ref, p_auth_user_id,
    jsonb_build_array(jsonb_build_object(
      'at', NOW(), 'from', NULL, 'to', 'PENDING',
      'actor', COALESCE(p_auth_user_id::text, 'service'),
      'note', 'claimed with evidence ' || p_evidence
    ))
  )
  ON CONFLICT (legacy_provider, legacy_subject) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'claim_id', v_id, 'state', 'PENDING', 'outcome', 'claimed');
  END IF;

  SELECT * INTO v_existing
    FROM public.legacy_identity_claims c
   WHERE c.legacy_provider = p_legacy_provider
     AND c.legacy_subject  = p_legacy_subject;

  IF v_existing.user_id = p_user_id THEN
    -- Idempotent replay. Nothing written.
    RETURN jsonb_build_object(
      'ok', true, 'claim_id', v_existing.id, 'state', v_existing.state, 'outcome', 'already_claimed'
    );
  END IF;

  RETURN jsonb_build_object('ok', false, 'reason', 'claimed_by_another_user');
END
$$;

REVOKE EXECUTE ON FUNCTION public.claim_legacy_identity_v1(TEXT, TEXT, UUID, TEXT, TEXT, UUID)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.claim_legacy_identity_v1(TEXT, TEXT, UUID, TEXT, TEXT, UUID)
  TO service_role;

-- ---------------------------------------------------------------------------
-- advance_legacy_claim_v1 — audited state transition.
-- ---------------------------------------------------------------------------
-- Legal edges only: PENDING→VERIFIED, PENDING→REJECTED, VERIFIED→MIGRATED,
-- VERIFIED→REJECTED. MIGRATED and REJECTED are terminal. A transition to the
-- state a claim is already in is an idempotent no-op, not an error and not a
-- second audit entry.
CREATE FUNCTION public.advance_legacy_claim_v1(
  p_claim_id     UUID,
  p_to_state     TEXT,
  p_actor        TEXT DEFAULT 'service',
  p_note         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_row     public.legacy_identity_claims%ROWTYPE;
  v_updated public.legacy_identity_claims%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.legacy_identity_claims c WHERE c.id = p_claim_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_claim');
  END IF;

  IF v_row.state = p_to_state THEN
    RETURN jsonb_build_object('ok', true, 'claim_id', v_row.id, 'state', v_row.state, 'outcome', 'unchanged');
  END IF;

  IF NOT (
       (v_row.state = 'PENDING'  AND p_to_state IN ('VERIFIED', 'REJECTED'))
    OR (v_row.state = 'VERIFIED' AND p_to_state IN ('MIGRATED', 'REJECTED'))
  ) THEN
    RETURN jsonb_build_object(
      'ok', false, 'reason', 'illegal_transition', 'from', v_row.state, 'to', p_to_state
    );
  END IF;

  -- Guarded by `state = v_row.state` so a concurrent transition loses rather
  -- than silently overwriting: same atomic-claim shape as the nonce consume.
  UPDATE public.legacy_identity_claims c
     SET state       = p_to_state,
         verified_at = CASE WHEN p_to_state = 'VERIFIED' THEN NOW() ELSE c.verified_at END,
         migrated_at = CASE WHEN p_to_state = 'MIGRATED' THEN NOW() ELSE c.migrated_at END,
         rejected_at = CASE WHEN p_to_state = 'REJECTED' THEN NOW() ELSE c.rejected_at END,
         updated_at  = NOW(),
         audit_trail = c.audit_trail || jsonb_build_array(jsonb_build_object(
           'at', NOW(), 'from', c.state, 'to', p_to_state,
           'actor', COALESCE(p_actor, 'service'), 'note', p_note
         ))
   WHERE c.id = p_claim_id
     AND c.state = v_row.state
  RETURNING c.* INTO v_updated;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'concurrent_transition');
  END IF;

  -- MIGRATED means this legacy identity is now fully represented by user_id.
  -- The row stays forever: it is the audit record of the merge.
  RETURN jsonb_build_object(
    'ok', true, 'claim_id', v_updated.id, 'state', v_updated.state, 'outcome', 'advanced'
  );
END
$$;

REVOKE EXECUTE ON FUNCTION public.advance_legacy_claim_v1(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.advance_legacy_claim_v1(UUID, TEXT, TEXT, TEXT)
  TO service_role;
