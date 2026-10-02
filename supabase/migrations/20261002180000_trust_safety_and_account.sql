-- Trust, safety and account lifecycle — additive.
--
-- What this adds, all service-role only (RLS on, zero policies, no client
-- grants), written and read by the calls BFF after it has verified the
-- caller's Supabase session:
--
--   content_reports            a person reports a call, a thesis or a person
--   user_blocks / user_mutes   who a person has blocked or muted
--   legal_acceptances          the 18+ / jurisdiction / venue-terms attestation
--                              recorded before a first funded trade (append-only)
--   account_deletions          one row per deleted sign-in, so deletion is
--                              idempotent across a retry
--   account_deletion_requests  requests made from the web deletion page
--   users.deleted_at           marks an anonymised account
--   delete_account_v1()        the one deletion path
--
-- What this does NOT change: no existing table, column, grant, policy or
-- function is altered or dropped. Every legacy client write that worked
-- before keeps working (tests/trustAccount.postgres.test.ts proves it on a
-- copy with the live rights). The one new restriction is a trigger that stops
-- anon/authenticated from editing a row that has already been anonymised.
--
-- Deletion keeps calls, responses and results — they are immutable records
-- (calls_guard_immutability refuses DELETE for every role) — and shows their
-- author as "Deleted account". Everything that identifies the person is
-- removed or blanked: name, bio, email, wallet, handle, avatar, linked
-- wallets, linked Google/X identities, follows, friends, blocks, mutes,
-- push tokens, inbox and wallet nonces.

DO $$
BEGIN
  IF to_regclass('public.users') IS NULL
     OR to_regclass('public.linked_wallets') IS NULL
     OR to_regclass('public.wallet_link_audit') IS NULL
     OR to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION 'trust_safety_and_account requires the identity and social calls migrations';
  END IF;
END;
$$;

-- ── users.deleted_at ────────────────────────────────────────────────────────
-- No client grant: 20260913120000 made new users columns fail-closed for
-- anon/authenticated writes.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
COMMENT ON COLUMN public.users.deleted_at IS
  'When this account was deleted and anonymised (delete_account_v1). Calls stay as "Deleted account". Service-role only.';

-- A deleted account is read-only to clients. The permissive legacy UPDATE
-- policy would otherwise let anyone put a new name on it.
CREATE FUNCTION public.users_deleted_row_guard_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  IF OLD.deleted_at IS NOT NULL AND current_user IN ('anon', 'authenticated') THEN
    RAISE EXCEPTION 'this account was deleted and can no longer be edited'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_users_deleted_row_guard
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.users_deleted_row_guard_v1();

-- ── content_reports ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.content_reports (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  subject_kind        TEXT NOT NULL,
  -- The call reported (or whose thesis was reported). NULL for a person report.
  subject_call_id     UUID REFERENCES public.calls(id) ON DELETE RESTRICT,
  -- The person responsible: the call's author, or the person reported.
  subject_user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  reason              TEXT NOT NULL,
  details             TEXT,
  status              TEXT NOT NULL DEFAULT 'open',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at         TIMESTAMPTZ,
  resolved_by_user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
  resolution_note     TEXT,
  CONSTRAINT content_reports_kind_check CHECK (subject_kind IN ('call', 'thesis', 'person')),
  CONSTRAINT content_reports_reason_check CHECK (reason IN (
    'spam', 'harassment', 'hate', 'sexual', 'violence', 'self_harm',
    'scam', 'impersonation', 'illegal', 'other')),
  CONSTRAINT content_reports_status_check CHECK (status IN ('open', 'actioned', 'dismissed')),
  CONSTRAINT content_reports_details_length CHECK (details IS NULL OR char_length(details) <= 500),
  CONSTRAINT content_reports_note_length CHECK (resolution_note IS NULL OR char_length(resolution_note) <= 500),
  CONSTRAINT content_reports_subject_shape CHECK (
    (subject_kind = 'person' AND subject_call_id IS NULL)
    OR (subject_kind IN ('call', 'thesis') AND subject_call_id IS NOT NULL)
  ),
  CONSTRAINT content_reports_not_self CHECK (reporter_user_id <> subject_user_id),
  CONSTRAINT content_reports_resolution_shape CHECK (
    (status = 'open' AND resolved_at IS NULL) OR (status <> 'open' AND resolved_at IS NOT NULL)
  )
);
-- One open report per reporter per subject; a repeat is "already reported".
CREATE UNIQUE INDEX IF NOT EXISTS uq_content_reports_open_subject
  ON public.content_reports (reporter_user_id, subject_kind, (COALESCE(subject_call_id, subject_user_id)))
  WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_content_reports_open
  ON public.content_reports (created_at DESC) WHERE status = 'open';
CREATE INDEX IF NOT EXISTS idx_content_reports_subject_user
  ON public.content_reports (subject_user_id, created_at DESC);

-- ── user_blocks / user_mutes ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_blocks_pair PRIMARY KEY (blocker_user_id, blocked_user_id),
  CONSTRAINT user_blocks_not_self CHECK (blocker_user_id <> blocked_user_id)
);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON public.user_blocks (blocked_user_id);

CREATE TABLE IF NOT EXISTS public.user_mutes (
  muter_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  muted_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_mutes_pair PRIMARY KEY (muter_user_id, muted_user_id),
  CONSTRAINT user_mutes_not_self CHECK (muter_user_id <> muted_user_id)
);

-- ── legal_acceptances (append-only) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.legal_acceptances (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  scope                 TEXT NOT NULL,
  terms_version         TEXT NOT NULL,
  is_18_plus            BOOLEAN NOT NULL,
  jurisdiction_eligible BOOLEAN NOT NULL,
  venue_terms_accepted  BOOLEAN NOT NULL,
  accepted_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT legal_acceptances_scope_check CHECK (scope IN ('funded_trading')),
  CONSTRAINT legal_acceptances_version_check CHECK (terms_version ~ '^[A-Za-z0-9._-]{1,64}$'),
  -- An attestation records a yes. A "no" is not an acceptance and is never stored.
  CONSTRAINT legal_acceptances_all_attested CHECK (is_18_plus AND jurisdiction_eligible AND venue_terms_accepted),
  CONSTRAINT legal_acceptances_once_per_version UNIQUE (user_id, scope, terms_version)
);

CREATE FUNCTION public.legal_acceptances_append_only_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'legal_acceptances is append-only: an acceptance is a record of what was agreed'
    USING ERRCODE = 'raise_exception';
END;
$$;
CREATE TRIGGER trg_legal_acceptances_append_only
  BEFORE UPDATE OR DELETE ON public.legal_acceptances
  FOR EACH ROW EXECUTE FUNCTION public.legal_acceptances_append_only_v1();
CREATE TRIGGER trg_legal_acceptances_no_truncate
  BEFORE TRUNCATE ON public.legal_acceptances
  FOR EACH STATEMENT EXECUTE FUNCTION public.legal_acceptances_append_only_v1();

-- ── account_deletions ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_deletions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- NULL when the sign-in never created a profile.
  user_id         UUID REFERENCES public.users(id) ON DELETE RESTRICT,
  -- Not a foreign key: the auth user is removed as part of deletion.
  auth_user_id    UUID NOT NULL,
  requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  anonymised_at   TIMESTAMPTZ,
  auth_deleted_at TIMESTAMPTZ,
  summary         JSONB NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT account_deletions_auth_user_key UNIQUE (auth_user_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_deletions_user
  ON public.account_deletions (user_id) WHERE user_id IS NOT NULL;

-- ── account_deletion_requests (web page) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact        TEXT NOT NULL,
  handle         TEXT,
  wallet_address TEXT,
  details        TEXT,
  status         TEXT NOT NULL DEFAULT 'received',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at   TIMESTAMPTZ,
  CONSTRAINT account_deletion_requests_contact_length CHECK (char_length(contact) BETWEEN 3 AND 254),
  CONSTRAINT account_deletion_requests_handle_length CHECK (handle IS NULL OR char_length(handle) <= 40),
  CONSTRAINT account_deletion_requests_wallet_length CHECK (wallet_address IS NULL OR char_length(wallet_address) <= 64),
  CONSTRAINT account_deletion_requests_details_length CHECK (details IS NULL OR char_length(details) <= 1000),
  CONSTRAINT account_deletion_requests_status_check CHECK (status IN ('received', 'completed', 'rejected'))
);
CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_open
  ON public.account_deletion_requests (created_at) WHERE status = 'received';

-- ── default-deny on every new table ─────────────────────────────────────────
ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_mutes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_deletions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.content_reports, public.user_blocks, public.user_mutes,
  public.legal_acceptances, public.account_deletions, public.account_deletion_requests
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.content_reports, public.user_blocks, public.user_mutes,
  public.legal_acceptances, public.account_deletions, public.account_deletion_requests
  TO service_role;

-- ── deletion ────────────────────────────────────────────────────────────────

-- Delete one person's rows from a table that may or may not exist here. The
-- repo schema is not the live schema (fcm_tokens and friends exist only
-- live), so every legacy table is looked up first. Internal: no role but the
-- owner may execute it, and it is only ever called with constant names.
CREATE FUNCTION public.trust_delete_rows_v1(p_table TEXT, p_column TEXT, p_values TEXT[])
RETURNS INTEGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  IF p_values IS NULL OR cardinality(p_values) = 0 THEN
    RETURN 0;
  END IF;
  IF to_regclass(format('public.%I', p_table)) IS NULL OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = p_table AND column_name = p_column
  ) THEN
    RETURN 0;
  END IF;
  EXECUTE format('DELETE FROM public.%I WHERE %I::text = ANY($1)', p_table, p_column) USING p_values;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.trust_delete_rows_v1(TEXT, TEXT, TEXT[]) FROM PUBLIC, anon, authenticated, service_role;

-- The one deletion path. The BFF calls it only after verifying the caller's
-- Supabase session, with that session's auth user and the canonical user it
-- maps to; it then removes the auth user through the GoTrue admin API.
--
--   ok / deleted           the account was anonymised now
--   ok / already_deleted   a retry: nothing left to do here
--   ok / no_profile        the sign-in never had a profile; recorded so the
--                          auth user can be removed
--   fail / session_mismatch  the profile is not this sign-in's
--   fail / unknown_user
CREATE FUNCTION public.delete_account_v1(p_user_id UUID, p_auth_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_existing public.account_deletions%ROWTYPE;
  v_owner    UUID;
  v_wallet   TEXT;
  v_wallets  TEXT[];
  v_ids      TEXT[];
  v_summary  JSONB := '{}'::jsonb;
  v_n        INTEGER;
BEGIN
  IF p_auth_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_auth_user');
  END IF;

  SELECT * INTO v_existing FROM public.account_deletions WHERE auth_user_id = p_auth_user_id;
  IF FOUND AND v_existing.anonymised_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'outcome', 'already_deleted',
      'user_id', v_existing.user_id, 'auth_user_id', p_auth_user_id);
  END IF;

  IF p_user_id IS NULL THEN
    INSERT INTO public.account_deletions (user_id, auth_user_id, anonymised_at, summary)
    VALUES (NULL, p_auth_user_id, NOW(), jsonb_build_object('profile', false))
    ON CONFLICT (auth_user_id) DO UPDATE SET anonymised_at = NOW();
    RETURN jsonb_build_object('ok', true, 'outcome', 'no_profile',
      'user_id', NULL, 'auth_user_id', p_auth_user_id);
  END IF;

  SELECT auth_user_id, wallet_address INTO v_owner, v_wallet
    FROM public.users WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;
  IF v_owner IS DISTINCT FROM p_auth_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'session_mismatch');
  END IF;

  SELECT array_agg(DISTINCT w) INTO v_wallets FROM (
    SELECT v_wallet AS w
    UNION SELECT wallet_address FROM public.linked_wallets WHERE user_id = p_user_id
  ) s WHERE w IS NOT NULL;
  v_wallets := COALESCE(v_wallets, ARRAY[]::TEXT[]);
  v_ids := ARRAY[p_user_id::TEXT];

  -- Wallets: an audited revocation, then the link itself, so the address can
  -- start a new account later (the full UNIQUE on wallet_address would
  -- otherwise hold it to this anonymised row forever).
  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, actor, reason)
  SELECT wallet_address, 'revoked', p_user_id, 'service', 'account deleted'
    FROM public.linked_wallets WHERE user_id = p_user_id AND revoked_at IS NULL;
  DELETE FROM public.linked_wallets WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_summary := v_summary || jsonb_build_object('linked_wallets', v_n);

  v_summary := v_summary || jsonb_build_object(
    'linked_identities', public.trust_delete_rows_v1('linked_identities', 'user_id', v_ids),
    'legacy_identity_claims', public.trust_delete_rows_v1('legacy_identity_claims', 'user_id', v_ids),
    'wallet_nonces', public.trust_delete_rows_v1('wallet_nonces', 'user_id', v_ids),
    'person_follows',
      public.trust_delete_rows_v1('person_follows', 'follower_user_id', v_ids)
      + public.trust_delete_rows_v1('person_follows', 'followee_user_id', v_ids),
    'follows',
      public.trust_delete_rows_v1('follows', 'follower_user_id', v_ids)
      + public.trust_delete_rows_v1('follows', 'followee_user_id', v_ids)
      + public.trust_delete_rows_v1('follows', 'follower_wallet', v_wallets)
      + public.trust_delete_rows_v1('follows', 'followee_wallet', v_wallets),
    'friends',
      public.trust_delete_rows_v1('friends', 'user_id', v_ids)
      + public.trust_delete_rows_v1('friends', 'friend_id', v_ids),
    'fcm_tokens', public.trust_delete_rows_v1('fcm_tokens', 'wallet_address', v_wallets),
    'pending_identity_targets', public.trust_delete_rows_v1('pending_identity_targets', 'created_by_wallet', v_wallets),
    'social_notifications', public.trust_delete_rows_v1('social_notifications', 'recipient_user_id', v_ids),
    'user_blocks',
      public.trust_delete_rows_v1('user_blocks', 'blocker_user_id', v_ids)
      + public.trust_delete_rows_v1('user_blocks', 'blocked_user_id', v_ids),
    'user_mutes',
      public.trust_delete_rows_v1('user_mutes', 'muter_user_id', v_ids)
      + public.trust_delete_rows_v1('user_mutes', 'muted_user_id', v_ids)
  );

  -- The row stays (calls reference it) and says nothing about the person.
  UPDATE public.users SET
    full_name        = 'Deleted account',
    bio              = NULL,
    email            = NULL,
    privy_id         = NULL,
    wallet_address   = NULL,
    sns_domain       = NULL,
    handle           = 'deleted_' || substr(replace(p_user_id::TEXT, '-', ''), 1, 12),
    profile_picture  = NULL,
    profile_image_id = NULL,
    last_seen_at     = NULL,
    auth_user_id     = NULL,
    deleted_at       = NOW(),
    updated_at       = NOW()
  WHERE id = p_user_id;

  INSERT INTO public.account_deletions (user_id, auth_user_id, anonymised_at, summary)
  VALUES (p_user_id, p_auth_user_id, NOW(), v_summary)
  ON CONFLICT (auth_user_id) DO UPDATE
    SET user_id = EXCLUDED.user_id, anonymised_at = NOW(), summary = EXCLUDED.summary;

  RETURN jsonb_build_object('ok', true, 'outcome', 'deleted',
    'user_id', p_user_id, 'auth_user_id', p_auth_user_id, 'summary', v_summary);
END;
$$;
REVOKE ALL ON FUNCTION public.delete_account_v1(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_account_v1(UUID, UUID) TO service_role;
COMMENT ON FUNCTION public.delete_account_v1(UUID, UUID) IS
  'Service-only, idempotent account deletion for a server-verified Supabase sign-in: anonymises public.users (calls stay as "Deleted account"), removes linked wallets/identities, follows, friends, blocks, mutes, push tokens and inbox.';
