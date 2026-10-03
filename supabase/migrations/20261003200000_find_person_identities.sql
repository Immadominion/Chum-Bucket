-- Find a person to add as a friend: by X handle, or by wallet — additive.
--
-- Adding a friend is now a follow of a real Chumbucket person, confirmed on a
-- card before anything is written (BFF `people.find`, then `people.follow`).
-- Two of the things that card needs live where the BFF cannot read them:
--
--   * Who signed in with which X account. Supabase Auth keeps it in
--     auth.identities (provider 'x', or 'twitter' for the older OAuth 1.0a
--     provider; identity_data carries user_name / preferred_username and the
--     profile picture). PostgREST does not expose the auth schema, so only a
--     definer function can answer "who is @name on X?". Accounts linked by the
--     old wallet-era flow are in public.linked_identities and count too.
--   * Whether a wallet belongs to a REAL person. public.users.is_placeholder
--     marks the empty rows the old add-friend path and legacy wallet connect
--     created for a wallet nobody proved they hold; those are not people, and
--     a lookup must never present one as somebody to follow.
--
-- Two read-only, service-role-only functions:
--
--   person_x_identities_v1(p_x_handle, p_user_ids)
--       by handle: the people whose X account has that username (case-
--       insensitive), most recently seen first; by ids (at most 50): the X
--       account of each of those people, when they have one.
--       Returns user_id, x_username, x_avatar_url, seen_at. Never an email,
--       a wallet, a provider subject or a token.
--   person_for_wallet_v1(p_wallet)
--       the person holding that wallet (users.wallet_address, then an
--       unrevoked linked_wallets row), or NULL. Never a placeholder.
--
-- Both leave out deleted accounts (users.deleted_at) and placeholders. Nothing
-- is written, no table or column is added, nothing existing changes, and the
-- functions are not callable by anon or authenticated: the BFF calls them for
-- a signed-in person, rate-limited, and returns a person card with no wallet.
--
-- The handle lookup reads auth.identities without an index on the username
-- (the auth schema belongs to Supabase Auth; this migration adds nothing to
-- it). That is a scan of the X identities, fine at today's size; revisit with
-- a mirrored, indexed column if X sign-ins reach the hundreds of thousands.
--
-- Proven on a throwaway PostgreSQL 15 (chumbucket-social-calls-api
-- tests/findPersonIdentities.postgres.test.ts).
--
-- Apply AFTER 20261002171000_lockdown_profiles_push_privacy.sql (is_placeholder)
-- and 20261002180000_trust_safety_and_account.sql (deleted_at), and BEFORE
-- deploying a BFF that serves people.find — without these functions that
-- procedure answers "We couldn't look that up right now" rather than guess.

DO $$
BEGIN
  IF to_regclass('auth.identities') IS NULL THEN
    RAISE EXCEPTION 'find_person_identities expects Supabase Auth''s auth.identities table';
  END IF;
  IF to_regclass('public.linked_identities') IS NULL THEN
    RAISE EXCEPTION 'find_person_identities requires public.linked_identities (20260715134226)';
  END IF;
  IF to_regclass('public.linked_wallets') IS NULL THEN
    RAISE EXCEPTION 'find_person_identities requires public.linked_wallets (20260913121500)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'auth_user_id') THEN
    RAISE EXCEPTION 'find_person_identities requires users.auth_user_id (20260913120000)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'is_placeholder') THEN
    RAISE EXCEPTION 'find_person_identities requires 20261002171000_lockdown_profiles_push_privacy.sql (users.is_placeholder)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'deleted_at') THEN
    RAISE EXCEPTION 'find_person_identities requires 20261002180000_trust_safety_and_account.sql (users.deleted_at)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'linked_wallets' AND column_name = 'revoked_at') THEN
    RAISE EXCEPTION 'find_person_identities requires linked_wallets.revoked_at (20260913121500)';
  END IF;
END;
$$;

-- ── who is @name on X, and which X account does each person have ───────────
--
-- Exactly one argument: a handle (1–15 of A–Z a–z 0–9 _, an optional leading
-- @, any case), or 1–50 user ids. Anything else returns no rows. One row per
-- person; when a person has both an Auth identity and an old linked identity,
-- the most recently seen one wins.

CREATE FUNCTION public.person_x_identities_v1(
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
  x AS (
    SELECT u.id AS user_id,
           coalesce(nullif(btrim(i.identity_data ->> 'user_name'), ''),
                    nullif(btrim(i.identity_data ->> 'preferred_username'), ''),
                    nullif(btrim(i.identity_data ->> 'screen_name'), '')) AS x_username,
           coalesce(nullif(btrim(i.identity_data ->> 'avatar_url'), ''),
                    nullif(btrim(i.identity_data ->> 'picture'), '')) AS x_avatar_url,
           coalesce(i.last_sign_in_at, i.updated_at, i.created_at) AS seen_at
      FROM auth.identities i
      JOIN public.users u ON u.auth_user_id = i.user_id
     WHERE i.provider IN ('x', 'twitter')
       AND u.deleted_at IS NULL
       AND NOT u.is_placeholder
       AND (p_user_ids IS NULL OR u.id = ANY (p_user_ids))
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

REVOKE ALL ON FUNCTION public.person_x_identities_v1(TEXT, UUID[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.person_x_identities_v1(TEXT, UUID[]) TO service_role;
COMMENT ON FUNCTION public.person_x_identities_v1(TEXT, UUID[]) IS
  'Service-only, read-only: the people whose X account has this username (auth.identities provider x/twitter, or an old linked identity), or the X account of up to 50 given people. Never placeholders or deleted accounts; never an email, wallet or provider subject.';

-- ── the person holding a wallet ─────────────────────────────────────────────

CREATE FUNCTION public.person_for_wallet_v1(p_wallet TEXT)
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT c.id
    FROM (
      SELECT u.id, 0 AS preference
        FROM public.users u
       WHERE u.wallet_address = btrim(p_wallet)
         AND u.deleted_at IS NULL
         AND NOT u.is_placeholder
      UNION ALL
      SELECT u.id, 1
        FROM public.linked_wallets w
        JOIN public.users u ON u.id = w.user_id
       WHERE w.wallet_address = btrim(p_wallet)
         AND w.revoked_at IS NULL
         AND u.deleted_at IS NULL
         AND NOT u.is_placeholder
    ) c
   ORDER BY c.preference
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.person_for_wallet_v1(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.person_for_wallet_v1(TEXT) TO service_role;
COMMENT ON FUNCTION public.person_for_wallet_v1(TEXT) IS
  'Service-only, read-only: the real (not placeholder, not deleted) person holding this wallet, as users.wallet_address or an unrevoked linked wallet, or NULL.';
