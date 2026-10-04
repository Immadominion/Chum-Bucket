-- One account, many sign-ins: deliberate linking and folding — additive and
-- re-runnable (IF NOT EXISTS, CREATE OR REPLACE, DROP TRIGGER IF EXISTS).
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
--   account_link_audit     every link, unlink, fold and deletion (append-only)
--
-- What a fold does, precisely (fold_account_into_v1). The account being
-- folded ("F") into the account the person is signed in to ("K"):
--
--   * who may: only F's PRIMARY sign-in (users.auth_user_id) proves F for a
--             fold. A wallet merely linked to F, or an additional sign-in of
--             F, may not fold it;
--   * moves:  every sign-in of F (its primary and its additional sign-ins)
--             becomes an additional sign-in of K; F's active linked wallets
--             move to K (wallet_link_audit 'transferred'); F's
--             users.wallet_address moves to K (if K already has one, the fold
--             is refused — a legacy wallet column is never orphaned); F's push
--             tokens and legacy linked_identities move to K. The BFF tells
--             F's devices it happened;
--   * copies: F's follows (both directions) and blocks/mutes (both
--             directions) onto K, never onto K itself; F's own rows stay;
--   * keeps:  every call, response, result, thesis update and receipt of F,
--             unchanged: same rows, same author, same timestamps. A call never
--             changes author (calls_guard_immutability); F stays as the record
--             of those calls and is marked folded (it can never sign in again);
--   * refuses (nothing changes) when F has funded activity or money: a
--             funded call, a venue order or position, a Panta trade or claim
--             session, a market it paid to create, a legacy prediction
--             position or claim, a legacy SOL escrow challenge (as creator,
--             participant, witness or winner, by id, wallet, legacy Privy id
--             or email), or an app-held wallet (embedded, chumbucket, or any
--             type but mwa/imported). A table or column it cannot check
--             refuses (fail closed). The session creators lock the account row
--             (FOR KEY SHARE) and refuse folded accounts, so none slips in
--             between check and commit;
--   * also refuses when F or K is deleted or folded, F is K, or what the
--             person was shown changed (complete names the expected outcome
--             and the other account).
--
-- delete_account_v2: one deletion for the whole person, from any sign-in that
-- reaches the account: the account (delete_account_v1), every account folded
-- into it (anonymised the same way), and every additional sign-in (released
-- here; the BFF deletes their auth users).
--
-- Everything is service-role only (RLS on, zero policies). The BFF calls it
-- after verifying every session with GoTrue; it is switched off there unless
-- ACCOUNT_LINKING_ENABLED / ACCOUNT_FOLD_ENABLED say otherwise.
--
-- Additive in shape: four new tables; new triggers on public.users (a sign-in
-- is primary or additional, never both; a folded account never gets a
-- sign-in again) and on the three money-session tables (live account only);
-- new functions. No existing table, column, grant, policy or function is
-- altered or dropped.
--
-- Proven on a throwaway PostgreSQL 15 against the real identity chain
-- (chumbucket-social-calls-api tests/accountSignIns.postgres.test.ts).
--
-- Apply AFTER 20261002171000_lockdown_profiles_push_privacy.sql,
-- 20261002180000_trust_safety_and_account.sql and
-- 20261003200000_find_person_identities.sql, and BEFORE deploying a BFF that
-- serves auth.signInMethods.

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
  IF to_regprocedure('public.delete_account_v1(uuid,uuid)') IS NULL
     OR to_regprocedure('public.trust_delete_rows_v1(text,text,text[])') IS NULL THEN
    RAISE EXCEPTION 'account_sign_ins requires 20261002180000_trust_safety_and_account.sql';
  END IF;
  IF to_regprocedure('public.person_x_identities_v1(text,uuid[])') IS NULL THEN
    RAISE EXCEPTION 'account_sign_ins requires 20261003200000_find_person_identities.sql';
  END IF;
END;
$$;

-- ── tables ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.account_sign_ins (
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
    revoked_reason IS NULL OR revoked_reason IN ('unlinked', 'folded', 'account_deleted')),
  CONSTRAINT account_sign_ins_revoked_shape CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
-- One sign-in reaches at most one account.
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_sign_ins_active ON public.account_sign_ins (auth_user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_account_sign_ins_user ON public.account_sign_ins (user_id)
  WHERE revoked_at IS NULL;
ALTER TABLE public.account_sign_ins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_sign_ins FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.account_sign_ins TO service_role;
COMMENT ON TABLE public.account_sign_ins IS
  'Additional Supabase sign-ins that reach an account they are not the primary of (users.auth_user_id). Only written by the definer functions of 20261004120000 after the BFF verified both sides. Revoked rows are history.';

CREATE TABLE IF NOT EXISTS public.account_link_tickets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- sha256 hex; the plaintext lives only in the memory of the client that asked.
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
CREATE INDEX IF NOT EXISTS idx_account_link_tickets_user ON public.account_link_tickets (user_id, issued_at);
ALTER TABLE public.account_link_tickets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_link_tickets FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.account_link_tickets TO service_role;

CREATE TABLE IF NOT EXISTS public.account_folds (
  id                  UUID PRIMARY KEY,
  folded_user_id      UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE RESTRICT,
  into_user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- The sign-in the fold was started from (K's), and F's primary that proved F.
  keeper_auth_user_id UUID NOT NULL,
  proof_auth_user_id  UUID NOT NULL,
  method              TEXT NOT NULL,
  summary             JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT account_folds_not_self CHECK (folded_user_id <> into_user_id),
  CONSTRAINT account_folds_method_check CHECK (method IN ('wallet', 'x', 'google'))
);
CREATE INDEX IF NOT EXISTS idx_account_folds_into ON public.account_folds (into_user_id);
ALTER TABLE public.account_folds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_folds FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.account_folds TO service_role;
COMMENT ON TABLE public.account_folds IS
  'One row per account folded into another (fold_account_into_v1). The folded account keeps its calls and receipts unchanged; its sign-ins, wallets and devices moved to into_user_id. Append-only.';

CREATE TABLE IF NOT EXISTS public.account_link_audit (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action         TEXT NOT NULL,
  user_id        UUID REFERENCES public.users(id) ON DELETE SET NULL,
  other_user_id  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  auth_user_id   UUID,
  wallet_address TEXT,
  detail         JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT account_link_audit_action_check CHECK (
    action IN ('sign_in_linked', 'sign_in_unlinked', 'wallet_unlinked', 'folded', 'account_deleted'))
);
CREATE INDEX IF NOT EXISTS idx_account_link_audit_user ON public.account_link_audit (user_id, created_at DESC);
-- A database that ran an earlier draft of this file gets today's checks.
ALTER TABLE public.account_link_audit DROP CONSTRAINT IF EXISTS account_link_audit_action_check;
ALTER TABLE public.account_link_audit ADD CONSTRAINT account_link_audit_action_check CHECK (
  action IN ('sign_in_linked', 'sign_in_unlinked', 'wallet_unlinked', 'folded', 'account_deleted'));
ALTER TABLE public.account_sign_ins DROP CONSTRAINT IF EXISTS account_sign_ins_reason_check;
ALTER TABLE public.account_sign_ins ADD CONSTRAINT account_sign_ins_reason_check CHECK (
  revoked_reason IS NULL OR revoked_reason IN ('unlinked', 'folded', 'account_deleted'));
-- The earlier draft's completion took no expectation; it must not linger.
DROP FUNCTION IF EXISTS public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN);
ALTER TABLE public.account_link_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_link_audit FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.account_link_audit TO service_role;
COMMENT ON TABLE public.account_link_audit IS
  'Append-only trail of every additional sign-in linked or unlinked, wallet unlinked, account folded and account deleted. Service role only.';

CREATE OR REPLACE FUNCTION public.account_link_history_guard_v1()
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
DROP TRIGGER IF EXISTS trg_account_folds_append_only ON public.account_folds;
CREATE TRIGGER trg_account_folds_append_only BEFORE UPDATE OR DELETE ON public.account_folds
  FOR EACH ROW EXECUTE FUNCTION public.account_link_history_guard_v1();
DROP TRIGGER IF EXISTS trg_account_folds_no_truncate ON public.account_folds;
CREATE TRIGGER trg_account_folds_no_truncate BEFORE TRUNCATE ON public.account_folds
  FOR EACH STATEMENT EXECUTE FUNCTION public.account_link_history_guard_v1();
DROP TRIGGER IF EXISTS trg_account_link_audit_append_only ON public.account_link_audit;
CREATE TRIGGER trg_account_link_audit_append_only BEFORE UPDATE OR DELETE ON public.account_link_audit
  FOR EACH ROW EXECUTE FUNCTION public.account_link_history_guard_v1();
DROP TRIGGER IF EXISTS trg_account_link_audit_no_truncate ON public.account_link_audit;
CREATE TRIGGER trg_account_link_audit_no_truncate BEFORE TRUNCATE ON public.account_link_audit
  FOR EACH STATEMENT EXECUTE FUNCTION public.account_link_history_guard_v1();

-- ── what a live account is ──────────────────────────────────────────────────

-- Neither deleted nor folded into another. Internal.
CREATE OR REPLACE FUNCTION public.account_is_live_v1(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user_id AND u.deleted_at IS NULL)
     AND NOT EXISTS (SELECT 1 FROM public.account_folds f WHERE f.folded_user_id = p_user_id);
$$;
REVOKE ALL ON FUNCTION public.account_is_live_v1(UUID) FROM PUBLIC, anon, authenticated;

-- ── triggers: the two kinds of sign-in never overlap ───────────────────────

CREATE OR REPLACE FUNCTION public.account_sign_ins_not_primary_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  -- The same per-sign-in lock every linking function takes: a profile being
  -- created for this sign-in and a link of it can never both commit.
  PERFORM pg_advisory_xact_lock(hashtextextended('account-sign-in:' || NEW.auth_user_id::text, 0));
  IF NEW.revoked_at IS NULL
     AND EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = NEW.auth_user_id) THEN
    RAISE EXCEPTION 'this sign-in is already an account''s primary sign-in'
      USING ERRCODE = 'unique_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.account_sign_ins_not_primary_v1() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_account_sign_ins_not_primary ON public.account_sign_ins;
CREATE TRIGGER trg_account_sign_ins_not_primary
  BEFORE INSERT OR UPDATE ON public.account_sign_ins
  FOR EACH ROW EXECUTE FUNCTION public.account_sign_ins_not_primary_v1();

-- A folded account never gets a sign-in again (no carry-over, no claim, no
-- re-bind), and a sign-in that reaches a live account as an additional one
-- never becomes another account's primary.
CREATE OR REPLACE FUNCTION public.users_primary_not_additional_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF NEW.auth_user_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.auth_user_id IS DISTINCT FROM OLD.auth_user_id) THEN
    -- Serialises create_social_person_v*, bind_wallet_session_v1 and claims
    -- with complete_account_link_v1 / resolve_wallet_sign_in_v1 for this
    -- sign-in: whichever commits second sees the first and is refused.
    PERFORM pg_advisory_xact_lock(hashtextextended('account-sign-in:' || NEW.auth_user_id::text, 0));
    IF EXISTS (SELECT 1 FROM public.account_folds f WHERE f.folded_user_id = NEW.id) THEN
      RAISE EXCEPTION 'a folded account never signs in again'
        USING ERRCODE = 'unique_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM public.account_sign_ins s
                WHERE s.auth_user_id = NEW.auth_user_id AND s.revoked_at IS NULL
                  AND public.account_is_live_v1(s.user_id)) THEN
      RAISE EXCEPTION 'this sign-in already reaches another account'
        USING ERRCODE = 'unique_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.users_primary_not_additional_v1() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_users_primary_not_additional ON public.users;
CREATE TRIGGER trg_users_primary_not_additional
  BEFORE INSERT OR UPDATE OF auth_user_id ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.users_primary_not_additional_v1();

-- ── triggers: a money session starts only on a live account ───────────────
--
-- The row lock (FOR KEY SHARE) serialises with a fold's FOR UPDATE on the
-- same row — either the session commits first and the fold sees it (and
-- refuses), or the fold commits first and the session sees a folded account
-- (and is refused) — without blocking ordinary profile updates. Separately
-- named; the tables' own guards are untouched.
CREATE OR REPLACE FUNCTION public.money_session_account_live_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_user UUID := (to_jsonb(NEW) ->> TG_ARGV[0])::uuid;
BEGIN
  PERFORM 1 FROM public.users u WHERE u.id = v_user FOR KEY SHARE;
  IF NOT public.account_is_live_v1(v_user) THEN
    RAISE EXCEPTION 'this account was folded or deleted'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.money_session_account_live_v1() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v RECORD;
BEGIN
  FOR v IN SELECT * FROM (VALUES
    ('panta_trade_sessions', 'user_id'),
    ('panta_claim_sessions', 'user_id'),
    ('market_creation_sessions', 'publisher_id')
  ) AS t(tbl, col)
  LOOP
    IF to_regclass('public.' || v.tbl) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', 'trg_' || v.tbl || '_account_live', v.tbl);
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT ON public.%I FOR EACH ROW EXECUTE FUNCTION public.money_session_account_live_v1(%L)',
        'trg_' || v.tbl || '_account_live', v.tbl, v.col);
    END IF;
  END LOOP;
END;
$$;

-- ── resolution ──────────────────────────────────────────────────────────────

-- The account a sign-in reaches: its primary account, else the account it is
-- an additional sign-in of. Never a deleted or folded account. Internal.
CREATE OR REPLACE FUNCTION public.account_for_auth_user_v1(p_auth_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT c.id FROM (
    SELECT u.id, 0 AS preference
      FROM public.users u
     WHERE u.auth_user_id = p_auth_user_id AND public.account_is_live_v1(u.id)
    UNION ALL
    SELECT s.user_id, 1
      FROM public.account_sign_ins s
     WHERE s.auth_user_id = p_auth_user_id AND s.revoked_at IS NULL
       AND public.account_is_live_v1(s.user_id)
  ) c
  ORDER BY c.preference
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.account_for_auth_user_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Whether this auth user holds the Web3 identity of this wallet. Internal.
CREATE OR REPLACE FUNCTION public.auth_user_holds_wallet_v1(p_auth_user_id UUID, p_wallet TEXT)
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

-- What an identity shows: the X username, the Google email, the wallet. Internal.
CREATE OR REPLACE FUNCTION public.identity_label_v1(p_provider TEXT, p_provider_id TEXT, p_data JSONB)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT CASE
    WHEN p_provider IN ('x', 'twitter') THEN
      coalesce(nullif(btrim(p_data ->> 'user_name'), ''),
               nullif(btrim(p_data ->> 'preferred_username'), ''),
               nullif(btrim(p_data ->> 'screen_name'), ''))
    WHEN p_provider = 'google' THEN nullif(btrim(p_data ->> 'email'), '')
    WHEN p_provider = 'web3' THEN
      coalesce(substring(p_provider_id FROM '^web3:solana:(.+)$'),
               substring(p_data ->> 'sub' FROM '^web3:solana:(.+)$'))
    ELSE NULL END;
$$;
REVOKE ALL ON FUNCTION public.identity_label_v1(TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;

-- The account holding a wallet through a PROVEN link: an active linked_wallets
-- row whose signature was verified, on a live account, AND the latest entry
-- of the service-only audit trail for that wallet names the same account.
-- The audit check is what makes a link written by the old client-writable
-- path (sync_user_by_wallet before 20261002171000 repointed rows without an
-- audit entry) count for nothing here. Internal.
CREATE OR REPLACE FUNCTION public.proven_wallet_owner_v1(p_wallet TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT w.user_id
    FROM public.linked_wallets w
   WHERE w.wallet_address = btrim(p_wallet)
     AND w.revoked_at IS NULL
     AND w.verified_at IS NOT NULL
     AND w.siws_proof_version IS NOT NULL
     AND public.account_is_live_v1(w.user_id)
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
CREATE OR REPLACE FUNCTION public.wallet_account_v1(p_wallet TEXT)
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

-- Additional sign-ins of a deleted account are released (delete_account_v1
-- predates them). Internal; called before a sign-in is linked anywhere.
CREATE OR REPLACE FUNCTION public.release_dead_sign_ins_v1(p_auth_user_id UUID)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  UPDATE public.account_sign_ins s
     SET revoked_at = now(), revoked_reason = 'account_deleted'
    FROM public.users u
   WHERE u.id = s.user_id AND u.deleted_at IS NOT NULL
     AND s.auth_user_id = p_auth_user_id AND s.revoked_at IS NULL;
$$;
REVOKE ALL ON FUNCTION public.release_dead_sign_ins_v1(UUID) FROM PUBLIC, anon, authenticated;

-- What the BFF asks when the primary lookup misses: the live account an
-- additional sign-in reaches. {ok, user_id (null when none), via}.
CREATE OR REPLACE FUNCTION public.resolve_auth_user_v1(p_auth_user_id UUID)
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
   WHERE u.auth_user_id = p_auth_user_id AND public.account_is_live_v1(u.id);
  IF v_user IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'user_id', v_user, 'via', 'primary');
  END IF;
  SELECT s.user_id INTO v_user FROM public.account_sign_ins s
   WHERE s.auth_user_id = p_auth_user_id AND s.revoked_at IS NULL AND public.account_is_live_v1(s.user_id);
  RETURN jsonb_build_object('ok', true, 'user_id', v_user,
                            'via', CASE WHEN v_user IS NULL THEN NULL ELSE 'additional' END);
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
CREATE OR REPLACE FUNCTION public.resolve_wallet_sign_in_v1(p_auth_user_id UUID, p_wallet_address TEXT)
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
  PERFORM public.release_dead_sign_ins_v1(p_auth_user_id);

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
  IF v_primary IS NULL OR NOT public.account_is_live_v1(v_owner) THEN
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
CREATE OR REPLACE FUNCTION public.wallet_sign_in_conflict_v1(p_user_id UUID, p_wallet_address TEXT)
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
CREATE OR REPLACE FUNCTION public.account_sign_ins_v1(p_user_id UUID)
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
     WHERE u.id = p_user_id AND u.auth_user_id IS NOT NULL AND public.account_is_live_v1(u.id)
    UNION ALL
    SELECT a.auth_user_id, false, a.id, a.via, 1, a.created_at
      FROM public.account_sign_ins a
     WHERE a.user_id = p_user_id AND a.revoked_at IS NULL AND public.account_is_live_v1(a.user_id)
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
                          'label', public.identity_label_v1(i.provider, i.provider_id, i.identity_data),
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
       WHERE w.user_id = p_user_id AND w.revoked_at IS NULL AND w.verified_at IS NOT NULL
         AND public.account_is_live_v1(p_user_id)), '[]'::jsonb));
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
-- again at its next sign-in. When the account's legacy wallet column named an
-- unlinked wallet, it moves to another linked wallet or is cleared.
CREATE OR REPLACE FUNCTION public.unlink_sign_in_v1(
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
  v_column   TEXT;
  v_next     TEXT;
  v_auths    UUID[] := ARRAY[]::UUID[];
  v_wallets  TEXT[] := ARRAY[]::TEXT[];
  v_n        INTEGER;
  v_wallet   TEXT := nullif(btrim(coalesce(p_wallet, '')), '');
BEGIN
  IF p_user_id IS NULL OR p_session_auth_user_id IS NULL
     OR (p_sign_in_id IS NULL) = (v_wallet IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  SELECT u.auth_user_id, u.wallet_address INTO v_primary, v_column FROM public.users u
   WHERE u.id = p_user_id AND public.account_is_live_v1(u.id) FOR UPDATE;
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

  -- The legacy column never keeps naming a wallet this account let go.
  IF v_column IS NOT NULL AND v_column = ANY (v_wallets) THEN
    SELECT w.wallet_address INTO v_next
      FROM public.linked_wallets w
     WHERE w.user_id = p_user_id AND w.revoked_at IS NULL AND w.verified_at IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM public.users o WHERE o.wallet_address = w.wallet_address)
     ORDER BY w.is_primary DESC, w.created_at
     LIMIT 1;
    UPDATE public.users SET wallet_address = v_next, updated_at = now() WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'outcome', 'unlinked',
    'sign_ins', v_n, 'wallets', cardinality(v_wallets));
END;
$$;
REVOKE ALL ON FUNCTION public.unlink_sign_in_v1(UUID, UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unlink_sign_in_v1(UUID, UUID, UUID, TEXT) TO service_role;

-- ── link tickets ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.issue_account_link_ticket_v1(
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

-- Every wallet an account has held: its legacy column, every linked wallet
-- (active or not), and the Web3 identity of every sign-in reaching it. Internal.
CREATE OR REPLACE FUNCTION public.account_wallets_v1(p_user_id UUID)
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT coalesce(array_agg(DISTINCT w), ARRAY[]::TEXT[]) FROM (
    SELECT u.wallet_address AS w FROM public.users u WHERE u.id = p_user_id
    UNION ALL
    SELECT l.wallet_address FROM public.linked_wallets l WHERE l.user_id = p_user_id
    UNION ALL
    SELECT public.identity_label_v1(i.provider, i.provider_id, i.identity_data)
      FROM auth.identities i
     WHERE i.provider = 'web3'
       AND i.user_id IN (SELECT u.auth_user_id FROM public.users u WHERE u.id = p_user_id
                         UNION ALL
                         SELECT s.auth_user_id FROM public.account_sign_ins s
                          WHERE s.user_id = p_user_id AND s.revoked_at IS NULL)
  ) x WHERE w IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.account_wallets_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Every legacy Privy id and email an account is known by: its own columns,
-- its old Privy claims, and the identities of every sign-in reaching it.
-- Emails are lowercased. Internal.
CREATE OR REPLACE FUNCTION public.account_privy_ids_v1(p_user_id UUID)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v TEXT[];
  v_more TEXT[];
BEGIN
  SELECT coalesce(array_agg(DISTINCT u.privy_id) FILTER (WHERE u.privy_id IS NOT NULL), ARRAY[]::TEXT[])
    INTO v FROM public.users u WHERE u.id = p_user_id;
  IF to_regclass('public.legacy_identity_claims') IS NOT NULL THEN
    EXECUTE 'SELECT coalesce(array_agg(DISTINCT legacy_subject), ARRAY[]::TEXT[])
               FROM public.legacy_identity_claims WHERE user_id = $1 AND legacy_provider = ''privy'''
      INTO v_more USING p_user_id;
    v := v || v_more;
  END IF;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.account_privy_ids_v1(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.account_emails_v1(p_user_id UUID)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v TEXT[];
  v_more TEXT[];
BEGIN
  SELECT coalesce(array_agg(DISTINCT lower(e)), ARRAY[]::TEXT[]) INTO v FROM (
    SELECT u.email AS e FROM public.users u WHERE u.id = p_user_id
    UNION ALL
    SELECT i.identity_data ->> 'email'
      FROM auth.identities i
     WHERE i.user_id IN (SELECT u.auth_user_id FROM public.users u WHERE u.id = p_user_id
                         UNION ALL
                         SELECT s.auth_user_id FROM public.account_sign_ins s
                          WHERE s.user_id = p_user_id AND s.revoked_at IS NULL)
  ) x WHERE e IS NOT NULL AND btrim(e) <> '';
  IF to_regclass('public.linked_identities') IS NOT NULL THEN
    EXECUTE 'SELECT coalesce(array_agg(DISTINCT lower(provider_email)), ARRAY[]::TEXT[])
               FROM public.linked_identities WHERE user_id = $1 AND provider_email IS NOT NULL'
      INTO v_more USING p_user_id;
    v := v || v_more;
  END IF;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.account_emails_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Funded activity or money on an account: the first kind found, or NULL.
-- Fail closed: a table or a column this knows to check that is not there
-- answers 'unverifiable', which refuses a fold just the same. Each column is
-- matched by what it holds: the account id, its wallets, its legacy Privy
-- ids, or its emails (the legacy SOL escrow keyed people all four ways).
CREATE OR REPLACE FUNCTION public.account_money_activity_v1(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_wallets TEXT[] := public.account_wallets_v1(p_user_id);
  v_privy   TEXT[] := public.account_privy_ids_v1(p_user_id);
  v_emails  TEXT[] := public.account_emails_v1(p_user_id);
  v_found   BOOLEAN;
  v_check   RECORD;
  v_col     TEXT;
  v_name    TEXT;
  v_preds   TEXT[];
BEGIN
  FOR v_check IN
    SELECT * FROM (VALUES
      ('funded_call',         'calls',                    ARRAY['user_id:id'],                         'funding_state <> ''NONE'''),
      ('venue_order',         'venue_orders',             ARRAY['user_id:id'],                         NULL),
      ('venue_position',      'venue_positions',          ARRAY['user_id:id'],                         NULL),
      ('panta_trade',         'panta_trade_sessions',     ARRAY['user_id:id', 'wallet_address:wallet'], NULL),
      ('panta_claim',         'panta_claim_sessions',     ARRAY['user_id:id', 'wallet_address:wallet'], NULL),
      ('market_creation',     'market_creation_sessions', ARRAY['publisher_id:id', 'wallet_address:wallet'], NULL),
      ('prediction_position', 'prediction_positions',     ARRAY['user_id:id', 'wallet_address:wallet'], NULL),
      ('prediction_claim',    'claims',                   ARRAY['user_id:id', 'wallet_address:wallet'], NULL),
      ('escrow_challenge',    'challenges',               ARRAY[
                                'creator_id:id', 'participant_id:id', 'witness_id:id',
                                'winner_id:text', 'winner_id:wallet', 'winner_id:privy',
                                'creator_wallet_address:wallet',
                                'member1_address:wallet', 'member1_address:privy',
                                'member2_address:wallet', 'member2_address:privy',
                                'witness_address:wallet', 'witness_address:privy',
                                'creator_privy_id:privy', 'participant_privy_id:privy', 'winner_privy_id:privy',
                                'participant_email:email'], NULL),
      ('escrow_participant',  'challenge_participants',   ARRAY['wallet_address:wallet', 'wallet_address:privy',
                                                                'user_privy_id:privy'],          NULL),
      ('escrow_transaction',  'challenge_transactions',   ARRAY['from_address:wallet', 'to_address:wallet'], NULL),
      -- An app-held wallet (embedded, chumbucket, anything but a wallet app
      -- or an import) may hold a balance only this account can reach.
      ('app_wallet',          'linked_wallets',           ARRAY['user_id:id'],
                              'revoked_at IS NULL AND wallet_type NOT IN (''mwa'', ''imported'')')
    ) AS t(kind, tbl, cols, extra)
  LOOP
    IF to_regclass('public.' || v_check.tbl) IS NULL THEN
      RETURN 'unverifiable';
    END IF;
    v_preds := ARRAY[]::TEXT[];
    FOREACH v_col IN ARRAY v_check.cols LOOP
      v_name := split_part(v_col, ':', 1);
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema = 'public' AND table_name = v_check.tbl AND column_name = v_name) THEN
        RETURN 'unverifiable';
      END IF;
      v_preds := v_preds || CASE split_part(v_col, ':', 2)
        WHEN 'id'     THEN format('%I = $1', v_name)
        WHEN 'text'   THEN format('%I::text = $1::text', v_name)
        WHEN 'wallet' THEN format('%I::text = ANY ($2)', v_name)
        WHEN 'privy'  THEN format('%I::text = ANY ($3)', v_name)
        ELSE format('lower(%I::text) = ANY ($4)', v_name) END;
    END LOOP;
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE (%s)%s)',
                   v_check.tbl, array_to_string(v_preds, ' OR '),
                   CASE WHEN v_check.extra IS NULL THEN '' ELSE ' AND ' || v_check.extra END)
      INTO v_found USING p_user_id, v_wallets, v_privy, v_emails;
    IF v_found THEN RETURN v_check.kind; END IF;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.account_money_activity_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Does this auth user hold an identity for the ticket's method? Internal.
CREATE OR REPLACE FUNCTION public.auth_user_has_method_v1(p_auth_user_id UUID, p_method TEXT)
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

-- What the proving sign-in proved, as the person will see it: its most
-- recently used identity of the ticket's method (X username, Google email,
-- wallet address). Internal.
CREATE OR REPLACE FUNCTION public.proof_label_v1(p_auth_user_id UUID, p_method TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT public.identity_label_v1(i.provider, i.provider_id, i.identity_data)
    FROM auth.identities i
   WHERE i.user_id = p_auth_user_id
     AND i.provider = ANY (CASE p_method
                             WHEN 'x' THEN ARRAY['x', 'twitter']
                             WHEN 'google' THEN ARRAY['google']
                             WHEN 'wallet' THEN ARRAY['web3']
                             ELSE ARRAY[]::TEXT[] END)
   ORDER BY i.last_sign_in_at DESC NULLS LAST, i.created_at DESC NULLS LAST
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.proof_label_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- The account the proving sign-in reaches, including through its wallet: an
-- auth user with no account yet whose Web3 wallet is linked somewhere reaches
-- that account (exactly as its next sign-in would). Internal.
CREATE OR REPLACE FUNCTION public.proving_account_v1(p_auth_user_id UUID)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT coalesce(
    public.account_for_auth_user_v1(p_auth_user_id),
    (SELECT public.proven_wallet_owner_v1(public.identity_label_v1(i.provider, i.provider_id, i.identity_data))
       FROM auth.identities i
      WHERE i.user_id = p_auth_user_id AND i.provider = 'web3'
        AND NOT EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = p_auth_user_id)
      LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.proving_account_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Why a fold of F proven by this sign-in would be refused, or NULL. Internal;
-- the same rules preview shows and the fold enforces.
CREATE OR REPLACE FUNCTION public.fold_refusal_v1(p_into_user_id UUID, p_folded_user_id UUID, p_proof_auth UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_money TEXT;
BEGIN
  IF p_into_user_id = p_folded_user_id THEN RETURN 'same_account'; END IF;
  IF NOT public.account_is_live_v1(p_into_user_id) OR NOT public.account_is_live_v1(p_folded_user_id) THEN
    RETURN 'already_folded';
  END IF;
  -- Only the account's own first sign-in can give it away.
  IF NOT EXISTS (SELECT 1 FROM public.users u
                  WHERE u.id = p_folded_user_id AND u.auth_user_id = p_proof_auth) THEN
    RETURN 'not_primary_sign_in';
  END IF;
  v_money := public.account_money_activity_v1(p_folded_user_id);
  IF v_money = 'unverifiable' THEN RETURN 'money_unverifiable'; END IF;
  IF v_money IS NOT NULL THEN RETURN 'has_money'; END IF;
  -- One legacy wallet column each: never orphan one to make room.
  IF EXISTS (SELECT 1 FROM public.users f, public.users k
              WHERE f.id = p_folded_user_id AND k.id = p_into_user_id
                AND f.wallet_address IS NOT NULL AND k.wallet_address IS NOT NULL) THEN
    RETURN 'wallet_conflict';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.fold_refusal_v1(UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;

-- What completing a ticket with this sign-in would do. Reads only.
--   outcome     'already'  the sign-in already reaches the ticket's account
--               'link'     a sign-in with no account becomes an additional one
--               'fold'     the sign-in's account would be folded in
--   proof_label what the sign-in proved (X username, Google email, wallet)
--   refusal     why it cannot, when it cannot
CREATE OR REPLACE FUNCTION public.preview_account_link_v1(p_ticket_hash TEXT, p_auth_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_ticket public.account_link_tickets%ROWTYPE;
  v_other  UUID;
  v_label  TEXT;
  v_refusal TEXT;
BEGIN
  SELECT * INTO v_ticket FROM public.account_link_tickets WHERE ticket_hash = p_ticket_hash;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown'); END IF;
  IF v_ticket.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_used'); END IF;
  IF v_ticket.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_expired'); END IF;
  IF p_auth_user_id IS NULL OR NOT public.auth_user_has_method_v1(p_auth_user_id, v_ticket.method) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'method_mismatch');
  END IF;
  IF NOT public.account_is_live_v1(v_ticket.user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown');
  END IF;
  v_label := public.proof_label_v1(p_auth_user_id, v_ticket.method);

  v_other := public.proving_account_v1(p_auth_user_id);
  IF v_other = v_ticket.user_id THEN
    RETURN jsonb_build_object('ok', true, 'outcome', 'already', 'into_user_id', v_ticket.user_id,
                              'other_user_id', v_other, 'method', v_ticket.method, 'proof_label', v_label);
  END IF;
  IF v_other IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'outcome', 'link', 'into_user_id', v_ticket.user_id,
                              'other_user_id', NULL, 'method', v_ticket.method, 'proof_label', v_label);
  END IF;
  v_refusal := public.fold_refusal_v1(v_ticket.user_id, v_other, p_auth_user_id);
  RETURN jsonb_build_object('ok', true, 'outcome', 'fold', 'into_user_id', v_ticket.user_id,
                            'other_user_id', v_other, 'method', v_ticket.method, 'proof_label', v_label,
                            'refusal', v_refusal);
END;
$$;
REVOKE ALL ON FUNCTION public.preview_account_link_v1(TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.preview_account_link_v1(TEXT, UUID) TO service_role;

-- ── the fold ────────────────────────────────────────────────────────────────
--
-- Internal: called only by complete_account_link_v1, inside its transaction.
-- Locks both rows, then re-checks everything the preview showed. See the
-- header for exactly what moves, what is copied and what stays.
CREATE OR REPLACE FUNCTION public.fold_account_into_v1(
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
  v_f_wallet TEXT;
  v_moved    TEXT[];
  v_signins  UUID[] := ARRAY[]::UUID[];
  v_old      JSONB;
  v_follows  JSONB;
  v_notify   JSONB := '[]'::jsonb;
  v_n        INTEGER;
  v_summary  JSONB := '{}'::jsonb;
  v_refusal  TEXT;
BEGIN
  IF p_into_user_id = p_folded_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'same_account');
  END IF;
  -- Both rows, in a fixed order: two folds in opposite directions cannot deadlock.
  PERFORM 1 FROM public.users WHERE id IN (p_into_user_id, p_folded_user_id) ORDER BY id FOR UPDATE;
  IF (SELECT count(*) FROM public.users WHERE id IN (p_into_user_id, p_folded_user_id)) <> 2 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;
  -- What the person was shown is re-proven under the locks.
  IF public.proving_account_v1(p_proof_auth) IS DISTINCT FROM p_folded_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'proof_changed');
  END IF;
  v_refusal := public.fold_refusal_v1(p_into_user_id, p_folded_user_id, p_proof_auth);
  IF v_refusal IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_refusal,
                              'money', public.account_money_activity_v1(p_folded_user_id));
  END IF;

  -- Who to tell: the folded account's devices, before they move.
  IF to_regclass('public.push_tokens') IS NOT NULL THEN
    EXECUTE 'SELECT coalesce(jsonb_agg(jsonb_build_object(''token'', token, ''platform'', platform)), ''[]''::jsonb)
               FROM public.push_tokens WHERE user_id = $1'
      INTO v_notify USING p_folded_user_id;
  END IF;

  -- 1. Sign-ins. The folded account's primary becomes an additional sign-in
  --    here (its row is released first: a sign-in is never both), then each
  --    of its additional sign-ins is re-issued here and the old row revoked.
  SELECT auth_user_id, wallet_address INTO v_primary, v_f_wallet FROM public.users WHERE id = p_folded_user_id;
  UPDATE public.users SET auth_user_id = NULL, updated_at = now() WHERE id = p_folded_user_id;
  INSERT INTO public.account_sign_ins (auth_user_id, user_id, via, fold_id)
  VALUES (v_primary, p_into_user_id, 'fold', v_fold);
  v_signins := v_signins || v_primary;
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
  -- The legacy column moves with the person (the refusal above guarantees
  -- the surviving account has none), so wallet-keyed history stays reachable.
  IF v_f_wallet IS NOT NULL THEN
    UPDATE public.users SET wallet_address = NULL, updated_at = now() WHERE id = p_folded_user_id;
    UPDATE public.users SET wallet_address = v_f_wallet, updated_at = now() WHERE id = p_into_user_id;
  END IF;
  v_summary := v_summary || jsonb_build_object('wallets', to_jsonb(v_moved), 'wallet_column', v_f_wallet);

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
                            'summary', v_summary, 'notify', v_notify);
END;
$$;
REVOKE ALL ON FUNCTION public.fold_account_into_v1(UUID, UUID, UUID, UUID, TEXT) FROM PUBLIC, anon, authenticated;

-- Complete a ticket with the sign-in that proves the other side. The BFF
-- passes what the person was shown (the outcome and the other account); if
-- either changed since, nothing happens. Consumes the ticket only when
-- something happened (or nothing needed to); a refusal leaves it for a retry
-- until it expires. p_allow_link / p_allow_fold are the BFF's switches, read
-- inside the same transaction as the state they gate.
CREATE OR REPLACE FUNCTION public.complete_account_link_v1(
  p_ticket_hash      TEXT,
  p_auth_user_id     UUID,
  p_allow_link       BOOLEAN,
  p_allow_fold       BOOLEAN,
  p_expected_outcome TEXT,
  p_expected_other   UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_ticket  public.account_link_tickets%ROWTYPE;
  v_other   UUID;
  v_outcome TEXT;
  v_result  JSONB;
BEGIN
  IF p_auth_user_id IS NULL OR p_ticket_hash IS NULL
     OR p_expected_outcome NOT IN ('already', 'link', 'fold') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-sign-in:' || p_auth_user_id::text, 0));
  PERFORM public.release_dead_sign_ins_v1(p_auth_user_id);
  SELECT * INTO v_ticket FROM public.account_link_tickets WHERE ticket_hash = p_ticket_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown'); END IF;
  IF v_ticket.consumed_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_used'); END IF;
  IF v_ticket.expires_at <= clock_timestamp() THEN RETURN jsonb_build_object('ok', false, 'reason', 'ticket_expired'); END IF;
  IF NOT public.auth_user_has_method_v1(p_auth_user_id, v_ticket.method) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'method_mismatch');
  END IF;
  IF NOT public.account_is_live_v1(v_ticket.user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown');
  END IF;

  v_other := public.proving_account_v1(p_auth_user_id);
  v_outcome := CASE WHEN v_other = v_ticket.user_id THEN 'already'
                    WHEN v_other IS NULL THEN 'link'
                    ELSE 'fold' END;
  IF v_outcome <> p_expected_outcome OR v_other IS DISTINCT FROM p_expected_other THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'preview_changed');
  END IF;

  IF v_outcome = 'already' THEN
    v_result := jsonb_build_object('ok', true, 'outcome', 'already', 'user_id', v_ticket.user_id);
  ELSIF v_outcome = 'link' THEN
    IF NOT coalesce(p_allow_link, false) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'linking_disabled');
    END IF;
    -- The account the sign-in joins is locked and re-checked.
    PERFORM 1 FROM public.users WHERE id = v_ticket.user_id FOR UPDATE;
    IF NOT public.account_is_live_v1(v_ticket.user_id) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'ticket_unknown');
    END IF;
    IF EXISTS (SELECT 1 FROM public.users u WHERE u.auth_user_id = p_auth_user_id) THEN
      -- The primary sign-in of a deleted or folded account: never reused.
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
    v_result := v_result || jsonb_build_object(
      'folded_handle', (SELECT handle FROM public.users WHERE id = v_other),
      'into_handle', (SELECT handle FROM public.users WHERE id = v_ticket.user_id));
  END IF;

  UPDATE public.account_link_tickets SET consumed_at = clock_timestamp(), consumed_reason = 'redeemed'
   WHERE id = v_ticket.id;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN, TEXT, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN, TEXT, UUID) TO service_role;
COMMENT ON FUNCTION public.complete_account_link_v1(TEXT, UUID, BOOLEAN, BOOLEAN, TEXT, UUID) IS
  'Service-only: completes a link ticket an account issued itself, with a GoTrue-verified sign-in for the other side, only if the outcome and other account are still what the person was shown. Already the same account: nothing. A sign-in with no account: an additional sign-in (when linking is on). Another account: folded in (when folding is on), only by its primary sign-in, never one with money. Audited.';

-- ── deletion: the whole person ──────────────────────────────────────────────
--
-- Internal: anonymise an account folded into one being deleted, the way
-- delete_account_v1 anonymises an account (it has no sign-in of its own left
-- to call that with). Its calls stay as "Deleted account".
CREATE OR REPLACE FUNCTION public.anonymise_folded_account_v1(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_ids     TEXT[] := ARRAY[p_user_id::TEXT];
  v_wallets TEXT[] := public.account_wallets_v1(p_user_id);
  v_handle  TEXT;
  v_summary JSONB;
BEGIN
  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, actor, reason)
  SELECT wallet_address, 'revoked', p_user_id, 'service', 'account deleted'
    FROM public.linked_wallets WHERE user_id = p_user_id AND revoked_at IS NULL;
  DELETE FROM public.linked_wallets WHERE user_id = p_user_id;
  v_summary := jsonb_build_object(
    'linked_identities', public.trust_delete_rows_v1('linked_identities', 'user_id', v_ids),
    'legacy_identity_claims', public.trust_delete_rows_v1('legacy_identity_claims', 'user_id', v_ids),
    'wallet_nonces', public.trust_delete_rows_v1('wallet_nonces', 'user_id', v_ids),
    'person_follows',
      public.trust_delete_rows_v1('person_follows', 'follower_user_id', v_ids)
      + public.trust_delete_rows_v1('person_follows', 'followee_user_id', v_ids),
    'follows',
      public.trust_delete_rows_v1('follows', 'follower_user_id', v_ids)
      + public.trust_delete_rows_v1('follows', 'followee_user_id', v_ids),
    'friends',
      public.trust_delete_rows_v1('friends', 'user_id', v_ids)
      + public.trust_delete_rows_v1('friends', 'friend_id', v_ids),
    'push_tokens', public.trust_delete_rows_v1('push_tokens', 'user_id', v_ids),
    'social_notifications', public.trust_delete_rows_v1('social_notifications', 'recipient_user_id', v_ids),
    'user_blocks',
      public.trust_delete_rows_v1('user_blocks', 'blocker_user_id', v_ids)
      + public.trust_delete_rows_v1('user_blocks', 'blocked_user_id', v_ids),
    'user_mutes',
      public.trust_delete_rows_v1('user_mutes', 'muter_user_id', v_ids)
      + public.trust_delete_rows_v1('user_mutes', 'muted_user_id', v_ids));
  IF to_regclass('public.existing_account_anchors') IS NOT NULL THEN
    EXECUTE 'UPDATE public.existing_account_anchors SET revoked_at = NOW()
              WHERE user_id = $1 AND revoked_at IS NULL' USING p_user_id;
  END IF;
  v_handle := 'deleted_' || substr(replace(p_user_id::TEXT, '-', ''), 1, 12);
  IF EXISTS (SELECT 1 FROM public.users WHERE lower(handle) = v_handle AND id <> p_user_id) THEN
    v_handle := 'deleted_' || replace(p_user_id::TEXT, '-', '');
    IF EXISTS (SELECT 1 FROM public.users WHERE lower(handle) = v_handle AND id <> p_user_id) THEN
      v_handle := NULL;
    END IF;
  END IF;
  UPDATE public.users SET
    full_name = 'Deleted account', bio = NULL, email = NULL, privy_id = NULL,
    wallet_address = NULL, sns_domain = NULL, handle = v_handle, profile_picture = NULL,
    profile_image_id = NULL, last_seen_at = NULL, auth_user_id = NULL,
    deleted_at = NOW(), updated_at = NOW()
  WHERE id = p_user_id;
  RETURN v_summary || jsonb_build_object('wallets', cardinality(v_wallets));
END;
$$;
REVOKE ALL ON FUNCTION public.anonymise_folded_account_v1(UUID) FROM PUBLIC, anon, authenticated;

-- Delete the person behind ANY sign-in that reaches the account: the account
-- itself (delete_account_v1, with the primary sign-in — a sign-in is promoted
-- first when the account has none), every account folded into it (through
-- any chain), and every additional sign-in (released here and recorded, so a
-- retry with any of them answers "already deleted"). Returns every auth user
-- the BFF must delete from Supabase Auth. Idempotent.
CREATE OR REPLACE FUNCTION public.delete_account_v2(p_user_id UUID, p_auth_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_account UUID;
  v_primary UUID;
  v_extras  UUID[];
  v_folded  UUID[];
  v_prior   public.account_deletions%ROWTYPE;
  v_owner   UUID;
  v_result  JSONB;
  v_f       UUID;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_auth_user');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('account-sign-in:' || p_auth_user_id::text, 0));
  v_account := public.account_for_auth_user_v1(p_auth_user_id);

  IF v_account IS NULL THEN
    -- Already deleted (through this or another sign-in), or never had one.
    SELECT * INTO v_prior FROM public.account_deletions WHERE auth_user_id = p_auth_user_id;
    IF FOUND AND v_prior.anonymised_at IS NOT NULL THEN
      v_owner := coalesce(v_prior.user_id, (v_prior.summary ->> 'additional_sign_in_of')::uuid);
      RETURN jsonb_build_object('ok', true, 'outcome', 'already_deleted', 'user_id', v_owner,
        'auth_user_id', p_auth_user_id,
        'auth_user_ids', coalesce((SELECT jsonb_agg(d.auth_user_id) FROM public.account_deletions d
                                    WHERE v_owner IS NOT NULL
                                      AND (d.user_id = v_owner OR d.summary ->> 'additional_sign_in_of' = v_owner::text)),
                                  jsonb_build_array(p_auth_user_id)),
        'folded_user_ids', '[]'::jsonb);
    END IF;
    IF p_user_id IS NULL THEN
      RETURN public.delete_account_v1(NULL, p_auth_user_id)
        || jsonb_build_object('auth_user_ids', jsonb_build_array(p_auth_user_id), 'folded_user_ids', '[]'::jsonb);
    END IF;
    RETURN jsonb_build_object('ok', false, 'reason', 'session_mismatch');
  END IF;
  -- The caller must name the account this sign-in reaches: a caller that
  -- could not resolve it (and so ran no checks on it) deletes nothing.
  IF p_user_id IS DISTINCT FROM v_account THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_mismatch');
  END IF;

  SELECT auth_user_id INTO v_primary FROM public.users WHERE id = v_account FOR UPDATE;
  IF v_primary IS NULL THEN
    -- The account's first sign-in is gone: the one asking becomes it.
    UPDATE public.account_sign_ins SET revoked_at = now(), revoked_reason = 'unlinked'
     WHERE auth_user_id = p_auth_user_id AND revoked_at IS NULL;
    UPDATE public.users SET auth_user_id = p_auth_user_id, updated_at = now() WHERE id = v_account;
    v_primary := p_auth_user_id;
  END IF;

  SELECT coalesce(array_agg(auth_user_id), ARRAY[]::UUID[]) INTO v_extras
    FROM public.account_sign_ins WHERE user_id = v_account AND revoked_at IS NULL;
  WITH RECURSIVE f(id) AS (
    SELECT a.folded_user_id FROM public.account_folds a WHERE a.into_user_id = v_account
    UNION
    SELECT a.folded_user_id FROM public.account_folds a JOIN f ON a.into_user_id = f.id
  )
  SELECT coalesce(array_agg(id), ARRAY[]::UUID[]) INTO v_folded FROM f;

  FOREACH v_f IN ARRAY v_folded LOOP
    PERFORM public.anonymise_folded_account_v1(v_f);
  END LOOP;

  UPDATE public.account_sign_ins SET revoked_at = now(), revoked_reason = 'account_deleted'
   WHERE user_id = v_account AND revoked_at IS NULL;
  INSERT INTO public.account_deletions (user_id, auth_user_id, anonymised_at, summary)
  SELECT NULL, a, now(), jsonb_build_object('additional_sign_in_of', v_account)
    FROM unnest(v_extras) a
  ON CONFLICT (auth_user_id) DO NOTHING;

  v_result := public.delete_account_v1(v_account, v_primary);
  IF NOT (v_result ->> 'ok')::boolean THEN
    RAISE EXCEPTION 'delete_account_v1 refused: %', v_result ->> 'reason';
  END IF;
  INSERT INTO public.account_link_audit (action, user_id, auth_user_id, detail)
  VALUES ('account_deleted', v_account, p_auth_user_id,
          jsonb_build_object('additional_sign_ins', cardinality(v_extras), 'folded_accounts', to_jsonb(v_folded)));
  RETURN v_result || jsonb_build_object(
    'auth_user_ids', to_jsonb(ARRAY[v_primary] || v_extras),
    'folded_user_ids', to_jsonb(v_folded));
END;
$$;
REVOKE ALL ON FUNCTION public.delete_account_v2(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_v2(UUID, UUID) TO service_role;
COMMENT ON FUNCTION public.delete_account_v2(UUID, UUID) IS
  'Service-only, idempotent deletion of the whole person behind any sign-in that reaches the account: the account (delete_account_v1), every account folded into it, and every additional sign-in. Returns the auth users the BFF deletes from Supabase Auth.';

-- ── X identities, including additional sign-ins ─────────────────────────────
--
-- person_x_identities_v1 with one change: an X identity on an additional
-- sign-in counts for the account it reaches (after a fold, the folded
-- account's X is the surviving account's X). Same shape, same rules.
CREATE OR REPLACE FUNCTION public.person_x_identities_v2(
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
