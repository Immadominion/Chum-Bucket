-- A person follows a person, with no wallet credential required on either side.
-- The legacy public.follows graph stays intact for existing Arena consumers.
-- Apply only after the auth-identity and social-calls migrations.
DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL
     OR to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION 'canonical person follows requires identity and social calls';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.person_follows (
  follower_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  followee_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT person_follows_not_self CHECK (follower_user_id <> followee_user_id),
  CONSTRAINT person_follows_pair PRIMARY KEY (follower_user_id, followee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_person_follows_followee
  ON public.person_follows (followee_user_id, follower_user_id);

ALTER TABLE public.person_follows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.person_follows FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.person_follows TO service_role;
GRANT SELECT ON public.person_follows TO authenticated;

-- People can inspect only their own outgoing graph; all writes come through
-- the BFF after a verified session is mapped to public.users.id.
CREATE POLICY person_follows_self_select ON public.person_follows
  FOR SELECT TO authenticated
  USING (follower_user_id = public.current_app_user_id());

-- Existing calls_followers_select continues to honour legacy wallet follows.
-- This additional predicate makes walletless canonical follows visible without
-- rewriting the old graph or granting anonymous access to private calls.
CREATE POLICY calls_person_followers_select ON public.calls
  FOR SELECT TO authenticated
  USING (
    hidden_at IS NULL AND visibility = 'followers'
    AND EXISTS (
      SELECT 1 FROM public.person_follows pf
      WHERE pf.follower_user_id = public.current_app_user_id()
        AND pf.followee_user_id = calls.user_id
    )
  );
