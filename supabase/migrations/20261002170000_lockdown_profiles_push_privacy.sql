-- Lockdown: profiles, placeholders, push tokens and linked wallets.
--
-- Closes, in the database, the client-writable identity paths that the
-- production-readiness sweep of 2 Oct 2026 lists as B1, M1, B3 and M2:
--
--   B1  anyone could rename, re-bio or re-picture any profile: permissive
--       users INSERT/UPDATE policies, column INSERT/UPDATE grants for anon and
--       authenticated, and anon-executable update_user_profile[_with_pfp]
--       keyed only by a wallet string.
--   M1  anyone could pre-seed a profile (name, @handle) for a wallet they do
--       not hold — through a direct INSERT (the add-friend placeholder) or
--       through sync_user_by_wallet(wallet, sns) — and wallet sign-in then
--       carried that profile, name and all, to the real owner.
--   B3  fcm_tokens: anon could read every push token, wallet and display
--       name, and overwrite or delete anyone's token.
--   M2  linked_wallets was world-readable, linking people to every wallet
--       they hold (embedded wallets included, once they exist).
--
-- What replaces each path (all through the calls BFF, as the service role,
-- with the person taken from a VERIFIED Supabase session — never from a
-- wallet or id the client names):
--
--   profile edits       update_own_profile_v1   (account.updateProfile)
--   add friend by wallet add_wallet_friend_v1   (account.addWalletFriend)
--   push tokens         public.push_tokens      (account.registerPushToken)
--
-- Legacy client paths that KEEP working, deliberately:
--   * every users SELECT the app and web make (column grants unchanged);
--   * sync_user_by_wallet(wallet, sns) at wallet connect — still callable,
--     but it now only creates an empty, flagged placeholder row (no name, no
--     handle, no SNS) or touches last_seen_at, so it can no longer label a
--     wallet;
--   * fetch_user_profile(wallet) for the splash "has a name" check;
--   * the legacy friends table (reads, and the insert of an edge between two
--     rows that already exist), the challenges tables, notification_outbox
--     realtime — none are touched here.
--
-- Legacy client paths that STOP working (each has a replacement above, and the
-- current app no longer uses them):
--   * update_user_profile / update_user_profile_with_pfp (EXECUTE revoked);
--   * direct UPDATE of users (profile_image_id, full_name) and direct INSERT
--     of users rows (the add-friend placeholder);
--   * any anon/authenticated access to fcm_tokens;
--   * anon reads of linked_wallets (a signed-in person still reads their own).
--
-- Carry-over (bind_wallet_session_v1) keeps its contract, with one change: a
-- row flagged is_placeholder is carried WITHOUT anything a stranger could have
-- written on it — full_name, bio, handle, sns_domain, profile_picture and the
-- placeholder privy_id/email are cleared — so the owner starts clean and
-- claims their own @username. Existing add-friend placeholders (the
-- 'wallet_xxxxxxxx' / '@temp.com' pattern, never bound to a sign-in) are
-- flagged below.
--
-- Additive in shape: one column on users, one on friends, one new table, three
-- new service-role functions, two functions replaced with the same signature.
-- No table, column, row or legacy function is dropped.
--
-- Proven on a throwaway PostgreSQL 15 that reproduces the live rights
-- (chumbucket-social-calls-api tests/lockdown.postgres.test.ts). The rights it
-- relies on are written down in docs/schema/legacy-rights-2026-10-02.sql.
--
-- Apply AFTER: 20261002090000_wallet_sign_in_and_usernames.sql,
-- 20261002120000_lock_profile_identity_columns.sql, and only once the BFF that
-- serves account.* is deployed (otherwise profile edits have nowhere to go).

DO $$
BEGIN
  IF to_regprocedure('public.bind_wallet_session_v1(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'lockdown requires 20261002090000_wallet_sign_in_and_usernames.sql';
  END IF;
  IF to_regprocedure('public.sync_user_by_wallet(text,text)') IS NULL THEN
    RAISE EXCEPTION 'lockdown expects sync_user_by_wallet(text, text) (20260715134226)';
  END IF;
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION 'lockdown requires public.current_app_user_id() (20260913120000)';
  END IF;
  IF to_regclass('public.friends') IS NULL THEN
    RAISE EXCEPTION 'lockdown expects the legacy public.friends table';
  END IF;
  -- ON CONFLICT (wallet_address) below needs exactly this.
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
     WHERE i.indrelid = 'public.users'::regclass AND i.indisunique
       AND i.indnatts = 1 AND a.attname = 'wallet_address' AND i.indpred IS NULL
  ) THEN
    RAISE EXCEPTION 'lockdown expects a UNIQUE index on public.users(wallet_address)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_index i
     WHERE i.indrelid = 'public.friends'::regclass AND i.indisunique AND i.indnatts = 2
  ) THEN
    RAISE EXCEPTION 'lockdown expects UNIQUE (user_id, friend_id) on public.friends';
  END IF;
END;
$$;

-- ── 1. placeholders are marked, and the old ones are found ─────────────────

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_placeholder BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.users.is_placeholder IS
  'True for a row created on behalf of a wallet by someone who did not prove they hold it (add friend by wallet, legacy wallet connect). Wallet sign-in carries such a row over with its display fields cleared (bind_wallet_session_v1).';

-- The add-friend path wrote exactly this shape (unified_database_service.dart
-- addFriend; web lib/social.ts addSupabaseFriend). Only rows nobody has signed
-- in to are flagged: a bound row already belongs to its owner.
UPDATE public.users
   SET is_placeholder = true
 WHERE auth_user_id IS NULL
   AND is_placeholder = false
   AND privy_id LIKE 'wallet\_%'
   AND email LIKE 'wallet\_%@temp.com';

-- ── 2. no client writes users rows any more ────────────────────────────────

-- Privileges are the real gate (checked before RLS). A table-level REVOKE also
-- removes the column-level INSERT/UPDATE grants anon/authenticated held.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.users FROM anon, authenticated;

-- And the permissive policies go too, so a future GRANT cannot quietly reopen
-- them. The two live names, then anything else that writes.
DROP POLICY IF EXISTS users_insert ON public.users;
DROP POLICY IF EXISTS users_update ON public.users;
DO $$
DECLARE
  p RECORD;
BEGIN
  FOR p IN
    SELECT polname, polcmd FROM pg_policy
     WHERE polrelid = 'public.users'::regclass AND polcmd IN ('a', 'w', 'd')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.users', p.polname);
  END LOOP;
  FOR p IN
    SELECT polname FROM pg_policy WHERE polrelid = 'public.users'::regclass AND polcmd = '*'
  LOOP
    -- An ALL policy also governs SELECT; it is left in place (the privilege
    -- revoke above already stops every write) and reported.
    RAISE NOTICE 'public.users keeps ALL-command policy % (writes are blocked by privileges)', p.polname;
  END LOOP;
END;
$$;

DO $$
BEGIN
  IF to_regprocedure('public.update_user_profile(text,text,text)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.update_user_profile(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
  END IF;
  IF to_regprocedure('public.update_user_profile_with_pfp(text,text,text,text)') IS NOT NULL THEN
    REVOKE EXECUTE ON FUNCTION public.update_user_profile_with_pfp(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
  END IF;
END;
$$;

-- ── 3. wallet connect can no longer label a wallet ─────────────────────────
--
-- Same signature and return type, still anon-executable: installed apps call it
-- at every wallet connect and ignore the result. It proves nothing about the
-- wallet, so it may only (a) create an EMPTY placeholder row for a wallet that
-- has none, or (b) note that the wallet was seen. It never writes a name, a
-- handle, an SNS domain or a wallet link, and p_sns_domain is ignored.

CREATE OR REPLACE FUNCTION public.sync_user_by_wallet(
  p_wallet_address TEXT,
  p_sns_domain TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_wallet  TEXT := btrim(coalesce(p_wallet_address, ''));
  v_user_id UUID;
BEGIN
  IF v_wallet !~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$' THEN
    RAISE EXCEPTION 'wallet address is required';
  END IF;

  SELECT id INTO v_user_id FROM public.users WHERE wallet_address = v_wallet;
  IF v_user_id IS NULL THEN
    INSERT INTO public.users (wallet_address, is_placeholder, created_at, updated_at, last_seen_at)
    VALUES (v_wallet, true, NOW(), NOW(), NOW())
    ON CONFLICT (wallet_address) DO NOTHING
    RETURNING id INTO v_user_id;
    IF v_user_id IS NULL THEN
      SELECT id INTO v_user_id FROM public.users WHERE wallet_address = v_wallet;
    END IF;
  ELSE
    UPDATE public.users SET last_seen_at = NOW() WHERE id = v_user_id;
  END IF;

  RETURN v_user_id;
END;
$$;

COMMENT ON FUNCTION public.sync_user_by_wallet(TEXT, TEXT) IS
  'Legacy wallet-connect hook, kept for installed apps. Creates an empty placeholder row for an unseen wallet or stamps last_seen_at. Writes no name, handle, SNS domain or wallet link: it proves nothing about who holds the wallet (20261002170000).';

-- ── 4. carry-over never carries a stranger's words ─────────────────────────

CREATE OR REPLACE FUNCTION public.bind_wallet_session_v1(p_auth_user_id UUID, p_wallet_address TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_existing    UUID;
  v_target      UUID;
  v_owner       UUID;
  v_placeholder BOOLEAN;
  v_wallet      TEXT := nullif(btrim(coalesce(p_wallet_address, '')), '');
BEGIN
  IF p_auth_user_id IS NULL OR v_wallet IS NULL
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_input');
  END IF;

  SELECT id INTO v_existing FROM public.users WHERE auth_user_id = p_auth_user_id;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'user_id', v_existing, 'outcome', 'existing');
  END IF;

  SELECT id, auth_user_id, is_placeholder INTO v_target, v_owner, v_placeholder
    FROM public.users WHERE wallet_address = v_wallet
    FOR UPDATE;
  IF v_target IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_profile');
  END IF;
  IF v_owner IS NOT NULL THEN
    -- Already reachable through another sign-in. Never moved silently.
    RETURN jsonb_build_object('ok', false, 'reason', 'owned');
  END IF;

  IF v_placeholder THEN
    -- Everything on this row was written by someone who never proved they
    -- hold the wallet. The owner keeps the row (friend edges, legacy history)
    -- and none of the words.
    UPDATE public.users
       SET auth_user_id = p_auth_user_id,
           full_name = NULL, bio = NULL, handle = NULL, sns_domain = NULL,
           profile_picture = NULL, privy_id = NULL, email = NULL,
           is_placeholder = false, updated_at = NOW()
     WHERE id = v_target AND auth_user_id IS NULL;
  ELSE
    UPDATE public.users SET auth_user_id = p_auth_user_id, updated_at = NOW()
     WHERE id = v_target AND auth_user_id IS NULL;
  END IF;

  UPDATE public.linked_wallets
     SET siws_proof_version = 1, verified_at = NOW(), revoked_at = NULL,
         last_signed_at = NOW(), updated_at = NOW()
   WHERE wallet_address = v_wallet AND user_id = v_target;
  IF NOT FOUND THEN
    INSERT INTO public.linked_wallets (
      user_id, wallet_address, wallet_type, is_primary,
      first_seen_at, last_signed_at, siws_proof_version, verified_at
    ) VALUES (v_target, v_wallet, 'mwa',
      NOT EXISTS (SELECT 1 FROM public.linked_wallets w WHERE w.user_id = v_target AND w.revoked_at IS NULL),
      NOW(), NOW(), 1, NOW());
  END IF;
  INSERT INTO public.wallet_link_audit (wallet_address, action, from_user_id, to_user_id, reason)
  VALUES (v_wallet, 'reaffirmed', v_target, v_target,
          CASE WHEN v_placeholder
               THEN 'placeholder carried over to wallet sign-in; display fields cleared'
               ELSE 'existing account carried over to wallet sign-in' END);

  RETURN jsonb_build_object('ok', true, 'user_id', v_target,
                            'outcome', CASE WHEN v_placeholder THEN 'carried_placeholder' ELSE 'carried' END);
END;
$$;
REVOKE ALL ON FUNCTION public.bind_wallet_session_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bind_wallet_session_v1(UUID, TEXT) TO service_role;

-- ── 5. the one way to edit a profile ───────────────────────────────────────
--
-- p_user_id is the canonical id the BFF resolved from a verified session.
-- NULL means "leave unchanged". An empty bio clears it. The avatar is one of
-- the app's five fixed pictures (assets/images/ai_gen/profile_images/{1..5}).

CREATE FUNCTION public.update_own_profile_v1(
  p_user_id      UUID,
  p_display_name TEXT DEFAULT NULL,
  p_bio          TEXT DEFAULT NULL,
  p_avatar_id    INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_name TEXT := CASE WHEN p_display_name IS NULL THEN NULL ELSE btrim(p_display_name) END;
  v_bio  TEXT := CASE WHEN p_bio IS NULL THEN NULL ELSE btrim(p_bio) END;
  v_row  public.users%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;
  IF p_display_name IS NULL AND p_bio IS NULL AND p_avatar_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'nothing_to_change');
  END IF;
  IF v_name IS NOT NULL AND (length(v_name) NOT BETWEEN 1 AND 60 OR v_name ~ '[[:cntrl:]]') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_name');
  END IF;
  -- A bio may break lines; nothing else invisible.
  IF v_bio IS NOT NULL AND (length(v_bio) > 280 OR replace(v_bio, E'\n', '') ~ '[[:cntrl:]]') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_bio');
  END IF;
  IF p_avatar_id IS NOT NULL AND p_avatar_id NOT BETWEEN 1 AND 5 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_avatar');
  END IF;

  UPDATE public.users
     SET full_name        = coalesce(v_name, full_name),
         bio              = CASE WHEN v_bio IS NULL THEN bio ELSE nullif(v_bio, '') END,
         profile_image_id = coalesce(p_avatar_id, profile_image_id),
         updated_at       = NOW()
   WHERE id = p_user_id
     AND auth_user_id IS NOT NULL
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    -- No such account, or one nobody has signed in to: never edited here.
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;

  RETURN jsonb_build_object('ok', true, 'profile', jsonb_build_object(
    'user_id', v_row.id, 'display_name', v_row.full_name, 'bio', v_row.bio,
    'avatar_id', v_row.profile_image_id, 'handle', v_row.handle));
END;
$$;
REVOKE ALL ON FUNCTION public.update_own_profile_v1(UUID, TEXT, TEXT, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_own_profile_v1(UUID, TEXT, TEXT, INTEGER) TO service_role;
COMMENT ON FUNCTION public.update_own_profile_v1(UUID, TEXT, TEXT, INTEGER) IS
  'Service-only: the signed-in person edits their own display name, bio and avatar (1-5). The BFF passes the canonical id it resolved from a verified Supabase session; a row with no sign-in bound to it is never edited.';

-- ── 6. add a friend by wallet, server-side ─────────────────────────────────
--
-- The name the adder types is THEIR label for the friend, so it lives on their
-- own friendship edge (friends.nickname), never on the shared users row.

ALTER TABLE public.friends
  ADD COLUMN IF NOT EXISTS nickname TEXT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'friends_nickname_length') THEN
    ALTER TABLE public.friends
      ADD CONSTRAINT friends_nickname_length CHECK (nickname IS NULL OR length(nickname) BETWEEN 1 AND 60);
  END IF;
END;
$$;
COMMENT ON COLUMN public.friends.nickname IS
  'What user_id calls friend_id. Private label written by add_wallet_friend_v1; never copied onto the friend''s profile.';

CREATE FUNCTION public.add_wallet_friend_v1(
  p_user_id       UUID,
  p_friend_wallet TEXT,
  p_nickname      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_wallet   TEXT := btrim(coalesce(p_friend_wallet, ''));
  v_nick     TEXT := nullif(btrim(coalesce(p_nickname, '')), '');
  v_friend   UUID;
  v_created  BOOLEAN := false;
  v_already  BOOLEAN;
BEGIN
  IF p_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = p_user_id AND auth_user_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unknown_user');
  END IF;
  IF v_wallet !~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_wallet');
  END IF;
  IF v_nick IS NOT NULL AND (length(v_nick) > 60 OR v_nick ~ '[[:cntrl:]]') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_nickname');
  END IF;

  -- The account that holds this wallet: its profile wallet, else a verified
  -- active link, else an empty placeholder (no name — see the header).
  SELECT id INTO v_friend FROM public.users WHERE wallet_address = v_wallet;
  IF v_friend IS NULL THEN
    SELECT w.user_id INTO v_friend FROM public.linked_wallets w
     WHERE w.wallet_address = v_wallet AND w.revoked_at IS NULL AND w.verified_at IS NOT NULL
     LIMIT 1;
  END IF;
  IF v_friend IS NULL THEN
    INSERT INTO public.users (wallet_address, is_placeholder, created_at, updated_at)
    VALUES (v_wallet, true, NOW(), NOW())
    ON CONFLICT (wallet_address) DO NOTHING
    RETURNING id INTO v_friend;
    v_created := v_friend IS NOT NULL;
    IF v_friend IS NULL THEN
      SELECT id INTO v_friend FROM public.users WHERE wallet_address = v_wallet;
    END IF;
  END IF;

  IF v_friend = p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'self');
  END IF;

  v_already := EXISTS (
    SELECT 1 FROM public.friends
     WHERE (user_id = p_user_id AND friend_id = v_friend)
        OR (user_id = v_friend AND friend_id = p_user_id));

  -- The legacy graph is symmetric and accepted on both sides; kept as it is.
  INSERT INTO public.friends (user_id, friend_id, status, nickname, created_at)
  VALUES (p_user_id, v_friend, 'accepted', v_nick, NOW())
  ON CONFLICT (user_id, friend_id) DO UPDATE
    SET nickname = coalesce(EXCLUDED.nickname, public.friends.nickname);
  INSERT INTO public.friends (user_id, friend_id, status, created_at)
  VALUES (v_friend, p_user_id, 'accepted', NOW())
  ON CONFLICT (user_id, friend_id) DO NOTHING;

  RETURN jsonb_build_object('ok', true, 'friend_user_id', v_friend,
                            'created_placeholder', v_created, 'already_friends', v_already);
END;
$$;
REVOKE ALL ON FUNCTION public.add_wallet_friend_v1(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.add_wallet_friend_v1(UUID, TEXT, TEXT) TO service_role;
COMMENT ON FUNCTION public.add_wallet_friend_v1(UUID, TEXT, TEXT) IS
  'Service-only: the signed-in person adds a friend by wallet. Creates at most an empty, flagged placeholder for an unknown wallet; the typed name is stored as the adder''s private nickname on their own edge.';

-- ── 7. push tokens, keyed by the canonical person ──────────────────────────

CREATE TABLE IF NOT EXISTS public.push_tokens (
  token      TEXT PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  platform   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT push_tokens_platform_check CHECK (platform IN ('android', 'ios')),
  CONSTRAINT push_tokens_token_shape CHECK (length(token) BETWEEN 20 AND 4096 AND token ~ '^[A-Za-z0-9:_-]+$')
);
CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON public.push_tokens (user_id);
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_tokens FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.push_tokens TO service_role;
COMMENT ON TABLE public.push_tokens IS
  'FCM registration tokens, one row per device, owned by the canonical person who registered it through the BFF. Service role only: no client reads or writes.';

-- The legacy wallet-keyed registry: nobody but the service role.
DO $$
BEGIN
  IF to_regclass('public.fcm_tokens') IS NOT NULL THEN
    ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;
    REVOKE ALL ON public.fcm_tokens FROM PUBLIC, anon, authenticated;
    GRANT ALL ON public.fcm_tokens TO service_role;
    COMMENT ON TABLE public.fcm_tokens IS
      'LEGACY wallet-keyed push tokens. Service role only since 20261002170000; the app registers in public.push_tokens through the BFF.';
  ELSE
    RAISE NOTICE 'public.fcm_tokens not present; nothing to lock';
  END IF;
END;
$$;

-- ── 8. linked wallets are private to their owner ───────────────────────────

DROP POLICY IF EXISTS linked_wallets_public_select ON public.linked_wallets;
DROP POLICY IF EXISTS linked_wallets_own_select ON public.linked_wallets;
CREATE POLICY linked_wallets_own_select ON public.linked_wallets
  FOR SELECT TO authenticated
  USING (user_id = public.current_app_user_id());
REVOKE ALL ON public.linked_wallets FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.linked_wallets FROM authenticated;
GRANT SELECT ON public.linked_wallets TO authenticated;
GRANT ALL ON public.linked_wallets TO service_role;
