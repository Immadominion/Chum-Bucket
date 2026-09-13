-- ============================================================================
-- AUTH IDENTITY 2/4 — wallet_nonces: single-use, short-lived SIWS challenges.
-- Packet: A (identity)   Created: 2026-09-13
-- Contract: pivot-contracts-v1 §5 (new table + default-deny template, pinned
--           search_path, REVOKE/GRANT pair on every new function).
-- ============================================================================
--
-- Why this table exists: src/auth/WalletSignature.ts is honest in its header
-- that it has "no server nonce store", so a leaked proof is replayable inside
-- SIGNATURE_MAX_AGE_MS. That tradeoff was acceptable for a public self-authored
-- follow edge. It is NOT acceptable for binding a wallet to an account, which
-- is a permanent identity claim. This is that missing nonce store.
--
-- What is stored, and what is deliberately NOT:
--   * `nonce_hash` — sha256(nonce) as 64 lowercase hex chars.
--   * the nonce PLAINTEXT is never written here, never logged, never returned
--     by any function below. It exists only in the issuing response and in the
--     message the wallet signs. A dump of this table therefore cannot be used
--     to forge or pre-compute a link: the nonce is 256 bits of CSPRNG output,
--     so the hash has no meaningful preimage attack and no dictionary.
--
-- Everything the proof must be bound to is a column, and every one of them is
-- re-checked inside the single atomic UPDATE that consumes the row. There is no
-- read-then-write window anywhere in this file.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.wallet_nonces (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- sha256 hex of the plaintext challenge. UNIQUE so a hash collision or a
  -- duplicated insert can never produce two independently-consumable rows.
  nonce_hash        TEXT NOT NULL UNIQUE,

  -- The account this challenge was issued TO. A proof presented by any other
  -- account is rejected: a nonce is not a bearer token.
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- The address this challenge was issued FOR. Declared up front at issue time
  -- so the signer cannot swap in a different address at redemption.
  wallet_address    TEXT NOT NULL,

  -- What the proof authorises. A link_wallet nonce can never be redeemed as a
  -- transfer_wallet nonce.
  purpose           TEXT NOT NULL,

  -- SIWS binding fields. All three are validated against the server allowlist
  -- at issue time, and re-validated against the signed message at consume time.
  domain            TEXT NOT NULL,
  uri               TEXT NOT NULL,
  network           TEXT NOT NULL,

  issued_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at        TIMESTAMPTZ NOT NULL,
  consumed_at       TIMESTAMPTZ,

  -- Why a live nonce stopped being live without being redeemed: 'superseded'
  -- (a newer challenge replaced it) or 'revoked'. NULL for an ordinary redeem.
  -- Both set consumed_at, so both are terminal and neither is replayable.
  consumed_reason   TEXT,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT wallet_nonces_hash_shape        CHECK (nonce_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT wallet_nonces_purpose_check     CHECK (purpose IN ('link_wallet', 'transfer_wallet')),
  CONSTRAINT wallet_nonces_network_check     CHECK (network IN ('devnet', 'mainnet-beta')),
  CONSTRAINT wallet_nonces_address_not_empty CHECK (length(trim(wallet_address)) > 0),
  CONSTRAINT wallet_nonces_domain_not_empty  CHECK (length(trim(domain)) > 0),
  CONSTRAINT wallet_nonces_uri_not_empty     CHECK (length(trim(uri)) > 0),
  CONSTRAINT wallet_nonces_ttl_positive      CHECK (expires_at > issued_at),
  -- A short TTL is part of the security property, not a preference. 15 minutes
  -- is the ceiling; the issuing function defaults far below it.
  CONSTRAINT wallet_nonces_ttl_bounded       CHECK (expires_at <= issued_at + INTERVAL '15 minutes'),
  CONSTRAINT wallet_nonces_reason_check      CHECK (
    consumed_reason IS NULL OR consumed_reason IN ('redeemed', 'superseded', 'revoked')
  ),
  CONSTRAINT wallet_nonces_reason_needs_consumption CHECK (
    consumed_reason IS NULL OR consumed_at IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_wallet_nonces_user_id
  ON public.wallet_nonces (user_id);

-- The only hot path: "is there a live challenge for this user/address/purpose?"
CREATE INDEX IF NOT EXISTS idx_wallet_nonces_live
  ON public.wallet_nonces (user_id, wallet_address, purpose, expires_at)
  WHERE consumed_at IS NULL;

-- Drives the retention sweep.
CREATE INDEX IF NOT EXISTS idx_wallet_nonces_expires_at
  ON public.wallet_nonces (expires_at);

-- ── Mandatory default-deny template (contract §5) ───────────────────────────
-- No policy is added. A table with RLS enabled and zero policies denies every
-- row to every non-superuser role; service_role bypasses RLS. There is no
-- client read path to a challenge store and there must never be one.
ALTER TABLE public.wallet_nonces ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wallet_nonces FROM anon, authenticated;
GRANT ALL ON public.wallet_nonces TO service_role;

COMMENT ON TABLE public.wallet_nonces IS
  'Single-use SIWS challenges. Stores sha256(nonce) only — never the plaintext. Default-deny: no RLS policy exists, so only service_role (which bypasses RLS) can reach it. Consumed atomically by public.consume_wallet_nonce_v1.';
COMMENT ON COLUMN public.wallet_nonces.nonce_hash IS
  'sha256 of the challenge, 64 lowercase hex. The plaintext is never stored, logged, or returned.';

-- ---------------------------------------------------------------------------
-- issue_wallet_nonce_v1 — record a freshly-minted challenge.
-- ---------------------------------------------------------------------------
-- The caller (the BFF) generates the CSPRNG nonce and hashes it; only the hash
-- crosses this boundary. Issuing supersedes any still-live challenge for the
-- same (user, address, purpose) so at most one is redeemable at a time — a
-- second "link my wallet" tap cannot leave a stale challenge armed behind it.
--
-- Suffixed _v1 because contract §5 forbids CREATE OR REPLACE on an existing
-- function: a behaviour change here ships as _v2 beside this one, never as a
-- redefinition of it.
CREATE FUNCTION public.issue_wallet_nonce_v1(
  p_nonce_hash     TEXT,
  p_user_id        UUID,
  p_wallet_address TEXT,
  p_purpose        TEXT,
  p_domain         TEXT,
  p_uri            TEXT,
  p_network        TEXT,
  p_ttl_seconds    INTEGER DEFAULT 300
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_now        TIMESTAMPTZ := NOW();
  v_ttl        INTEGER;
  v_id         UUID;
  v_superseded INTEGER;
BEGIN
  -- Clamp rather than trust: 30s..900s, matching the CHECK ceiling.
  v_ttl := LEAST(GREATEST(COALESCE(p_ttl_seconds, 300), 30), 900);

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_user');
  END IF;

  -- The account must exist. A dangling FK error would surface as a 500; a
  -- clean reason keeps the BFF's error mapping honest.
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  UPDATE public.wallet_nonces n
     SET consumed_at     = v_now,
         consumed_reason = 'superseded'
   WHERE n.user_id        = p_user_id
     AND n.wallet_address = p_wallet_address
     AND n.purpose        = p_purpose
     AND n.consumed_at IS NULL;
  GET DIAGNOSTICS v_superseded = ROW_COUNT;

  INSERT INTO public.wallet_nonces (
    nonce_hash, user_id, wallet_address, purpose, domain, uri, network,
    issued_at, expires_at
  )
  VALUES (
    p_nonce_hash, p_user_id, p_wallet_address, p_purpose, p_domain, p_uri, p_network,
    v_now, v_now + make_interval(secs => v_ttl)
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'ok',          true,
    'nonce_id',    v_id,
    'issued_at',   v_now,
    'expires_at',  v_now + make_interval(secs => v_ttl),
    'superseded',  v_superseded
  );
END
$$;

REVOKE EXECUTE ON FUNCTION public.issue_wallet_nonce_v1(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.issue_wallet_nonce_v1(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER)
  TO service_role;

-- ---------------------------------------------------------------------------
-- consume_wallet_nonce_v1 — atomic single-use redemption.
-- ---------------------------------------------------------------------------
-- ONE `UPDATE ... WHERE consumed_at IS NULL ... RETURNING`. Every binding is in
-- the WHERE clause, so a mismatched proof simply fails to claim the row. There
-- is no SELECT-then-UPDATE, so two concurrent redemptions of the same challenge
-- cannot both succeed: the second finds consumed_at already set and matches
-- zero rows. Row-level locking inside a single UPDATE is what serialises this —
-- not an advisory lock, and not application code.
--
-- The diagnostic pass afterwards runs ONLY when nothing was claimed, and it
-- mutates nothing. It exists so the BFF can return a distinct, testable reason
-- instead of one opaque failure. That detail is not an oracle: this function is
-- service_role-only and the BFF decides what, if anything, reaches a client.
CREATE FUNCTION public.consume_wallet_nonce_v1(
  p_nonce_hash     TEXT,
  p_user_id        UUID,
  p_wallet_address TEXT,
  p_purpose        TEXT,
  p_domain         TEXT,
  p_uri            TEXT,
  p_network        TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_claimed public.wallet_nonces%ROWTYPE;
  v_row     public.wallet_nonces%ROWTYPE;
BEGIN
  UPDATE public.wallet_nonces n
     SET consumed_at     = NOW(),
         consumed_reason = 'redeemed'
   WHERE n.nonce_hash     = p_nonce_hash
     AND n.consumed_at   IS NULL
     AND n.expires_at     > NOW()
     AND n.user_id        = p_user_id
     AND n.wallet_address = p_wallet_address
     AND n.purpose        = p_purpose
     AND n.domain         = p_domain
     AND n.uri            = p_uri
     AND n.network        = p_network
  RETURNING n.* INTO v_claimed;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok',             true,
      'nonce_id',       v_claimed.id,
      'user_id',        v_claimed.user_id,
      'wallet_address', v_claimed.wallet_address,
      'purpose',        v_claimed.purpose,
      'issued_at',      v_claimed.issued_at
    );
  END IF;

  -- Nothing claimed. Work out why, without writing.
  SELECT * INTO v_row FROM public.wallet_nonces n WHERE n.nonce_hash = p_nonce_hash;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_unknown');
  ELSIF v_row.consumed_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_reused');
  ELSIF v_row.expires_at <= NOW() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_expired');
  ELSIF v_row.user_id IS DISTINCT FROM p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_user_mismatch');
  ELSIF v_row.wallet_address IS DISTINCT FROM p_wallet_address THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_address_mismatch');
  ELSIF v_row.purpose IS DISTINCT FROM p_purpose THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_purpose_mismatch');
  ELSIF v_row.domain IS DISTINCT FROM p_domain THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_domain_mismatch');
  ELSIF v_row.uri IS DISTINCT FROM p_uri THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_uri_mismatch');
  ELSIF v_row.network IS DISTINCT FROM p_network THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nonce_network_mismatch');
  END IF;

  -- Every binding matched and the row is live, yet the UPDATE claimed nothing:
  -- another transaction won the race between the UPDATE and this SELECT. That
  -- is a reuse by definition.
  RETURN jsonb_build_object('ok', false, 'reason', 'nonce_reused');
END
$$;

REVOKE EXECUTE ON FUNCTION public.consume_wallet_nonce_v1(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.consume_wallet_nonce_v1(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, TEXT)
  TO service_role;

-- ---------------------------------------------------------------------------
-- purge_wallet_nonces_v1 — retention sweep.
-- ---------------------------------------------------------------------------
-- A challenge past its expiry is terminal whether or not it was redeemed — it
-- can never be claimed again — so expiry alone is the retention key. Keeping
-- them beyond the grace window (default 7 days, so an incident still has a
-- trail) is pure liability surface.
CREATE FUNCTION public.purge_wallet_nonces_v1(p_grace_days INTEGER DEFAULT 7)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (contract §5)
AS $$
DECLARE
  v_deleted INTEGER;
  v_grace   INTEGER := LEAST(GREATEST(COALESCE(p_grace_days, 7), 1), 90);
BEGIN
  DELETE FROM public.wallet_nonces n
   WHERE n.expires_at < NOW() - make_interval(days => v_grace);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END
$$;

REVOKE EXECUTE ON FUNCTION public.purge_wallet_nonces_v1(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.purge_wallet_nonces_v1(INTEGER) TO service_role;
