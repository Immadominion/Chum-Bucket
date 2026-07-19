-- ============================================================================
-- SECURITY HARDENING (correction) — actually restrict anon PII columns
-- Created: 2026-07-19
-- ============================================================================
--
-- The prior migration's column-level `REVOKE SELECT (email) ...` was a NO-OP:
-- anon/authenticated hold TABLE-level SELECT on users and linked_identities,
-- and a table grant supersedes column revokes (verified live — anon could still
-- read users.email after that migration). The correct pattern is: revoke the
-- table-level grant, then re-grant SELECT on only the non-PII columns.
--
-- users: re-grant every column EXCEPT `email` (privy_id stays granted — the app
--        filters by it as anon; last_seen_at etc. all public display data).
--        A future users column is not auto-granted to anon (fail-closed) — grant
--        it explicitly if a client needs to read it as anon.
-- linked_identities: nothing reads it directly as anon (confirmed by grep) —
--        wallet_profiles (SECURITY DEFINER) is the only read path — so revoke
--        anon/authenticated table SELECT outright, closing provider_email AND
--        provider_subject.
-- ============================================================================

REVOKE SELECT ON public.users FROM anon, authenticated;
GRANT SELECT (
  id, wallet_address, privy_id, full_name, bio, profile_picture,
  profile_image_id, created_at, updated_at, sns_domain, handle, last_seen_at
) ON public.users TO anon, authenticated;

REVOKE SELECT ON public.linked_identities FROM anon, authenticated;
