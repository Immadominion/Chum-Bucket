-- One account, many sign-ins: deliberate linking and folding — additive.
--
-- A Chumbucket account is a public.users row. Supabase Auth gives every way in
-- its own auth.users row unless the ways in are linked onto one auth user:
-- automatically (a Google and an X identity with the same verified email), or
-- manually (supabase.auth.linkIdentity, Google/X only). Two cases cannot be
-- linked in Supabase Auth at all:
--
--   * a Solana wallet (Web3 sign-in). linkIdentity takes OAuth and OIDC
--     id-token providers only; a wallet sign-in always has its own auth user;
--   * an identity that already belongs to another auth user (linkIdentity
--     answers identity_already_exists).
--
-- So an account is now reached by its primary sign-in (users.auth_user_id,
-- unchanged) AND by any additional sign-in recorded here after the person
-- proved both sides:
--
--   account_sign_ins       an auth user that resolves to an account it is not
--                          the primary of. Three ways to get one:
--                            wallet   the wallet was linked to the account with
--                                     a SIWS proof (attach_verified_wallet_v1);
--                                     its first wallet sign-in lands here
--                            sign_in  a sign-in with no account, proven inside
--                                     a link ticket the account started
--                            fold     the sign-ins of an account folded into
--                                     this one
--   account_link_tickets   single-use, 10-minute capabilities an account issues
--                          to itself before the person proves the other side
--   account_folds          one row per folded account (append-only)
--   account_link_audit     every link, unlink and fold (append-only)
--
-- What a fold does, precisely (fold_account_into_v1). The account being
-- folded ("F") into the account the person is signed in to ("K"):
--
--   * moves:  every sign-in of F (its primary and its additional sign-ins)
--             becomes an additional sign-in of K; F's active linked wallets
--             move to K (wallet_link_audit 'transferred'); F's verified
--             users.wallet_address moves to K when K has none; F's push
--             tokens and legacy linked_identities move to K;
--   * copies: F's follows (both directions) and blocks/mutes (both
--             directions) are copied onto K, never onto K itself; F's own
--             rows stay;
--   * keeps:  every call, response, result, thesis update and receipt of F,
--             unchanged: same rows, same author, same timestamps. A call never
--             changes author (calls_guard_immutability); F's profile stays as
--             the record of those calls and is marked folded into K;
--   * refuses (nothing changes) when F has funded activity or money: a
--             funded call, a venue order or position, a Panta trade or claim
--             session, a market it paid to create, a legacy prediction
--             position, or an app-held wallet (embedded or any type other than
--             mwa/imported). Moving those across accounts is not guaranteed
--             lossless, so they are never moved;
--   * also refuses when F or K is deleted, F is already folded, or F is K.
--
-- Everything is service-role only (RLS on, zero policies). The BFF calls it
-- after verifying every session with GoTrue; it is switched off there unless
-- ACCOUNT_LINKING_ENABLED / ACCOUNT_FOLD_ENABLED say otherwise.
--
-- Additive in shape: four new tables, one new trigger on public.users (refuses
-- making an additional sign-in a primary one as well), new functions. No
-- existing table, column, grant, policy or function is altered or dropped.
--
-- Proven on a throwaway PostgreSQL 15 against the real identity chain
-- (chumbucket-social-calls-api tests/accountSignIns.postgres.test.ts).
--
-- Apply AFTER 20261002171000_lockdown_profiles_push_privacy.sql,
-- 20261002180000_trust_safety_and_account.sql and
-- 20261003200000_find_person_identities.sql.

DO $$
BEGIN
  IF to_regclass('auth.identities') IS NULL THEN
    RAISE EXCEPTION 'account_sign_ins expects Supabase Auth''s auth.identities table';
  END IF;
  IF to_regprocedure('public.bind_wallet_session_v1(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'account_sign_ins requires 20261002090000_wallet_sign_in_and_usernames.sql';
  END IF;
  IF to_regclass('public.wallet_link_audit') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'linked_wallets' AND column_name = 'verified_at') THEN
    RAISE EXCEPTION 'account_sign_ins requires 20260913121500_auth_identity_linked_wallets.sql';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'is_placeholder') THEN
    RAISE EXCEPTION 'account_sign_ins requires 20261002171000_lockdown_profiles_push_privacy.sql (users.is_placeholder)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'deleted_at') THEN
    RAISE EXCEPTION 'account_sign_ins requires 20261002180000_trust_safety_and_account.sql (users.deleted_at)';
  END IF;
  IF to_regprocedure('public.person_x_identities_v1(text,uuid[])') IS NULL THEN
    RAISE EXCEPTION 'account_sign_ins requires 20261003200000_find_person_identities.sql';
  END IF;
END;
$$;

-- ── additional sign-ins ─────────────────────────────────────────────────────

CREATE TABLE public.account_sign_ins (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  via            TEXT NOT NULL,
  -- For 'wallet': the linked wallet whose sign-in this is.
  wallet_address TEXT,
  -- For 'fold': the fold that moved it here.
  fold_id        UUID,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at     TIMESTAMPTZ,
  revoked_reason TEXT,
  CONSTRAINT account_sign_ins_via_check CHECK (via IN ('wallet', 'sign_in', 'fold')),
  CONSTRAINT account_sign_ins_wallet_shape CHECK (
    wallet_address IS NULL OR wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  CONSTRAINT account_sign_ins_wallet_needed CHECK (via <> 'wallet' OR wallet_address IS NOT NULL),
  CONSTRAINT account_sign_ins_fold_needed CHECK (via <> 'fold' OR fold_id IS NOT NULL),
  CONSTRAINT account_sign_ins_reason_check CHECK (
    revoked_reason IS NULL OR revoked_reason IN ('unlinked', 'folded')),
  CONSTRAINT account_sign_ins_revoked_shape CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
-- One sign-in reaches at most one account.
CREATE UNIQUE INDEX uq_account_sign_ins_active ON public.account_sign_ins (auth_user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX idx_account_sign_ins_user ON public.account_sign_ins (user_id)
  WHERE revoked_at IS NULL;
ALTER TABLE public.account_sign_ins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_sign_ins FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.account_sign_ins TO service_role;
COMMENT ON TABLE public.account_sign_ins IS
  'Additional Supabase sign-ins that reach an account they are not the primary of (users.auth_user_id). Only written by the definer functions of 20261004120000 after the BFF verified both sides. Revoked rows are history.';

-- A sign-in is a primary sign-in or an additional one, never both. Checked
-- here and in every function below; these two triggers are the backstop.
CREATE FUNCTION public.account_sign_ins_not_primary_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF NEW.revoked_at IS NULL
     AND EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = NEW.auth_user_id) THEN
    RAISE EXCEPTION 'this sign-in is already an account''s primary sign-in'
      USING ERRCODE = 'unique_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.account_sign_ins_not_primary_v1() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_account_sign_ins_not_primary
  BEFORE INSERT OR UPDATE ON public.account_sign_ins
  FOR EACH ROW EXECUTE FUNCTION public.account_sign_ins_not_primary_v1();

CREATE FUNCTION public.users_primary_not_additional_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF NEW.auth_user_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id)
     AND EXISTS (SELECT 1 FROM public.account_sign_ins s
                  WHERE s.auth_user_id = NEW.auth_user_id AND s.revoked_at IS NULL) THEN
    RAISE EXCEPTION 'this sign-in already reaches another account'
      USING ERRCODE = 'unique_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.users_primary_not_additional_v1() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_users_primary_not_additional
  BEFORE INSERT OR UPDATE OF auth_user_id ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.users_primary_not_additional_v1();

-- ── link tickets ────────────────────────────────────────────────────────────

CREATE TABLE public.account_link_tickets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- sha256 hex; the plaintext lives only with the client that asked for it.
  ticket_hash     TEXT NOT NULL UNIQUE,
  -- The account that started the link (it keeps everything)…
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- …and the verified sign-in it was started from.
  auth_user_id    UUID NOT NULL,
  -- How the other side will prove itself.
  method          TEXT NOT NULL,
  issued_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL,
  consumed_at     TIMESTAMPTZ,
  consumed_reason TEXT,
  CONSTRAINT account_link_tickets_hash_shape CHECK (ticket_hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT account_link_tickets_method_check CHECK (method IN ('wallet', 'x', 'google')),
  CONSTRAINT account_link_tickets_ttl CHECK (
    expires_at > issued_at AND expires_at <= issued_at + interval '15 minutes'),
  CONSTRAINT account_link_tickets_reason_check CHECK (
    consumed_reason IS NULL OR consumed_reason IN ('redeemed', 'superseded')),
  CONSTRAINT account_link_tickets_consumed_shape CHECK ((consumed_at IS NULL) = (consumed_reason IS NULL))
);
CREATE INDEX idx_account_link_tickets_user ON public.account_link_tickets (user_id, issued_at);
ALTER TABLE public.account_link_tickets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_link_tickets FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.account_link_tickets TO service_role;

-- ── folds and the audit trail (append-only) ─────────────────────────────────

CREATE TABLE public.account_folds (
  id                  UUID PRIMARY KEY,
  folded_user_id      UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE RESTRICT,
  into_user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- The sign-in the fold was started from (K's), and the one that proved F.
  keeper_auth_user_id UUID NOT NULL,
  proof_auth_user_id  UUID NOT NULL,
  method              TEXT NOT NULL,
  summary             JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT account_folds_not_self CHECK (folded_user_id <> into_user_id),
  CONSTRAINT account_folds_method_check CHECK (method IN ('wallet', 'x', 'google'))
);
CREATE INDEX idx_account_folds_into ON public.account_folds (into_user_id);
ALTER TABLE public.account_folds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_folds FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.account_folds TO service_role;
COMMENT ON TABLE public.account_folds IS
  'One row per account folded into another (fold_account_into_v1). The folded account keeps its calls and receipts unchanged; its sign-ins, wallets and devices moved to into_user_id. Append-only.';

CREATE TABLE public.account_link_audit (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action         TEXT NOT NULL,
  user_id        UUID REFERENCES public.users(id) ON DELETE SET NULL,
  other_user_id  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  auth_user_id   UUID,
  wallet_address TEXT,
  detail         JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT account_link_audit_action_check CHECK (
    action IN ('sign_in_linked', 'sign_in_unlinked', 'wallet_unlinked', 'folded'))
);
CREATE INDEX idx_account_link_audit_user ON public.account_link_audit (user_id, created_at DESC);
ALTER TABLE public.account_link_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_link_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.account_link_audit TO service_role;
COMMENT ON TABLE public.account_link_audit IS
  'Append-only trail of every additional sign-in linked or unlinked, wallet unlinked and account folded. Service role only.';

CREATE FUNCTION public.account_link_history_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'account link history is append-only';
END;
$$;
REVOKE ALL ON FUNCTION public.account_link_history_guard_v1() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER trg_account_folds_append_only BEFORE UPDATE OR DELETE ON public.account_folds
  FOR EACH ROW EXECUTE FUNCTION public.account_link_history_guard_v1();
CREATE TRIGGER trg_account_folds_no_truncate BEFORE TRUNCATE ON public.account_folds
  FOR EACH STATEMENT EXECUTE FUNCTION public.account_link_history_guard_v1();
CREATE TRIGGER trg_account_link_audit_append_only BEFORE UPDATE OR DELETE ON public.account_link_audit
  FOR EACH ROW EXECUTE FUNCTION public.account_link_history_guard_v1();
CREATE TRIGGER trg_account_link_audit_no_truncate BEFORE TRUNCATE ON public.account_link_audit
  FOR EACH STATEMENT EXECUTE FUNCTION public.account_link_history_guard_v1();

-- ── resolution ──────────────────────────────────────────────────────────────

-- The account a sign-in reaches: its primary account, else the account it is
-- an additional sign-in of. Never a deleted account. Internal.
CREATE FUNCTION public.account_for_auth_user_v1(p_auth_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT c.id FROM (
    SELECT u.id, 0 AS preference
      FROM public.users u
     WHERE u.auth_user_id = p_auth_user_id AND u.deleted_at IS NULL
    UNION ALL
    SELECT u.id, 1
      FROM public.account_sign_ins s
      JOIN public.users u ON u.id = s.user_id
     WHERE s.auth_user_id = p_auth_user_id AND s.revoked_at IS NULL AND u.deleted_at IS NULL
  ) c
  ORDER BY c.preference
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.account_for_auth_user_v1(UUID) FROM PUBLIC, anon, authenticated;

-- The wallet a Web3 identity of this auth user holds, if it holds that one.
CREATE FUNCTION public.auth_user_holds_wallet_v1(p_auth_user_id UUID, p_wallet TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.identities i
     WHERE i.user_id = p_auth_user_id
       AND i.provider = 'web3'
       AND (i.provider_id = 'web3:solana:' || p_wallet
            OR i.identity_data ->> 'sub' = 'web3:solana:' || p_wallet)
  );
$$;
REVOKE ALL ON FUNCTION public.auth_user_holds_wallet_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- The account holding a wallet through a PROVEN link: an active linked_wallets
-- row whose signature was verified, on a live account, AND the latest entry
-- of the service-only audit trail for that wallet names the same account.
-- The audit check is what makes a link written by the old client-writable
-- path (sync_user_by_wallet before 20261002171000 repointed rows without an
-- audit entry) count for nothing here. Internal.
CREATE FUNCTION public.proven_wallet_owner_v1(p_wallet TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT w.user_id
    FROM public.linked_wallets w
    JOIN public.users u ON u.id = w.user_id
   WHERE w.wallet_address = btrim(p_wallet)
     AND w.revoked_at IS NULL
     AND w.verified_at IS NOT NULL
     AND w.siws_proof_version IS NOT NULL
     AND u.deleted_at IS NULL
     AND (SELECT a.to_user_id FROM public.wallet_link_audit a
           WHERE a.wallet_address = w.wallet_address
             AND a.action IN ('linked', 'reaffirmed', 'transferred', 'revoked')
           ORDER BY a.created_at DESC, a.id DESC
           LIMIT 1) = w.user_id
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.proven_wallet_owner_v1(TEXT) FROM PUBLIC, anon, authenticated;

-- The account a wallet signs in to: the account of the auth user that holds
-- its Web3 identity, else its proven linked-wallet owner. Internal.
CREATE FUNCTION public.wallet_account_v1(p_wallet TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT coalesce(
    (SELECT public.account_for_auth_user_v1(i.user_id)
       FROM auth.identities i
      WHERE i.provider = 'web3'
        AND (i.provider_id = 'web3:solana:' || btrim(p_wallet)
             OR i.identity_data ->> 'sub' = 'web3:solana:' || btrim(p_wallet))
        AND public.account_for_auth_user_v1(i.user_id) IS NOT NULL
      LIMIT 1),
    public.proven_wallet_owner_v1(p_wallet));
$$;
REVOKE ALL ON FUNCTION public.wallet_account_v1(TEXT) FROM PUBLIC, anon, authenticated;

-- What the BFF asks when the primary lookup misses: the account an additional
-- sign-in reaches. {ok, user_id (null when none), via}.
CREATE FUNCTION public.resolve_auth_user_v1(p_auth_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user UUID;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  SELECT u.id INTO v_user FROM public.users u
   WHERE u.auth_user_id = p_auth_user_id AND u.deleted_at IS NULL;
  IF v_user IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'via', 'primary');
  END IF;
  SELECT s.user_id INTO v_user
    FROM public.account_sign_ins s JOIN public.users u ON u.id = s.user_id
   WHERE s.auth_user_id = p_auth_user_id AND s.revoked_at IS NULL AND u.deleted_at IS NULL;
  RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'via', CASE WHEN v_user IS NULL THEN NULL ELSE 'additional' END);
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_auth_user_v1(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_auth_user_v1(UUID) TO service_role;

-- ── a wallet sign-in lands on the account the wallet was linked to ──────────
--
-- Called for a Web3 session whose auth user reaches no account. The wallet is
-- re-checked against the auth user's own Web3 identity (the BFF read it from
-- GoTrue; this does not trust the BFF's copy either). An account with no
-- primary sign-in is left to bind_wallet_session_v1, which carries legacy
-- wallet profiles behind its own gate.
CREATE FUNCTION public.resolve_wallet_sign_in_v1(p_auth_user_id UUID, p_wallet_address TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_wallet  TEXT := nullif(btrim(coalesce(p_wallet_address, '')), '');
  v_user    UUID;
  v_owner   UUID;
  v_primary UUID;
BEGIN
  IF p_auth_user_id IS NULL OR v_wallet IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-sign-in:' || p_auth_user_id::text, 0));

  v_user := public.account_for_auth_user_v1(p_auth_user_id);
  IF v_user IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'outcome', 'existing');
  END IF;
  IF NOT public.auth_user_holds_wallet_v1(p_auth_user_id, v_wallet) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_this_wallet');
  END IF;
  -- A primary sign-in that was released (a deleted account) is not reused.
  IF EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = p_auth_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'owned');
  END IF;

  v_owner := public.proven_wallet_owner_v1(v_wallet);
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_link');
  END IF;
  SELECT u.auth_user_id INTO v_primary FROM public.users u WHERE u.id = v_owner FOR SHARE;
  IF v_primary IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_primary');
  END IF;

  BEGIN
    INSERT INTO public.account_sign_ins (auth_user_id, user_id, via, wallet_address)
    VALUES (p_auth_user_id, v_owner, 'wallet', v_wallet);
  EXCEPTION WHEN unique_violation THEN
    v_user := public.account_for_auth_user_v1(p_auth_user_id);
    IF v_user IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'outcome', 'existing');
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'link_contention');
  END;
  INSERT INTO public.account_link_audit (action, user_id, auth_user_id, wallet_address, detail)
  VALUES ('sign_in_linked', v_owner, p_auth_user_id, v_wallet,
          jsonb_build_object('via', 'wallet', 'reason', 'first sign-in of a linked wallet'));
  RETURN jsonb_build_object('ok', true, 'user_id', v_owner, 'outcome', 'linked');
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_wallet_sign_in_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_wallet_sign_in_v1(UUID, TEXT) TO service_role;
COMMENT ON FUNCTION public.resolve_wallet_sign_in_v1(UUID, TEXT) IS
  'Service-only: a Web3 sign-in with no account lands on the live account its wallet was linked to with a verified signature (and whose audit trail agrees), as an additional sign-in. Never for an account with no primary sign-in (bind_wallet_session_v1 handles those).';

-- The account a wallet already signs in to, other than p_user_id. The BFF
-- checks this before linking a wallet, so a wallet never ends up linked to
-- one account while it signs in to another.
CREATE FUNCTION public.wallet_sign_in_conflict_v1(p_user_id UUID, p_wallet_address TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT coalesce(public.wallet_account_v1(p_wallet_address) <> p_user_id, false);
$$;
REVOKE ALL ON FUNCTION public.wallet_sign_in_conflict_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_sign_in_conflict_v1(UUID, TEXT) TO service_role;

-- ── the account's sign-in methods ───────────────────────────────────────────
--
-- Every sign-in that reaches the account with its identities (provider, the
-- handle/email/address to show, when it was last used), and its verified
-- linked wallets. For the account's own Settings only: the BFF calls it with
-- the id it resolved from the verified session.
CREATE FUNCTION public.account_sign_ins_v1(p_user_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  WITH s AS (
    SELECT u.auth_user_id, true AS is_primary, NULL::uuid AS sign_in_id, 'primary'::text AS via, 0 AS ord,
           u.created_at AS since
      FROM public.users u
     WHERE u.id = p_user_id AND u.auth_user_id IS NOT NULL AND u.deleted_at IS NULL
    UNION ALL
    SELECT a.auth_user_id, false, a.id, a.via, 1, a.created_at
      FROM public.account_sign_ins a
      JOIN public.users u ON u.id = a.user_id
     WHERE a.user_id = p_user_id AND a.revoked_at IS NULL AND u.deleted_at IS NULL
  )
  SELECT jsonb_build_object(
    'ok', true,
    'sign_ins', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'auth_user_id', s.auth_user_id,
               'primary', s.is_primary,
               'sign_in_id', s.sign_in_id,
               'via', s.via,
               'identities', coalesce((
                 SELECT jsonb_agg(jsonb_build_object(
                          'identity_id', i.id,
                          'provider', i.provider,
                          'label', CASE
                            WHEN i.provider IN ('x', 'twitter') THEN
                              coalesce(nullif(btrim(i.identity_data ->> 'user_name'), ''),
                                       nullif(btrim(i.identity_data ->> 'preferred_username'), ''),
                                       nullif(btrim(i.identity_data ->> 'screen_name'), ''))
                            WHEN i.provider = 'google' THEN
                              nullif(btrim(i.identity_data ->> 'email'), '')
                            WHEN i.provider = 'web3' THEN
                              coalesce(substring(i.provider_id FROM '^web3:solana:(.+)$'),
                                       substring(i.identity_data ->> 'sub' FROM '^web3:solana:(.+)$'))
                            ELSE NULL END,
                          'last_sign_in_at', i.last_sign_in_at)
                        ORDER BY i.created_at)
                   FROM auth.identities i
                  WHERE i.user_id = s.auth_user_id), '[]'::jsonb))
             ORDER BY s.ord, s.since)
        FROM s), '[]'::jsonb),
    'wallets', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'address', w.wallet_address,
               'wallet_type', w.wallet_type,
               'is_primary', w.is_primary)
             ORDER BY w.is_primary DESC, w.created_at)
        FROM public.linked_wallets w
       WHERE w.user_id = p_user_id AND w.revoked_at IS NULL AND w.verified_at IS NOT NULL), '[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.account_sign_ins_v1(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.account_sign_ins_v1(UUID) TO service_role;

-- ── unlink ──────────────────────────────────────────────────────────────────
--
-- Exactly one of p_sign_in_id (an additional sign-in) or p_wallet (a linked
-- wallet). Never the sign-in the request was made with, never the account's
-- primary sign-in or its Web3 wallet: so the account always keeps at least the
-- way the person is signed in right now, and the last method can never go.
-- A wallet and its own sign-ins go together, or the wallet would land here
-- again at its next sign-in.
CREATE FUNCTION public.unlink_sign_in_v1(
  p_user_id                 UUID,
  p_session_auth_user_id    UUID,
  p_sign_in_id              UUID DEFAULT NULL,
  p_wallet                  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_primary  UUID;
  v_auths    UUID[] := ARRAY[]::UUID[];
  v_wallets  TEXT[] := ARRAY[]::TEXT[];
  v_n        INTEGER;
  v_wallet   TEXT := nullif(btrim(coalesce(p_wallet, '')), '');
BEGIN
  IF p_user_id IS NULL OR p_session_auth_user_id IS NULL
     OR (p_sign_in_id IS NULL) = (v_wallet IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  SELECT u.auth_user_id INTO v_primary FROM public.users u
   WHERE u.id = p_user_id AND u.deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;
  IF public.account_for_auth_user_v1(p_session_auth_user_id) IS DISTINCT FROM p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_mismatch');
  END IF;

  IF p_sign_in_id IS NOT NULL THEN
    SELECT array_agg(s.auth_user_id) INTO v_auths FROM public.account_sign_ins s
     WHERE s.id = p_sign_in_id AND s.user_id = p_user_id AND s.revoked_at IS NULL;
    IF v_auths IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
    END IF;
    -- The wallets this sign-in signs in with, when they are linked here.
    SELECT coalesce(array_agg(w.wallet_address), ARRAY[]::TEXT[]) INTO v_wallets
      FROM public.linked_wallets w
     WHERE w.user_id = p_user_id AND w.revoked_at IS NULL
       AND public.auth_user_holds_wallet_v1(v_auths[1], w.wallet_address);
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.linked_wallets w
                    WHERE w.user_id = p_user_id AND w.wallet_address = v_wallet AND w.revoked_at IS NULL) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_found');
    END IF;
    v_wallets := ARRAY[v_wallet];
    SELECT coalesce(array_agg(s.auth_user_id), ARRAY[]::UUID[]) INTO v_auths
      FROM public.account_sign_ins s
     WHERE s.user_id = p_user_id AND s.revoked_at IS NULL
       AND (s.wallet_address = v_wallet OR public.auth_user_holds_wallet_v1(s.auth_user_id, v_wallet));
  END IF;

  IF p_session_auth_user_id = ANY (v_auths)
     OR EXISTS (SELECT 1 FROM unnest(v_wallets) x(w)
                 WHERE public.auth_user_holds_wallet_v1(p_session_auth_user_id, x.w)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'current_sign_in');
  END IF;
  IF v_primary IS NOT NULL AND EXISTS (SELECT 1 FROM unnest(v_wallets) x(w)
                                        WHERE public.auth_user_holds_wallet_v1(v_primary, x.w)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'primary_sign_in');
  END IF;

  UPDATE public.account_sign_ins
     SET revoked_at = now(), revoked_reason = 'unlinked'
   WHERE user_id = p_user_id AND revoked_at IS NULL AND auth_user_id = ANY (v_auths);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO public.account_link_audit (action, user_id, auth_user_id)
  SELECT 'sign_in_unlinked', p_user_id, a FROM unnest(v_auths) a;

  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, actor, reason)
  SELECT w.wallet_address, 'revoked', p_user_id, 'service', 'unlinked in settings'
    FROM public.linked_wallets w
   WHERE w.user_id = p_user_id AND w.revoked_at IS NULL AND w.wallet_address = ANY (v_wallets);
  UPDATE public.linked_wallets
     SET revoked_at = now(), updated_at = now()
   WHERE user_id = p_user_id AND revoked_at IS NULL AND wallet_address = ANY (v_wallets);
  INSERT INTO public.account_link_audit (action, user_id, wallet_address)
  SELECT 'wallet_unlinked', p_user_id, w FROM unnest(v_wallets) w;

  RETURN jsonb_build_object('ok', true, 'outcome', 'unlinked',
    'sign_ins', v_n, 'wallets', cardinality(v_wallets));
END;
$$;
REVOKE ALL ON FUNCTION public.unlink_sign_in_v1(UUID, UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unlink_sign_in_v1(UUID, UUID, UUID, TEXT) TO service_role;

-- ── link tickets ────────────────────────────────────────────────────────────

CREATE FUNCTION public.issue_account_link_ticket_v1(
  p_user_id      UUID,
  p_auth_user_id UUID,
  p_method       TEXT,
  p_ticket_hash  TEXT,
  p_ttl_seconds  INTEGER DEFAULT 600
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_now     TIMESTAMPTZ := clock_timestamp();
  v_expires TIMESTAMPTZ;
BEGIN
  IF p_user_id IS NULL OR p_auth_user_id IS NULL OR p_ticket_hash IS NULL
     OR p_ticket_hash !~ '^[0-9a-f]{64}$' OR p_method NOT IN ('wallet', 'x', 'google') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-link-ticket:' || p_user_id::text, 0));
  IF public.account_for_auth_user_v1(p_auth_user_id) IS DISTINCT FROM p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_mismatch');
  END IF;
  IF (SELECT count(*) FROM public.account_link_tickets
       WHERE user_id = p_user_id AND issued_at > v_now - interval '1 minute') >= 10 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
  END IF;
  UPDATE public.account_link_tickets SET consumed_at = v_now, consumed_reason = 'superseded'
   WHERE user_id = p_user_id AND consumed_at IS NULL;
  v_expires := v_now + make_interval(secs => least(greatest(coalesce(p_ttl_seconds, 600), 60), 900));
  INSERT INTO public.account_link_tickets (ticket_hash, user_id, auth_user_id, method, issued_at, expires_at)
  VALUES (p_ticket_hash, p_user_id, p_auth_user_id, p_method, v_now, v_expires);
  RETURN jsonb_build_object('ok', true, 'expires_at', v_expires);
END;
$$;
REVOKE ALL ON FUNCTION public.issue_account_link_ticket_v1(UUID, UUID, TEXT, TEXT, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_account_link_ticket_v1(UUID, UUID, TEXT, TEXT, INTEGER) TO service_role;

-- Funded activity or money on an account: the first kind found, or NULL.
-- Every table is optional (a project that never had it has nothing in it).
CREATE FUNCTION public.account_money_activity_v1(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_found BOOLEAN;
  v_check RECORD;
BEGIN
  FOR v_check IN
    SELECT * FROM (VALUES
      ('funded_call',        'calls',                    'user_id',      'funding_state <> ''NONE'''),
      ('venue_order',        'venue_orders',             'user_id',      'true'),
      ('venue_position',     'venue_positions',          'user_id',      'true'),
      ('panta_trade',        'panta_trade_sessions',     'user_id',      'true'),
      ('panta_claim',        'panta_claim_sessions',     'user_id',      'true'),
      ('market_creation',    'market_creation_sessions', 'publisher_id', 'true'),
      ('prediction_position','prediction_positions',     'user_id',      'true'),
      ('app_wallet',         'linked_wallets',           'user_id',      'revoked_at IS NULL AND wallet_type NOT IN (''mwa'', ''imported'')')
    ) AS t(kind, tbl, col, cond)
  LOOP
    IF to_regclass('public.' || v_check.tbl) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE %I = $1 AND %s)',
                   v_check.tbl, v_check.col, v_check.cond)
      INTO v_found USING p_user_id;
    IF v_found THEN RETURN v_check.kind; END IF;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.account_money_activity_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Does this auth user hold an identity for the ticket's method?
CREATE FUNCTION public.auth_user_has_method_v1(p_auth_user_id UUID, p_method TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.identities i
     WHERE i.user_id = p_auth_user_id
       AND i.provider = ANY (CASE p_method
                               WHEN 'x' THEN ARRAY['x', 'twitter']
                               WHEN 'google' THEN ARRAY['google']
                               WHEN 'wallet' THEN ARRAY['web3']
                               ELSE ARRAY[]::TEXT[] END));
$$;
REVOKE ALL ON FUNCTION public.auth_user_has_method_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- The account the proving sign-in reaches, including through its wallet: an
-- auth user with no account yet whose Web3 wallet is linked somewhere reaches
-- that account (exactly as its next sign-in would).
CREATE FUNCTION public.proving_account_v1(p_auth_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT coalesce(
    public.account_for_auth_user_v1(p_auth_user_id),
    (SELECT public.proven_wallet_owner_v1(coalesce(substring(i.provider_id FROM '^web3:solana:(.+)$'),
                                                   substring(i.identity_data ->> 'sub' FROM '^web3:solana:(.+)$')))
       FROM auth.identities i
      WHERE i.user_id = p_auth_user_id AND i.provider = 'web3'
        AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = p_auth_user_id)
      LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.proving_account_v1(UUID) FROM PUBLIC, anon, authenticated;

-- What completing a ticket with this sign-in would do. Reads only.
--   outcome  'already'  the sign-in already reaches the ticket's account
--            'link'     a sign-in with no account becomes an additional one
--            'fold'     the sign-in's account would be folded in
--   refusal  why it cannot, when it cannot
CREATE FUNCTION public.preview_account_link_v1(p_ticket_hash TEXT, p_auth_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_ticket public.account_link_tickets%ROWTYPE;
  v_other  UUID;
  v_money  TEXT;
  v_refusal TEXT;
BEGIN
  SELECT * INTO v_ticket FROM public.account_link_tickets WHERE ticket_hash = p_ticket_hash;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown'); END IF;
  IF v_ticket.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_used'); END IF;
  IF v_ticket.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_expired'); END IF;
  IF p_auth_user_id IS NULL OR NOT public.auth_user_has_method_v1(p_auth_user_id, v_ticket.method) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'method_mismatch');
  END IF;
  IF EXISTS (SELECT 1 FROM public.users u WHERE u.id = v_ticket.user_id AND u.deleted_at IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.account_folds f WHERE f.folded_user_id = v_ticket.user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown');
  END IF;

  v_other := public.proving_account_v1(p_auth_user_id);
  IF v_other = v_ticket.user_id THEN
    RETURN jsonb_build_object('ok', true, 'outcome', 'already', 'into_user_id', v_ticket.user_id,
                              'other_user_id', v_other, 'method', v_ticket.method);
  END IF;
  IF v_other IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'outcome', 'link', 'into_user_id', v_ticket.user_id,
                              'other_user_id', NULL, 'method', v_ticket.method);
  END IF;
  v_money := public.account_money_activity_v1(v_other);
  v_refusal := CASE WHEN v_money IS NOT NULL THEN 'has_money' END;
  RETURN jsonb_build_object('ok', true, 'outcome', 'fold', 'into_user_id', v_ticket.user_id,
                            'other_user_id', v_other, 'method', v_ticket.method,
                            'refusal', v_refusal, 'money', v_money);
END;
$$;
REVOKE ALL ON FUNCTION public.preview_account_link_v1(TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.preview_account_link_v1(TEXT, UUID) TO service_role;

-- ── the fold ────────────────────────────────────────────────────────────────
--
-- Internal: called only by complete_account_link_v1, inside its transaction,
-- with both rows locked. See the header for exactly what moves, what is
-- copied and what stays.
CREATE FUNCTION public.fold_account_into_v1(
  p_into_user_id   UUID,
  p_folded_user_id UUID,
  p_keeper_auth    UUID,
  p_proof_auth     UUID,
  p_method         TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_fold     UUID := gen_random_uuid();
  v_primary  UUID;
  v_k_wallet TEXT;
  v_f_wallet TEXT;
  v_moved    TEXT[];
  v_signins  UUID[] := ARRAY[]::UUID[];
  v_old      JSONB;
  v_follows  JSONB;
  v_n        INTEGER;
  v_summary  JSONB := '{}'::jsonb;
  v_money    TEXT;
BEGIN
  IF p_into_user_id = p_folded_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'same_account');
  END IF;
  -- Both rows, in a fixed order: two folds in opposite directions cannot deadlock.
  PERFORM 1 FROM public.users WHERE id IN (p_into_user_id, p_folded_user_id) ORDER BY id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.users WHERE id IN (p_into_user_id, p_folded_user_id) AND deleted_at IS NOT NULL)
     OR (SELECT count(*) FROM public.users WHERE id IN (p_into_user_id, p_folded_user_id)) <> 2 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;
  IF EXISTS (SELECT 1 FROM public.account_folds
              WHERE folded_user_id IN (p_into_user_id, p_folded_user_id)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_folded');
  END IF;
  v_money := public.account_money_activity_v1(p_folded_user_id);
  IF v_money IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'has_money', 'money', v_money);
  END IF;

  -- 1. Sign-ins. The folded account's primary becomes an additional sign-in
  --    here (its row is released first: a sign-in is never both), then each
  --    of its additional sign-ins is re-issued here and the old row revoked.
  SELECT auth_user_id, wallet_address INTO v_primary, v_f_wallet FROM public.users WHERE id = p_folded_user_id;
  SELECT wallet_address INTO v_k_wallet FROM public.users WHERE id = p_into_user_id;
  UPDATE public.users SET auth_user_id = NULL, updated_at = now() WHERE id = p_folded_user_id;
  IF v_primary IS NOT NULL THEN
    INSERT INTO public.account_sign_ins (auth_user_id, user_id, via, fold_id)
    VALUES (v_primary, p_into_user_id, 'fold', v_fold);
    v_signins := v_signins || v_primary;
  END IF;
  -- Revoke, then re-issue, as two statements: the one-active-row index must
  -- see the old row gone before the new one arrives.
  WITH moved AS (
    UPDATE public.account_sign_ins
       SET revoked_at = now(), revoked_reason = 'folded'
     WHERE user_id = p_folded_user_id AND revoked_at IS NULL
    RETURNING auth_user_id, via, wallet_address
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('a', auth_user_id, 'v', via, 'w', wallet_address)), '[]'::jsonb)
    INTO v_old FROM moved;
  WITH reissued AS (
    INSERT INTO public.account_sign_ins (auth_user_id, user_id, via, wallet_address, fold_id)
    SELECT (e ->> 'a')::uuid, p_into_user_id, CASE WHEN e ->> 'v' = 'wallet' THEN 'wallet' ELSE 'fold' END,
           e ->> 'w', v_fold
      FROM jsonb_array_elements(v_old) e
    RETURNING auth_user_id
  )
  SELECT v_signins || coalesce(array_agg(auth_user_id), ARRAY[]::UUID[]) INTO v_signins FROM reissued;
  -- The sign-in that proved the folded account, when it had none of its own
  -- (a wallet that was linked to it but had never signed in).
  IF p_proof_auth IS NOT NULL AND NOT (p_proof_auth = ANY (v_signins))
     AND public.account_for_auth_user_v1(p_proof_auth) IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = p_proof_auth) THEN
    INSERT INTO public.account_sign_ins (auth_user_id, user_id, via, fold_id)
    VALUES (p_proof_auth, p_into_user_id, 'fold', v_fold);
    v_signins := v_signins || p_proof_auth;
  END IF;
  v_summary := v_summary || jsonb_build_object('sign_ins', to_jsonb(v_signins));

  -- 2. Wallets: an audited transfer each, keeping the proof that linked them.
  WITH moved AS (
    UPDATE public.linked_wallets
       SET user_id = p_into_user_id, is_primary = false, updated_at = now()
     WHERE user_id = p_folded_user_id AND revoked_at IS NULL
    RETURNING wallet_address
  )
  SELECT coalesce(array_agg(wallet_address), ARRAY[]::TEXT[]) INTO v_moved FROM moved;
  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, to_user_id, actor, reason)
  SELECT w, 'transferred', p_folded_user_id, p_into_user_id, 'service', 'account folded'
    FROM unnest(v_moved) w;
  -- The legacy column follows a wallet that moved, when there is room for it.
  IF v_f_wallet IS NOT NULL AND v_f_wallet = ANY (v_moved) THEN
    UPDATE public.users SET wallet_address = NULL, updated_at = now() WHERE id = p_folded_user_id;
    IF v_k_wallet IS NULL THEN
      UPDATE public.users SET wallet_address = v_f_wallet, updated_at = now() WHERE id = p_into_user_id;
    END IF;
  END IF;
  v_summary := v_summary || jsonb_build_object('wallets', to_jsonb(v_moved));

  -- 3. Follows, both directions, copied (never onto the account itself).
  IF to_regclass('public.person_follows') IS NOT NULL THEN
    WITH added AS (
      INSERT INTO public.person_follows (follower_user_id, followee_user_id)
      SELECT p_into_user_id, f.followee_user_id FROM public.person_follows f
       WHERE f.follower_user_id = p_folded_user_id AND f.followee_user_id <> p_into_user_id
      UNION
      SELECT f.follower_user_id, p_into_user_id FROM public.person_follows f
       WHERE f.followee_user_id = p_folded_user_id AND f.follower_user_id <> p_into_user_id
      ON CONFLICT DO NOTHING
      RETURNING follower_user_id, followee_user_id
    )
    SELECT coalesce(jsonb_agg(jsonb_build_array(follower_user_id, followee_user_id)), '[]'::jsonb)
      INTO v_follows FROM added;
  END IF;
  v_summary := v_summary || jsonb_build_object('follows', coalesce(v_follows, '[]'::jsonb));

  -- 4. Blocks and mutes, both directions, copied: someone who blocked the
  --    folded account is shielded from the person in their new account too.
  IF to_regclass('public.user_blocks') IS NOT NULL THEN
    INSERT INTO public.user_blocks (blocker_user_id, blocked_user_id)
    SELECT p_into_user_id, b.blocked_user_id FROM public.user_blocks b
     WHERE b.blocker_user_id = p_folded_user_id AND b.blocked_user_id <> p_into_user_id
    UNION
    SELECT b.blocker_user_id, p_into_user_id FROM public.user_blocks b
     WHERE b.blocked_user_id = p_folded_user_id AND b.blocker_user_id <> p_into_user_id
    ON CONFLICT DO NOTHING;
  END IF;
  IF to_regclass('public.user_mutes') IS NOT NULL THEN
    INSERT INTO public.user_mutes (muter_user_id, muted_user_id)
    SELECT p_into_user_id, m.muted_user_id FROM public.user_mutes m
     WHERE m.muter_user_id = p_folded_user_id AND m.muted_user_id <> p_into_user_id
    UNION
    SELECT m.muter_user_id, p_into_user_id FROM public.user_mutes m
     WHERE m.muted_user_id = p_folded_user_id AND m.muter_user_id <> p_into_user_id
    ON CONFLICT DO NOTHING;
  END IF;

  -- 5. Devices and the old linked-identity mirror move with the person.
  IF to_regclass('public.push_tokens') IS NOT NULL THEN
    UPDATE public.push_tokens SET user_id = p_into_user_id, updated_at = now() WHERE user_id = p_folded_user_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_summary := v_summary || jsonb_build_object('push_tokens', v_n);
  END IF;
  IF to_regclass('public.linked_identities') IS NOT NULL THEN
    UPDATE public.linked_identities SET user_id = p_into_user_id WHERE user_id = p_folded_user_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_summary := v_summary || jsonb_build_object('linked_identities', v_n);
  END IF;

  -- 6. What stays: the calls (and with them responses, results, receipts).
  IF to_regclass('public.calls') IS NOT NULL THEN
    SELECT count(*) INTO v_n FROM public.calls WHERE user_id = p_folded_user_id;
    v_summary := v_summary || jsonb_build_object('calls_kept', v_n);
  END IF;

  INSERT INTO public.account_folds (id, folded_user_id, into_user_id, keeper_auth_user_id,
                                    proof_auth_user_id, method, summary)
  VALUES (v_fold, p_folded_user_id, p_into_user_id, p_keeper_auth, p_proof_auth, p_method,
          v_summary - 'follows');
  INSERT INTO public.account_link_audit (action, user_id, other_user_id, auth_user_id, detail)
  VALUES ('folded', p_into_user_id, p_folded_user_id, p_proof_auth,
          jsonb_build_object('fold_id', v_fold, 'method', p_method, 'keeper_auth_user_id', p_keeper_auth)
            || (v_summary - 'follows'));

  RETURN jsonb_build_object('ok', true, 'outcome', 'folded', 'fold_id', v_fold,
                            'user_id', p_into_user_id, 'folded_user_id', p_folded_user_id,
                            'summary', v_summary);
END;
$$;
REVOKE ALL ON FUNCTION public.fold_account_into_v1(UUID, UUID, UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- Complete a ticket with the sign-in that proves the other side. Consumes the
-- ticket only when something happens (or nothing needed to); a refusal leaves
-- it for a retry until it expires. p_allow_link / p_allow_fold are the BFF's
-- switches, read inside the same transaction as the state they gate.
CREATE FUNCTION public.complete_account_link_v1(
  p_ticket_hash  TEXT,
  p_auth_user_id UUID,
  p_allow_link   BOOLEAN DEFAULT false,
  p_allow_fold   BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_ticket public.account_link_tickets%ROWTYPE;
  v_other  UUID;
  v_result JSONB;
BEGIN
  IF p_auth_user_id IS NULL OR p_ticket_hash IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-sign-in:' || p_auth_user_id::text, 0));
  SELECT * INTO v_ticket FROM public.account_link_tickets WHERE ticket_hash = p_ticket_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown'); END IF;
  IF v_ticket.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_used'); END IF;
  IF v_ticket.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_expired'); END IF;
  IF NOT public.auth_user_has_method_v1(p_auth_user_id, v_ticket.method) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'method_mismatch');
  END IF;
  IF EXISTS (SELECT 1 FROM public.users u WHERE u.id = v_ticket.user_id AND u.deleted_at IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.account_folds f WHERE f.folded_user_id = v_ticket.user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown');
  END IF;

  v_other := public.proving_account_v1(p_auth_user_id);
  IF v_other = v_ticket.user_id THEN
    v_result := jsonb_build_object('ok', true, 'outcome', 'already', 'user_id', v_ticket.user_id);
  ELSIF v_other IS NULL THEN
    IF NOT coalesce(p_allow_link, false) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'linking_disabled');
    END IF;
    IF EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = p_auth_user_id) THEN
      -- The primary sign-in of a deleted account: never reused.
      RETURN jsonb_build_object('ok', false, 'reason', 'owned');
    END IF;
    INSERT INTO public.account_sign_ins (auth_user_id, user_id, via)
    VALUES (p_auth_user_id, v_ticket.user_id, 'sign_in');
    INSERT INTO public.account_link_audit (action, user_id, auth_user_id, detail)
    VALUES ('sign_in_linked', v_ticket.user_id, p_auth_user_id,
            jsonb_build_object('via', 'sign_in', 'method', v_ticket.method,
                               'keeper_auth_user_id', v_ticket.auth_user_id));
    v_result := jsonb_build_object('ok', true, 'outcome', 'linked', 'user_id', v_ticket.user_id);
  ELSE
    IF NOT coalesce(p_allow_fold, false) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'fold_disabled');
    END IF;
    v_result := public.fold_account_into_v1(v_ticket.user_id, v_other, v_ticket.auth_user_id,
                                            p_auth_user_id, v_ticket.method);
    IF NOT (v_result ->> 'ok')::boolean THEN
      RETURN v_result;
    END IF;
  END IF;

  UPDATE public.account_link_tickets SET consumed_at = clock_timestamp(), consumed_reason = 'redeemed'
   WHERE id = v_ticket.id;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN) TO service_role;
COMMENT ON FUNCTION public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN) IS
  'Service-only: completes a link ticket an account issued itself, with a GoTrue-verified sign-in for the other side. Already the same account: nothing. A sign-in with no account: an additional sign-in (when linking is on). Another account: folded in (when folding is on), unless it has funded activity or money. Audited.';

-- ── X identities, including additional sign-ins ─────────────────────────────
--
-- person_x_identities_v1 with one change: an X identity on an additional
-- sign-in counts for the account it reaches (after a fold, the folded
-- account's X is the surviving account's X). Same shape, same rules.
CREATE FUNCTION public.person_x_identities_v2(
  p_x_handle TEXT DEFAULT NULL,
  p_user_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (user_id UUID, x_username TEXT, x_avatar_url TEXT, seen_at TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  WITH wanted AS (
    SELECT lower(ltrim(btrim(p_x_handle), '@')) AS handle
     WHERE p_x_handle IS NOT NULL AND p_user_ids IS NULL
       AND lower(ltrim(btrim(p_x_handle), '@')) ~ '^[a-z0-9_]{1,15}$'
    UNION ALL
    SELECT NULL
     WHERE p_x_handle IS NULL AND p_user_ids IS NOT NULL
       AND cardinality(p_user_ids) BETWEEN 1 AND 50
  ),
  reach AS (
    SELECT u.auth_user_id, u.id AS user_id FROM public.users u
     WHERE u.auth_user_id IS NOT NULL AND u.deleted_at IS NULL AND NOT u.is_placeholder
    UNION ALL
    SELECT s.auth_user_id, u.id FROM public.account_sign_ins s
      JOIN public.users u ON u.id = s.user_id
     WHERE s.revoked_at IS NULL AND u.deleted_at IS NULL AND NOT u.is_placeholder
  ),
  x AS (
    SELECT r.user_id,
           coalesce(nullif(btrim(i.identity_data ->> 'user_name'), ''),
                    nullif(btrim(i.identity_data ->> 'preferred_username'), ''),
                    nullif(btrim(i.identity_data ->> 'screen_name'), '')) AS x_username,
           coalesce(nullif(btrim(i.identity_data ->> 'avatar_url'), ''),
                    nullif(btrim(i.identity_data ->> 'picture'), '')) AS x_avatar_url,
           coalesce(i.last_sign_in_at, i.updated_at, i.created_at) AS seen_at
      FROM auth.identities i
      JOIN reach r ON r.auth_user_id = i.user_id
     WHERE i.provider IN ('x', 'twitter')
       AND (p_user_ids IS NULL OR r.user_id = ANY (p_user_ids))
    UNION ALL
    SELECT u.id,
           nullif(btrim(li.provider_username), ''),
           nullif(btrim(li.provider_avatar_url), ''),
           coalesce(li.verified_at, li.updated_at)
      FROM public.linked_identities li
      JOIN public.users u ON u.id = li.user_id
     WHERE li.provider IN ('x', 'twitter')
       AND u.deleted_at IS NULL
       AND NOT u.is_placeholder
       AND (p_user_ids IS NULL OR u.id = ANY (p_user_ids))
  ),
  matched AS (
    SELECT DISTINCT ON (x.user_id)
           x.user_id, ltrim(x.x_username, '@') AS x_username, x.x_avatar_url, x.seen_at
      FROM x
      JOIN wanted w ON w.handle IS NULL OR lower(ltrim(x.x_username, '@')) = w.handle
     WHERE x.x_username IS NOT NULL
     ORDER BY x.user_id, x.seen_at DESC NULLS LAST
  )
  SELECT m.user_id, m.x_username, m.x_avatar_url, m.seen_at
    FROM matched m
   ORDER BY m.seen_at DESC NULLS LAST, m.user_id
   LIMIT 50;
$$;
REVOKE ALL ON FUNCTION public.person_x_identities_v2(TEXT, UUID[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.person_x_identities_v2(TEXT, UUID[]) TO service_role;
COMMENT ON FUNCTION public.person_x_identities_v2(TEXT, UUID[]) IS
  'person_x_identities_v1, also counting X identities on additional sign-ins (account_sign_ins) for the account they reach. Service-only, read-only.';
