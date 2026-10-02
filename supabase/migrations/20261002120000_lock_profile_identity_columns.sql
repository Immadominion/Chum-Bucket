-- Lock the identity columns of public.users against client writes.
--
-- Live state read on 2026-10-02: RLS on public.users has permissive
-- INSERT (WITH CHECK true) and UPDATE (USING true) policies, and anon /
-- authenticated hold column-level INSERT and UPDATE on every column except
-- auth_user_id. So any caller could repoint ANY profile's wallet_address at a
-- wallet they control — after which a wallet sign-in would carry that
-- profile over to them. It also let anyone rename anyone's @username.
--
-- This revokes exactly the identity columns. Nothing the app or the web
-- client does today writes them directly:
--   * profile creation at wallet connect goes through sync_user_by_wallet
--     (SECURITY DEFINER, unaffected);
--   * name / bio / picture edits go through update_user_profile[_with_pfp]
--     (SECURITY DEFINER, write full_name, bio, profile_picture, updated_at)
--     and a direct profile_image_id update (still allowed);
--   * the add-friend placeholder INSERTs privy_id, email, full_name,
--     wallet_address, created_at (still allowed: INSERT is not revoked for
--     those) and later fills full_name (still allowed).
-- The one client path that loses access is the mobile fallback upsert used
-- only if sync_user_by_wallet itself errors: its ON CONFLICT DO UPDATE sets
-- wallet_address. It now fails instead of silently rewriting the row.
--
-- Not changed here (recorded, separate decision): anyone can still edit any
-- profile's name/bio/picture through the permissive policy and the definer
-- profile functions. That is vandalism, not account takeover.

REVOKE UPDATE (wallet_address, handle, privy_id) ON public.users FROM anon, authenticated;
REVOKE INSERT (handle) ON public.users FROM anon, authenticated;

-- Unreachable through PostgREST, but granted; there is no reason to hold it.
REVOKE TRUNCATE ON public.users, public.linked_wallets FROM anon, authenticated;

COMMENT ON COLUMN public.users.wallet_address IS
  'The wallet a profile belongs to. Written only by SECURITY DEFINER functions and the service role; clients cannot change it (20261002120000). A wallet sign-in carries over the profile at its wallet.';
COMMENT ON COLUMN public.users.handle IS
  'The public @username, unique case-insensitively (uq_users_handle_lower). Claimed through the BFF; clients cannot set or change it directly.';
