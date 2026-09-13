-- ============================================================================
-- PACKET D — public.calls: the free, immutable, timestamped statement
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §0.1 (a call is not a trade), §0.3 (identity
--           is public.users.id), §3 (Call, and the immutable-after-lockedAt
--           list), §5 (additive only, default-deny, no USING (true), pinned
--           search_path, never CREATE OR REPLACE an existing function)
-- ============================================================================
--
-- WHAT THIS TABLE IS, AND WHAT IT DELIBERATELY IS NOT
--
--   §0.1: "A call is a free, immutable, timestamped statement by a person. A
--   funded venue position is an optional, separately-authorised artefact that
--   REFERENCES a call. Neither implies the other."
--
-- So this table has NO money column. Not a stake, not an amount, not a base
-- unit, not a transaction signature, not an escrow, not a position address.
-- That absence is the enforcement: a UI cannot render an amount it was never
-- handed, and no writer can turn a call into a trade by filling in a field,
-- because there is no field. A funded artefact is a public.venue_orders /
-- public.venue_positions row (Packet B) that points AT a call; it is never
-- this row. The two are structurally distinct, and this file is where that is
-- true.
--
-- §2 already ruled out reusing prediction_positions: its match_id and
-- open_tx_signature are both NOT NULL, so a free call with no fixture and no
-- transaction is not even representable there.
--
-- THE THREE THINGS THIS FILE ENFORCES THAT A COMMENT COULD NOT
--
--   1. IMMUTABILITY (§3). An RLS policy can only see the row being written —
--      it has no OLD. So "marketId, side, entryProbability, snapshotId,
--      createdAt and the free/funded provenance may not change after lockedAt"
--      cannot be expressed as a policy at all. It is a BEFORE UPDATE trigger,
--      which also binds service_role (RLS does not), and service_role is what
--      SocialStore uses for every call (§2).
--   2. NO HARD DELETE. "Deleting a public call hides it from distribution; it
--      does not rewrite CallResult or accuracy history" (§3). A DELETE would
--      cascade-or-restrict its call_results row and erase the fact that the
--      person went on record. So DELETE is refused outright by the same
--      trigger, for every role, and "delete" means setting hidden_at.
--   3. VISIBILITY. A `public` row is readable by anyone; a `followers` row
--      only by a follower or the author (§5). Three permissive policies, each
--      a real predicate. Never USING (true) (§5).
--
-- DEPENDENCY: public.current_app_user_id() from Packet A. §5 requires every
-- new policy to scope on it. Fail loudly rather than create a policy that
-- silently references nothing.
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_calls requires public.current_app_user_id() (Packet A: *_auth_identity_* migrations). Apply the auth-identity migrations first; contracts §5 requires every new policy to scope on it.';
  END IF;
  IF to_regclass('public.venue_markets') IS NULL THEN
    RAISE EXCEPTION
      'social_calls_calls requires public.venue_markets (Packet B: *_venue_market_* migrations). A call references a normalized venue market; contracts §0.2 makes the venue the only source of a result.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- calls
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- §0.3: identity IS public.users.id. NEVER a wallet. There is deliberately
  -- no wallet column on this table: a wallet is a linked credential and
  -- nothing here authorises on one.
  -- ON DELETE RESTRICT: a person's account cannot be removed out from under
  -- the record of what they said.
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,

  -- ON DELETE RESTRICT: the market a call was made about outlives convenience.
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE RESTRICT,

  side TEXT NOT NULL,

  -- [0,1], self-reported, optional (§3). NUMERIC, never a float.
  confidence NUMERIC(9, 8),

  -- <= 280 chars (§3).
  thesis TEXT,

  -- The venue price the call was stamped with, and the snapshot row it was
  -- read from. Both immutable: this is the evidence that the person committed
  -- before the answer was known.
  entry_probability NUMERIC(9, 8),
  snapshot_id UUID REFERENCES public.market_snapshots(id) ON DELETE RESTRICT,

  visibility TEXT NOT NULL DEFAULT 'public',

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- "Immutable from this instant" (§3).
  locked_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Set when this call came from a Back/Fade (§3). A challenge sets nothing
  -- here because a challenge creates no call at all — see call_responses.
  parent_call_id UUID REFERENCES public.calls(id) ON DELETE RESTRICT,

  -- FundingState (§3). 'NONE' is the free call — the default, and the only
  -- state the MVP ships. It is IMMUTABLE: §3 freezes "the free/funded
  -- provenance", and a row that could walk NONE -> FILLED would be exactly
  -- that provenance changing. A funded artefact is a separate venue_positions
  -- row that references this call (§0.1), never this column moving.
  funding_state TEXT NOT NULL DEFAULT 'NONE',

  -- ── soft delete: hide from distribution, rewrite nothing (§3) ──
  hidden_at TIMESTAMPTZ,
  hidden_reason TEXT,

  CONSTRAINT calls_side_check CHECK (side IN ('YES', 'NO')),
  CONSTRAINT calls_visibility_check CHECK (visibility IN ('public', 'followers')),
  CONSTRAINT calls_funding_state_check CHECK (
    funding_state IN ('NONE', 'QUOTED', 'SUBMITTED', 'FILLED', 'PARTIAL', 'FAILED', 'CLOSED', 'CLAIMABLE', 'CLAIMED')
  ),
  CONSTRAINT calls_confidence_range CHECK (
    confidence IS NULL OR (confidence >= 0 AND confidence <= 1)
  ),
  CONSTRAINT calls_entry_probability_range CHECK (
    entry_probability IS NULL OR (entry_probability >= 0 AND entry_probability <= 1)
  ),
  CONSTRAINT calls_thesis_length CHECK (thesis IS NULL OR length(thesis) <= 280),
  CONSTRAINT calls_hidden_reason_length CHECK (hidden_reason IS NULL OR length(hidden_reason) <= 200),
  -- A call cannot be its own parent, and cannot be locked before it existed.
  CONSTRAINT calls_parent_not_self CHECK (parent_call_id IS DISTINCT FROM id),
  CONSTRAINT calls_locked_after_created CHECK (locked_at >= created_at),
  -- hidden_reason only means something on a hidden row.
  CONSTRAINT calls_hidden_reason_requires_hidden CHECK (
    hidden_reason IS NULL OR hidden_at IS NOT NULL
  )
);

-- The feed: newest first, public rows only, hidden rows never.
CREATE INDEX IF NOT EXISTS idx_calls_feed
  ON public.calls (locked_at DESC)
  WHERE hidden_at IS NULL AND visibility = 'public';

-- A person's page, and the accuracy history behind it.
CREATE INDEX IF NOT EXISTS idx_calls_author
  ON public.calls (user_id, locked_at DESC);

-- "Has the viewer locked a call on this market?" — the crowdSplit gate, and
-- the crowd split itself.
CREATE INDEX IF NOT EXISTS idx_calls_market
  ON public.calls (market_id, side)
  WHERE hidden_at IS NULL;

-- Back/Fade lineage.
CREATE INDEX IF NOT EXISTS idx_calls_parent
  ON public.calls (parent_call_id)
  WHERE parent_call_id IS NOT NULL;

-- One live call per person per market. A second opinion is an edit, and a call
-- is not editable (§0.1) — so it is refused rather than silently shadowing the
-- first. Hidden rows are outside the index: hiding a call frees the slot
-- without deleting the record.
CREATE UNIQUE INDEX IF NOT EXISTS uq_calls_one_live_per_user_market
  ON public.calls (user_id, market_id)
  WHERE hidden_at IS NULL;

-- §5 mandatory template.
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.calls FROM anon, authenticated;
GRANT ALL ON public.calls TO service_role;

GRANT SELECT ON public.calls TO anon, authenticated;

-- A client may insert its OWN call, and only the columns a person actually
-- chooses. entry_probability, locked_at, created_at, funding_state and
-- hidden_at are NOT grantable to a client: the server stamps them. A
-- client-inserted row therefore cannot forge the price it claims to have seen
-- or back-date when it went on record.
GRANT INSERT (user_id, market_id, side, confidence, thesis, snapshot_id, visibility, parent_call_id)
  ON public.calls TO authenticated;

-- The ONLY client-writable columns after the fact. This is the "delete"
-- surface, and it is the whole of it (§3: deleting hides, it does not rewrite).
GRANT UPDATE (hidden_at, hidden_reason) ON public.calls TO authenticated;

-- No DELETE grant, ever.

-- ── SELECT: three real predicates, OR'd by PostgreSQL. Never USING (true). ──

-- 1. A public row is readable by anyone — including anon, who has no session.
DROP POLICY IF EXISTS calls_public_select ON public.calls;
CREATE POLICY calls_public_select ON public.calls
  FOR SELECT
  TO anon, authenticated
  USING (hidden_at IS NULL AND visibility = 'public');

-- 2. A followers row is readable ONLY by someone who follows the author.
--    public.follows is the existing asymmetric graph; follower_user_id /
--    followee_user_id are its canonical-id columns. Scoped on
--    current_app_user_id(), so a wallet string authorises nothing (§0.3).
DROP POLICY IF EXISTS calls_followers_select ON public.calls;
CREATE POLICY calls_followers_select ON public.calls
  FOR SELECT
  TO authenticated
  USING (
    hidden_at IS NULL
    AND visibility = 'followers'
    AND EXISTS (
      SELECT 1
      FROM public.follows f
      WHERE f.followee_user_id = calls.user_id
        AND f.follower_user_id = public.current_app_user_id()
    )
  );

-- 3. The author always sees their own calls, including the ones they hid —
--    otherwise "unhide" would be unreachable and a hidden call would look
--    deleted to the only person entitled to know it is not.
DROP POLICY IF EXISTS calls_author_select ON public.calls;
CREATE POLICY calls_author_select ON public.calls
  FOR SELECT
  TO authenticated
  USING (user_id = public.current_app_user_id());

-- ── INSERT: only as yourself, only free, only visible. ──
DROP POLICY IF EXISTS calls_author_insert ON public.calls;
CREATE POLICY calls_author_insert ON public.calls
  FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = public.current_app_user_id()
    AND funding_state = 'NONE'
    AND hidden_at IS NULL
  );

-- ── UPDATE: the author, on their own row. The column grant above already
--    limits WHICH columns; the trigger below rejects every other change for
--    every writer, service_role included. A policy cannot see OLD, so a policy
--    alone could never express "immutable after lockedAt" (§5).
DROP POLICY IF EXISTS calls_author_hide ON public.calls;
CREATE POLICY calls_author_hide ON public.calls
  FOR UPDATE
  TO authenticated
  USING (user_id = public.current_app_user_id())
  WITH CHECK (user_id = public.current_app_user_id());

-- No DELETE policy: a call is never deleted, by anyone (see the trigger).

-- ---------------------------------------------------------------------------
-- THE IMMUTABILITY TRIGGER
--
-- §3, verbatim: "Immutable after lockedAt: marketId, side, entryProbability,
-- snapshotId, createdAt, and the free/funded provenance."
--
-- That list is the FLOOR, not the ceiling. §0.1 calls a call "a free,
-- immutable, timestamped statement by a person", so this trigger additionally
-- freezes user_id (a statement never changes author), thesis and confidence
-- (the statement itself), locked_at (the timestamp), parent_call_id (the
-- lineage) and visibility (the audience the statement was made to). The ONLY
-- columns any writer may change after INSERT are hidden_at and hidden_reason.
--
-- New, separately-named function; never CREATE OR REPLACE on an existing one
-- (§5 — record_prediction_call was redefined three times and silently lost
-- both a settled-position guard and its search_path pin).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.calls_guard_immutability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- §3: "Deleting a public call hides it from distribution; it does NOT
    -- rewrite CallResult or accuracy history." A row removal would do exactly
    -- what that sentence forbids, so there is no path to one — not for a
    -- client (no DELETE grant, no DELETE policy) and not for service_role
    -- (this, which RLS would not have stopped).
    RAISE EXCEPTION
      'calls: a call is never deleted. Set hidden_at to withdraw it from distribution — call_results and accuracy history must survive (contracts §3).'
      USING ERRCODE = 'raise_exception';
  END IF;

  -- ── the §3 list ──
  IF NEW.market_id IS DISTINCT FROM OLD.market_id THEN
    RAISE EXCEPTION 'calls: market_id is immutable after lockedAt (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.side IS DISTINCT FROM OLD.side THEN
    RAISE EXCEPTION 'calls: side is immutable after lockedAt (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.entry_probability IS DISTINCT FROM OLD.entry_probability THEN
    RAISE EXCEPTION 'calls: entry_probability is immutable after lockedAt (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.snapshot_id IS DISTINCT FROM OLD.snapshot_id THEN
    RAISE EXCEPTION 'calls: snapshot_id is immutable after lockedAt (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'calls: created_at is immutable after lockedAt (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.funding_state IS DISTINCT FROM OLD.funding_state THEN
    RAISE EXCEPTION
      'calls: funding_state is the free/funded provenance and is immutable (call % is %). A funded artefact is a separate venue_positions row that REFERENCES this call (contracts §0.1/§3).',
      OLD.id, OLD.funding_state
      USING ERRCODE = 'raise_exception';
  END IF;

  -- ── §0.1: "an immutable, timestamped statement by a person" ──
  IF NEW.id IS DISTINCT FROM OLD.id THEN
    RAISE EXCEPTION 'calls: id is immutable (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'calls: a call never changes author (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.locked_at IS DISTINCT FROM OLD.locked_at THEN
    RAISE EXCEPTION 'calls: locked_at is the timestamp the statement was made and is immutable (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.thesis IS DISTINCT FROM OLD.thesis THEN
    RAISE EXCEPTION 'calls: thesis is part of the immutable statement (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.confidence IS DISTINCT FROM OLD.confidence THEN
    RAISE EXCEPTION 'calls: confidence is part of the immutable statement (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.parent_call_id IS DISTINCT FROM OLD.parent_call_id THEN
    RAISE EXCEPTION 'calls: parent_call_id records where this call came from and is immutable (call %).', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;
  IF NEW.visibility IS DISTINCT FROM OLD.visibility THEN
    RAISE EXCEPTION
      'calls: visibility is the audience the statement was made to and is fixed at lock (call %). To withdraw a call, set hidden_at.', OLD.id
      USING ERRCODE = 'raise_exception';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.calls_guard_immutability() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.calls_guard_immutability() TO service_role;

DROP TRIGGER IF EXISTS trg_calls_guard_immutability ON public.calls;
CREATE TRIGGER trg_calls_guard_immutability
  BEFORE UPDATE OR DELETE ON public.calls
  FOR EACH ROW
  EXECUTE FUNCTION public.calls_guard_immutability();

-- ---------------------------------------------------------------------------
-- Insert-time sanity the CHECKs cannot express: a Back/Fade's parent must be a
-- call on the SAME market (otherwise the lineage is meaningless), and a call
-- may not be born hidden.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.calls_guard_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
DECLARE
  v_parent_market UUID;
BEGIN
  IF NEW.hidden_at IS NOT NULL THEN
    RAISE EXCEPTION
      'calls: a call may not be inserted already hidden. Lock it, then hide it — the record of it having been made is the point (contracts §0.1).'
      USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.parent_call_id IS NOT NULL THEN
    SELECT c.market_id INTO v_parent_market FROM public.calls c WHERE c.id = NEW.parent_call_id;
    IF v_parent_market IS NULL THEN
      RAISE EXCEPTION 'calls: parent_call_id % does not exist.', NEW.parent_call_id
        USING ERRCODE = 'raise_exception';
    END IF;
    IF v_parent_market <> NEW.market_id THEN
      RAISE EXCEPTION
        'calls: a Back/Fade must be on the SAME market as the call it came from (parent % is on market %, this call is on %).',
        NEW.parent_call_id, v_parent_market, NEW.market_id
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.calls_guard_insert() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.calls_guard_insert() TO service_role;

DROP TRIGGER IF EXISTS trg_calls_guard_insert ON public.calls;
CREATE TRIGGER trg_calls_guard_insert
  BEFORE INSERT ON public.calls
  FOR EACH ROW
  EXECUTE FUNCTION public.calls_guard_insert();

COMMENT ON TABLE public.calls IS
  'Free, immutable, timestamped statements (contracts §0.1/§3). Has NO money column by design — a funded artefact is a venue_positions row that REFERENCES a call, never this row. Public rows readable by anyone; followers rows only by a follower or the author; insert only as current_app_user_id(). Immutable after lockedAt, enforced by a BEFORE UPDATE trigger (an RLS policy cannot see OLD). Never deleted: hidden_at withdraws it from distribution while call_results and accuracy history survive.';
COMMENT ON COLUMN public.calls.user_id IS
  'The canonical public.users.id (§0.3). NEVER a wallet — there is no wallet column on this table and nothing here authorises on one.';
COMMENT ON COLUMN public.calls.funding_state IS
  'FundingState (§3); ''NONE'' is the free call and the only state the MVP ships. IMMUTABLE: §3 freezes the free/funded provenance, so this column may never move.';
COMMENT ON COLUMN public.calls.hidden_at IS
  'Soft delete. Setting it withdraws the call from every distribution surface; it rewrites no CallResult and no accuracy history (§3). There is no hard-delete path for any role.';
COMMENT ON COLUMN public.calls.visibility IS
  '''public'' = readable by anyone including anon; ''followers'' = readable only by a follower or the author. Fixed at lock.';
