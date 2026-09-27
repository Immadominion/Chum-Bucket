-- Explicit Google/Supabase onboarding. Additive: no legacy row is merged,
-- repointed, renamed or deleted. The BFF verifies the Supabase session BEFORE
-- supplying p_auth_user_id. Clients cannot execute this service-only function.
CREATE FUNCTION public.create_social_person_v1(p_auth_user_id UUID, p_display_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_id UUID;
  v_new_id UUID := gen_random_uuid();
  v_name TEXT := btrim(p_display_name);
BEGIN
  IF p_auth_user_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users WHERE id = p_auth_user_id
  ) THEN
    RAISE EXCEPTION 'verified auth user required' USING ERRCODE = '22023';
  END IF;
  IF v_name IS NULL OR length(v_name) NOT BETWEEN 1 AND 60
     OR v_name ~ '[[:cntrl:]]' THEN
    RAISE EXCEPTION 'display name must contain 1 to 60 printable characters'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.users (id, auth_user_id, full_name, handle)
    VALUES (v_new_id, p_auth_user_id, v_name, 'caller_' || replace(v_new_id::TEXT, '-', ''))
    ON CONFLICT (auth_user_id) DO NOTHING;

  -- Concurrent replays converge via users_auth_user_id_key. An existing
  -- profile (including a previously verified legacy link) is left untouched.
  SELECT id INTO STRICT v_id FROM public.users WHERE auth_user_id = p_auth_user_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_social_person_v1(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_social_person_v1(UUID, TEXT) TO service_role;
COMMENT ON FUNCTION public.create_social_person_v1(UUID, TEXT) IS
  'Service-only idempotent onboarding for a server-verified Supabase subject; never claims or merges a legacy account.';
