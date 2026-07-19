-- ============================================================================
-- SECURITY HARDENING — lock down pending_identity_targets + revoke PII columns
-- Created: 2026-07-19
-- ============================================================================
--
-- Two confirmed, live-verified integrity fixes (both additive, no legitimate
-- app path depends on the access being removed — the app reaches this data only
-- through SECURITY DEFINER RPCs, never as anon via PostgREST):
--
-- 1. pending_identity_targets (added earlier today) was created without RLS and
--    inherited Supabase's default broad anon/authenticated table grants — so the
--    wallet-signature auth + rate-limit on create_pending_target were trivially
--    bypassable by writing the table directly through PostgREST (spoof
--    created_by_wallet, repoint resolved_wallet_address, delete others' rows).
--    The client only ever goes through tRPC -> service_role, and
--    create_pending_target / pending_targets_for_wallet are SECURITY DEFINER, so
--    enabling RLS with no anon policy + revoking table grants breaks nothing.
--
-- 2. Private PII columns were anon-readable via direct PostgREST column access,
--    bypassing the wallet_profiles RPC (which correctly exposes only public
--    display fields). users.email and linked_identities.provider_email /
--    provider_subject are never read by any anon app path — confirmed by grep —
--    so revoking anon/authenticated column SELECT closes the leak with no
--    behavior change. (notification_outbox + users.privy_id are intentionally
--    NOT touched here: mobile Realtime subscribes to the outbox as anon and
--    filters users by privy_id as anon, so those need a read re-route first and
--    are handled separately, not with a blanket revoke that would break live
--    claim notifications.)
-- ============================================================================

-- 1. pending_identity_targets: RLS on, no anon policy, no anon table grants.
ALTER TABLE public.pending_identity_targets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pending_identity_targets FROM anon, authenticated;
GRANT ALL ON public.pending_identity_targets TO service_role;

-- 2. Revoke anon/authenticated column SELECT on private identity fields.
--    wallet_profiles (SECURITY DEFINER) still reads them as the owner.
REVOKE SELECT (email) ON public.users FROM anon, authenticated;
REVOKE SELECT (provider_email, provider_subject) ON public.linked_identities FROM anon, authenticated;

COMMENT ON TABLE public.pending_identity_targets IS 'RLS-locked; reachable only via SECURITY DEFINER RPCs (create_pending_target / pending_targets_for_wallet) after backend wallet-sig auth. Never write this table directly.';
