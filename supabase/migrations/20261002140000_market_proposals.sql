-- Market proposals: a person proposes a Panta prediction market, Chumbucket
-- reviews it, and an approved proposal is published by a wallet-signed,
-- wallet-paid Panta create (quote -> build -> sign -> broadcast -> register).
-- Only the BFF (service role) reads or writes these tables; the app uses the
-- BFF's marketCreation.* procedures. Nothing here holds keys or moves money.
--
--   pending_review -> approved | rejected | withdrawn
--   approved       -> publishing | rejected | withdrawn   (or approved: cover set)
--   publishing     -> live | approved   (approved only after chain evidence of failure)
--   live, rejected, withdrawn: permanent
--
-- A proposal's content is immutable once proposed; history is never deleted.

CREATE TABLE public.market_proposals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  proposer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  idempotency_key TEXT NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 128),
  request_fingerprint TEXT NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  -- Panta create limits: question <= 512, resolutionRule <= 2048, 1..20 sources,
  -- the eight create-allowlist categories (docs.panta.market .../markets/quote.md).
  question TEXT NOT NULL CHECK (char_length(question) BETWEEN 10 AND 512),
  category TEXT NOT NULL CHECK (category IN ('sports','crypto','politics','entertainment','finance','science','world','other')),
  closes_at TIMESTAMPTZ NOT NULL,
  resolves_at TIMESTAMPTZ NOT NULL,
  rules TEXT NOT NULL CHECK (char_length(rules) BETWEEN 20 AND 2048),
  sources TEXT[] NOT NULL CHECK (cardinality(sources) BETWEEN 1 AND 20 AND array_position(sources, NULL) IS NULL),
  description TEXT CHECK (description IS NULL OR char_length(description) BETWEEN 1 AND 1000),
  status TEXT NOT NULL DEFAULT 'pending_review'
    CHECK (status IN ('pending_review','approved','rejected','withdrawn','publishing','live')),
  reviewed_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
  reviewed_at TIMESTAMPTZ,
  review_reason TEXT CHECK (review_reason IN ('unclear','unverifiable','duplicate','not_allowed','other')),
  review_note TEXT CHECK (review_note IS NULL OR char_length(review_note) BETWEEN 1 AND 280),
  cover_image_url TEXT CHECK (cover_image_url IS NULL OR (cover_image_url ~ '^https://[^[:space:]]+$' AND char_length(cover_image_url) <= 2048)),
  venue_market_id TEXT UNIQUE CHECK (venue_market_id ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  creator_wallet TEXT CHECK (creator_wallet ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  published_by UUID REFERENCES public.users(id) ON DELETE RESTRICT,
  live_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (proposer_id, idempotency_key),
  CHECK (resolves_at >= closes_at),
  CHECK ((reviewed_by IS NULL) = (reviewed_at IS NULL)),
  CHECK ((status = 'pending_review') = (reviewed_by IS NULL) OR status = 'withdrawn'),
  CHECK ((status = 'rejected') = (review_reason IS NOT NULL)),
  CHECK (review_note IS NULL OR status = 'rejected'),
  CHECK ((status IN ('publishing','live')) = (creator_wallet IS NOT NULL AND published_by IS NOT NULL)),
  CHECK ((status = 'live') = (venue_market_id IS NOT NULL AND live_at IS NOT NULL)),
  CHECK (status NOT IN ('publishing','live') OR cover_image_url IS NOT NULL)
);
CREATE INDEX market_proposals_proposer_time ON public.market_proposals(proposer_id, created_at DESC);
CREATE INDEX market_proposals_open_queue ON public.market_proposals(status, created_at)
  WHERE status IN ('pending_review','approved','publishing');

CREATE TABLE public.market_creation_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  proposal_id UUID NOT NULL REFERENCES public.market_proposals(id) ON DELETE RESTRICT,
  publisher_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  wallet_address TEXT NOT NULL CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  state TEXT NOT NULL DEFAULT 'QUOTED' CHECK (state IN ('QUOTED','SUBMITTED','REGISTERED','FAILED')),
  create_id TEXT NOT NULL UNIQUE CHECK (create_id ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$'),
  event_pda TEXT NOT NULL CHECK (event_pda ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  payment_base_units NUMERIC(38,0) NOT NULL CHECK (payment_base_units > 0),
  prepared JSONB NOT NULL,
  signed_transaction TEXT CHECK (length(signed_transaction) BETWEEN 1 AND 1644 AND signed_transaction ~ '^[A-Za-z0-9+/]+={0,2}$'),
  signature TEXT UNIQUE CHECK (signature ~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
  registered_market_id TEXT CHECK (registered_market_id = event_pda),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((signed_transaction IS NULL) = (signature IS NULL)),
  CHECK (state NOT IN ('SUBMITTED','REGISTERED') OR signature IS NOT NULL),
  CHECK ((state = 'REGISTERED') = (registered_market_id IS NOT NULL)),
  -- The reviewed binding is the exact server record the wallet approved.
  CONSTRAINT market_creation_prepared_binding CHECK ((
    jsonb_typeof(prepared) = 'object'
    AND prepared->'version' = '1'::jsonb
    AND prepared->>'policy' = 'panta-create/docs-v1'
    AND prepared->>'createId' = create_id
    AND prepared->>'eventPda' = event_pda
    AND prepared->>'wallet' = wallet_address
    AND jsonb_typeof(prepared->'paymentBaseUnits') = 'string'
    AND prepared->>'paymentBaseUnits' = payment_base_units::text
    AND prepared->>'messageHash' ~ '^[0-9a-f]{64}$'
    AND prepared->>'transaction' ~ '^[A-Za-z0-9+/]+={0,2}$'
    AND length(prepared->>'transaction') BETWEEN 4 AND 1644
  ) IS TRUE)
);
CREATE INDEX market_creation_sessions_proposal ON public.market_creation_sessions(proposal_id, created_at DESC);
-- Two replicas or a double tap can never broadcast two paid creates for one proposal.
CREATE UNIQUE INDEX market_creation_sessions_one_submitted
  ON public.market_creation_sessions(proposal_id) WHERE state IN ('SUBMITTED','REGISTERED');

ALTER TABLE public.market_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.market_creation_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.market_proposals, public.market_creation_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.market_proposals, public.market_creation_sessions TO service_role;
GRANT UPDATE (status, reviewed_by, reviewed_at, review_reason, review_note, cover_image_url, venue_market_id,
  creator_wallet, published_by, live_at, updated_at) ON public.market_proposals TO service_role;
GRANT UPDATE (state, signed_transaction, signature, registered_market_id, updated_at)
  ON public.market_creation_sessions TO service_role;

CREATE FUNCTION public.market_proposal_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Market proposal history is permanent'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending_review' OR NEW.reviewed_by IS NOT NULL OR NEW.review_reason IS NOT NULL
      OR NEW.cover_image_url IS NOT NULL OR NEW.venue_market_id IS NOT NULL OR NEW.creator_wallet IS NOT NULL
      OR NEW.published_by IS NOT NULL OR NEW.live_at IS NOT NULL THEN
      RAISE EXCEPTION 'A market proposal must start pending review';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['status','reviewed_by','reviewed_at','review_reason','review_note','cover_image_url',
      'venue_market_id','creator_wallet','published_by','live_at','updated_at'])
    IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status','reviewed_by','reviewed_at','review_reason','review_note','cover_image_url',
      'venue_market_id','creator_wallet','published_by','live_at','updated_at']) THEN
    RAISE EXCEPTION 'A proposed market cannot be edited';
  END IF;
  IF OLD.status IN ('live','rejected','withdrawn') THEN RAISE EXCEPTION 'This market proposal is final'; END IF;
  IF OLD.cover_image_url IS NOT NULL AND NEW.cover_image_url IS DISTINCT FROM OLD.cover_image_url THEN
    RAISE EXCEPTION 'A market cover cannot change once uploaded';
  END IF;
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    -- The only same-state write: recording the cover of an approved proposal.
    IF OLD.status <> 'approved' OR (to_jsonb(NEW) - ARRAY['cover_image_url','updated_at'])
      IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['cover_image_url','updated_at']) THEN
      RAISE EXCEPTION 'Invalid market proposal update';
    END IF;
    RETURN NEW;
  END IF;
  IF NOT (
    (OLD.status = 'pending_review' AND NEW.status IN ('approved','rejected','withdrawn')) OR
    (OLD.status = 'approved' AND NEW.status IN ('publishing','rejected','withdrawn')) OR
    (OLD.status = 'publishing' AND NEW.status IN ('live','approved'))
  ) THEN RAISE EXCEPTION 'Invalid market proposal transition'; END IF;
  -- Review fields change only with a review decision.
  IF NEW.status NOT IN ('approved','rejected') OR OLD.status = 'publishing' THEN
    IF NEW.reviewed_by IS DISTINCT FROM OLD.reviewed_by OR NEW.reviewed_at IS DISTINCT FROM OLD.reviewed_at
      OR NEW.review_reason IS DISTINCT FROM OLD.review_reason OR NEW.review_note IS DISTINCT FROM OLD.review_note THEN
      RAISE EXCEPTION 'Review fields change only with a review decision';
    END IF;
  END IF;
  -- Going live requires the one submitted, registered create for this exact market.
  IF NEW.status = 'live' AND NOT EXISTS (
    SELECT 1 FROM public.market_creation_sessions s
    WHERE s.proposal_id = NEW.id AND s.state = 'REGISTERED' AND s.event_pda = NEW.venue_market_id
      AND s.wallet_address = NEW.creator_wallet AND s.publisher_id = NEW.published_by
  ) THEN RAISE EXCEPTION 'A market goes live only from its registered create'; END IF;
  IF NEW.status = 'publishing' AND NOT EXISTS (
    SELECT 1 FROM public.market_creation_sessions s
    WHERE s.proposal_id = NEW.id AND s.state = 'SUBMITTED'
      AND s.wallet_address = NEW.creator_wallet AND s.publisher_id = NEW.published_by
  ) THEN RAISE EXCEPTION 'Publishing requires a submitted create'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.market_proposal_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.market_proposal_guard_v1() TO service_role;
CREATE TRIGGER market_proposals_guard BEFORE INSERT OR UPDATE OR DELETE ON public.market_proposals
  FOR EACH ROW EXECUTE FUNCTION public.market_proposal_guard_v1();
CREATE TRIGGER market_proposals_no_truncate BEFORE TRUNCATE ON public.market_proposals
  FOR EACH STATEMENT EXECUTE FUNCTION public.market_proposal_guard_v1();

CREATE FUNCTION public.market_creation_session_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE p public.market_proposals;
BEGIN
  IF TG_OP IN ('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'Market creation history is permanent'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'QUOTED' OR NEW.signature IS NOT NULL OR NEW.registered_market_id IS NOT NULL THEN
      RAISE EXCEPTION 'A market create must start as an unsigned review';
    END IF;
    SELECT * INTO p FROM public.market_proposals WHERE id = NEW.proposal_id;
    IF p.id IS NULL OR p.status <> 'approved' THEN
      RAISE EXCEPTION 'Only an approved proposal can be published';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - ARRAY['state','signed_transaction','signature','registered_market_id','updated_at'])
    IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['state','signed_transaction','signature','registered_market_id','updated_at']) THEN
    RAISE EXCEPTION 'A reviewed market create cannot change';
  END IF;
  IF OLD.signature IS NOT NULL AND (NEW.signature IS DISTINCT FROM OLD.signature OR NEW.signed_transaction IS DISTINCT FROM OLD.signed_transaction) THEN
    RAISE EXCEPTION 'A market create can approve only one transaction';
  END IF;
  IF OLD.state IN ('REGISTERED','FAILED') AND to_jsonb(NEW) - 'updated_at' IS DISTINCT FROM to_jsonb(OLD) - 'updated_at' THEN
    RAISE EXCEPTION 'This market create is final';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
    (OLD.state = 'QUOTED' AND NEW.state IN ('SUBMITTED','FAILED')) OR
    (OLD.state = 'SUBMITTED' AND NEW.state IN ('REGISTERED','FAILED'))
  ) THEN RAISE EXCEPTION 'Invalid market create transition'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.market_creation_session_guard_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.market_creation_session_guard_v1() TO service_role;
CREATE TRIGGER market_creation_sessions_guard BEFORE INSERT OR UPDATE OR DELETE ON public.market_creation_sessions
  FOR EACH ROW EXECUTE FUNCTION public.market_creation_session_guard_v1();
CREATE TRIGGER market_creation_sessions_no_truncate BEFORE TRUNCATE ON public.market_creation_sessions
  FOR EACH STATEMENT EXECUTE FUNCTION public.market_creation_session_guard_v1();

COMMENT ON TABLE public.market_proposals IS
  'Markets people propose for Panta. BFF-only (marketCreation.*). Content is immutable; review and publish state follow market_proposal_guard_v1.';
COMMENT ON TABLE public.market_creation_sessions IS
  'Each reviewed, wallet-paid Panta create for a proposal. At most one SUBMITTED/REGISTERED per proposal. Signed bytes are committed before broadcast.';
