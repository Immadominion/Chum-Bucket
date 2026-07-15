-- ============================================================================
-- HARDENING: pin search_path on every SECURITY DEFINER function
-- Created: 2026-07-16
-- ============================================================================
--
-- SECURITY DEFINER functions run with the owner's privileges. Without an
-- explicit search_path, an unqualified built-in (trim/count/now/…) could resolve
-- a pg_temp shadow first — the classic definer search_path hijack, and exactly
-- what Supabase's `function_search_path_mutable` linter flags. We pin
-- `pg_catalog, public, pg_temp`: built-ins resolve from pg_catalog first (can't
-- be shadowed), our schema-qualified `public.*` refs still resolve, and pg_temp
-- is searched LAST rather than implicitly first. All function bodies already
-- schema-qualify their table references, so this is behavior-preserving.
-- ============================================================================

-- foundation (social predictions)
ALTER FUNCTION public.sync_user_by_wallet(TEXT, TEXT) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.record_prediction_call(TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, BIGINT, JSONB) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.confirm_prediction_signature(TEXT, TEXT, TEXT, BIGINT, JSONB) SET search_path = pg_catalog, public, pg_temp;

-- reconciler / settlement
ALTER FUNCTION public.apply_settlement(TEXT, TEXT, TEXT, TEXT, TEXT, BIGINT, NUMERIC, NUMERIC, INTEGER, INTEGER, BIGINT, BIGINT, TEXT, JSONB) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.apply_claim_fact(TEXT, TEXT, TEXT, TEXT, NUMERIC, BIGINT) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.advance_indexer_cursor(TEXT, TEXT, TEXT, TEXT, BIGINT) SET search_path = pg_catalog, public, pg_temp;

-- social graph + feeds
ALTER FUNCTION public.follow_wallet(TEXT, TEXT, TEXT) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.unfollow_wallet(TEXT, TEXT, TEXT) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.feed_following(TEXT, TEXT, INTEGER) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.follow_counts(TEXT, TEXT) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.is_following(TEXT, TEXT, TEXT) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.match_callers(TEXT, TEXT, INTEGER) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.social_leaderboard(TEXT, INTEGER) SET search_path = pg_catalog, public, pg_temp;
