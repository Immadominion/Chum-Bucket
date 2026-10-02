-- ============================================================================
-- LEGACY SCHEMA RIGHTS SNAPSHOT — reconstructed, schema only, 2 Oct 2026
-- ============================================================================
--
-- What this is: the policies, grants and function signatures on the LEGACY
-- tables that 20261002170000_lockdown_profiles_push_privacy.sql relies on,
-- written down because none of them are in version control (prod readiness
-- M19: the eight *_remote_baseline.sql files are two-line placeholders).
--
-- What this is NOT: a dump. Nothing here was read from production. Each line
-- carries its source:
--   [repo]      a migration or schema file in this repository
--   [live]      the live state recorded in a migration comment written after
--               reading production (20261002120000_lock_profile_identity_columns.sql,
--               20260715134226 header, 20260719161500 header)
--   [audit]     the 2 Oct 2026 readiness sweep (anon HEAD row counts on the
--               public REST endpoint; no row data)
--   [client]    inferred from what the shipped app and web client do with the
--               anon key and evidently succeed at
--   [unknown]   not knowable from here — the owner must confirm
--
-- The throwaway-PostgreSQL proof of the lockdown
-- (chumbucket-social-calls-api tests/lockdown.postgres.test.ts, LIVE_LEGACY)
-- builds exactly this state, then applies the real migrations.
--
-- OWNER: replace this file with the real thing and diff it against the above
-- before applying 20261002170000:
--   supabase db dump --linked --schema-only --schema public > docs/schema/live-public-schema.sql
--   (and, for the edge functions: supabase functions download send-challenge-notification
--    / analytics-telegram, then review their auth)
-- ============================================================================

-- A record, not a migration: refuse to run.
DO $$ BEGIN RAISE EXCEPTION 'docs/schema/legacy-rights-2026-10-02.sql is a documentation snapshot; do not run it'; END $$;

-- ── public.users ────────────────────────────────────────────────────────────
-- Columns [repo 001/002/20260715134226/20260913120000]:
--   id uuid pk, wallet_address text UNIQUE, privy_id text UNIQUE, email text,
--   full_name text, bio text, profile_picture text, profile_image_id int DEFAULT 1,
--   sns_domain text, handle text, last_seen_at timestamptz,
--   auth_user_id uuid UNIQUE, created_at, updated_at
-- + uq_users_handle_lower ON (lower(handle)) [repo 20261002090000]
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;                      -- [repo 001]
CREATE POLICY users_insert ON public.users FOR INSERT WITH CHECK (true);  -- [repo 001][live]
CREATE POLICY users_select ON public.users FOR SELECT USING (true);       -- [repo 001][live]
CREATE POLICY users_update ON public.users FOR UPDATE USING (true);       -- [repo 001][live]
-- 002's users_read_own_wallet / users_update_own_wallet used invalid
-- `CREATE POLICY IF NOT EXISTS` syntax and most likely do not exist [unknown].
GRANT SELECT (id, wallet_address, privy_id, full_name, bio, profile_picture,
  profile_image_id, created_at, updated_at, sns_domain, handle, last_seen_at)
  ON public.users TO anon, authenticated;                                 -- [repo 20260719161500][live]
-- INSERT/UPDATE: column grants on every column but auth_user_id           -- [live 20261002120000]
GRANT INSERT (bio, created_at, email, full_name, handle, id, last_seen_at, privy_id,
  profile_image_id, profile_picture, sns_domain, updated_at, wallet_address),
      UPDATE (bio, created_at, email, full_name, handle, id, last_seen_at, privy_id,
  profile_image_id, profile_picture, sns_domain, updated_at, wallet_address)
  ON public.users TO anon, authenticated;
REVOKE UPDATE (wallet_address, handle, privy_id) ON public.users FROM anon, authenticated; -- [repo 20261002120000]
REVOKE INSERT (handle) ON public.users FROM anon, authenticated;                          -- [repo 20261002120000]
GRANT DELETE ON public.users TO anon, authenticated;  -- [repo 001 GRANT ALL; no DELETE policy, so RLS refuses]
GRANT ALL ON public.users TO service_role;            -- [repo 20260913120000]

-- ── public.linked_wallets ───────────────────────────────────────────────────
-- [repo 20260715134226 + 20260913121500]; 210 rows anon-readable [audit]
ALTER TABLE public.linked_wallets ENABLE ROW LEVEL SECURITY;
CREATE POLICY linked_wallets_public_select ON public.linked_wallets FOR SELECT USING (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.linked_wallets TO anon, authenticated; -- [repo 001 default-privileges][inferred]
-- no INSERT/UPDATE/DELETE policy: writes refused by RLS [repo 20260913121500 header]

-- ── public.friends ──────────────────────────────────────────────────────────
-- [repo 001]: UNIQUE(user_id, friend_id), CHECK(user_id <> friend_id)
ALTER TABLE public.friends ENABLE ROW LEVEL SECURITY;
CREATE POLICY friends_all ON public.friends FOR ALL USING (true) WITH CHECK (true); -- [repo 001][client]
GRANT ALL ON public.friends TO anon, authenticated;                                  -- [repo 001][client]
-- Unchanged by the lockdown except the new nullable column `nickname`.

-- ── public.fcm_tokens ───────────────────────────────────────────────────────
-- Not defined in any SQL file [repo]. Columns from the client upsert
-- (fcm_token_service.dart) and 009_add_network_column.sql:
--   wallet_address text UNIQUE (onConflict target), fcm_token text,
--   platform text, user_display_name text, network text, updated_at timestamptz
-- 168 rows readable with the anon key [audit]; the app upserted and deleted
-- rows by wallet as anon [client] — so, at least:
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fcm_tokens TO anon;     -- [audit][client]
-- RLS: either disabled, or enabled with a permissive ALL policy [unknown].

-- ── functions the app or web call with the anon key ────────────────────────
-- sync_user_by_wallet(p_wallet_address text, p_sns_domain text DEFAULT NULL)
--   RETURNS uuid, SECURITY DEFINER, EXECUTE to PUBLIC                  -- [repo 20260715134226][client]
-- fetch_user_profile(p_privy_id text) RETURNS TABLE(...)               -- [repo 001][client]
--   returns email among its columns; SECURITY DEFINER or not [unknown]
-- update_user_profile(p_privy_id text, p_full_name text, p_bio text) RETURNS void          -- [repo 001][live]
-- update_user_profile_with_pfp(p_privy_id text, p_full_name text, p_bio text, p_pfp_path text) -- [repo 001][live]
--   both described live as definer and anon-executable [live 20261002120000]
-- get_notifications / unread_notification_count / pending_targets_for_wallet:
--   SECURITY DEFINER, wallet as an argument, never revoked from anon     -- [repo][pivot-contracts §8.3]
--   NOT changed by the lockdown: notification_outbox is itself SELECT USING (true)
--   for the Arena realtime subscription, so revoking the RPCs alone closes nothing.

-- ── edge functions ─────────────────────────────────────────────────────────
-- send-challenge-notification: invoked by the app with an arbitrary target
--   wallet [client]; source and auth not in the repo [unknown]. The app no
--   longer calls it after this package; the deployed function still accepts
--   calls from anyone holding the anon key until the owner removes or gates it.
-- analytics-telegram: invoked with wallet + display name [client]; out of scope
--   here (prod readiness M6).
