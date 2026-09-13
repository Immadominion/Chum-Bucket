-- ============================================================================
-- PACKET F — public.call_category_records: a person's record, per category,
--            free and funded kept strictly apart
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §0.1 (a call is not a trade), §3 (CallOutcome;
--           "VOID = cancelled/abandoned; never a win or a loss"; deleting a
--           call does not rewrite accuracy history), §5 (additive only,
--           default-deny, no USING (true), pinned search_path, REVOKE/GRANT on
--           every function, never CREATE OR REPLACE an existing function).
-- ============================================================================
--
-- ── THE DECISION: A NEW TABLE, NOT COLUMNS ON public.user_stats. AND WHY. ───
--
-- public.user_stats already has calls_made, calls_won, calls_lost,
-- calls_voided, current_streak and best_streak, keyed on public.users.id. It
-- looks like the answer. It is not, for four independent reasons:
--
--   1. RLS. `user_stats_public_select` is `FOR SELECT USING (true)`
--      (20260715134226:694-696). PostgreSQL ORs permissive policies together,
--      so any tighter policy added beside it is a no-op (contracts §2). A
--      column added to user_stats is a world-readable column, permanently, and
--      nothing this packet writes can change that without removing the legacy
--      policy — a production change requiring founder approval (§8).
--
--   2. IT MIXES MONEY WITH ACCURACY IN ONE ROW. user_stats carries
--      `stake_base_units` and `pnl_base_units` in the SAME ROW as calls_won and
--      calls_lost. The product rule this packet exists to hold is that free-call
--      accuracy and funded P&L stay strictly separate; a row that has both is
--      the exact shape that makes "he's up 4 SOL so he must be good" renderable
--      by accident. THIS TABLE HAS NO MONEY COLUMN AT ALL — no stake, no P&L, no
--      payout, no base units, in any row, for any funding class. A UI cannot
--      render an amount it was never handed, and no future writer can blend the
--      two by filling in a field, because there is no field.
--
--   3. IT HAS NO CATEGORY DIMENSION AND NO FREE/FUNDED DIMENSION. Its primary
--      key is (user_id). Adding either dimension means changing the primary key
--      of a live table that four existing functions write to by
--      `INSERT ... ON CONFLICT (user_id) DO UPDATE` — a rewrite, not an
--      addition. §5 is additive-only.
--
--   4. ITS COUNTERS ARE INCREMENTED BY LEGACY TRIGGERS FROM ARENA SETTLEMENT
--      (20260715220000:161-186), not derived from public.call_results. Two
--      writers with different definitions of "won" on one row is how a record
--      stops being a record.
--
-- Nothing in user_stats is touched by this file. It keeps working exactly as it
-- does today; the pivot simply does not build on it.
--
-- ── WHAT A RECORD IS HERE ───────────────────────────────────────────────────
--
-- One row per (person, category, funding class):
--
--     correct_count   the venue's resolution matched the side they called
--     incorrect_count it did not
--     void_count      the venue voided the market — NEVER a win, NEVER a loss
--     resolved_count  = correct + incorrect + void, by CHECK
--     decided_count   = correct + incorrect, GENERATED — the accuracy base
--     pending_count   the venue has published nothing yet; counts towards
--                     NOTHING, ever
--
-- ── FOUR THINGS THAT ARE STRUCTURALLY IMPOSSIBLE ────────────────────────────
--
--   1. A RECORD THAT OMITS MISSES. `resolved_count = correct_count +
--      incorrect_count + void_count` is a CHECK, so a row claiming ten resolved
--      and ten correct is not representable. And the counters are MONOTONE: the
--      guard trigger refuses any write that lowers correct, incorrect, void or
--      resolved, for every writer including service_role. A loss, once counted,
--      cannot be un-counted — not by a rebuild, not by an admin, not by a bug.
--      §3 already says hiding a call "does not rewrite CallResult or accuracy
--      history"; this is that sentence made unbreakable.
--
--   2. VOID COUNTING AS A WIN OR A LOSS. void_count is its own column, and
--      `decided_count` — the ONLY base an accuracy may be computed over — is
--      GENERATED as correct + incorrect. VOID is present in the record and
--      absent from the ratio, exactly as §3 requires.
--
--   3. PENDING COUNTING AS ANYTHING. pending_count is excluded from
--      resolved_count by the CHECK and from decided_count by the generation
--      expression. It appears so a person can see what is outstanding and
--      contributes to nothing.
--
--   4. FREE ACCURACY BLENDED WITH FUNDED. funding_class is part of the PRIMARY
--      KEY, so the two never share a row and a query has to name which one it
--      wants. 'free' is calls whose funding_state is 'NONE' (§3: the free call,
--      and the only state the MVP ships); 'funded' is everything else. There is
--      still no money column in the funded rows — P&L belongs to Packet B's
--      public.venue_positions, which is where money lives.
--
-- ── THE ACCURACY THRESHOLD, AND WHY IT IS IN THE SCHEMA ─────────────────────
--
-- `accuracy_reportable` is GENERATED ALWAYS AS (decided >= 10). Below ten
-- DECIDED calls the product shows raw counts and no percentage. Two independent
-- reasons, either sufficient:
--
--   · RESOLUTION. With n decided calls one call moves the headline by 100/n
--     points. At n = 10 that is already 10 points. Below 10, a single call moves
--     a displayed percentage by more than ten points, so the number is
--     describing the last call rather than the record.
--   · DISCRIMINATION. Against a null of a coin flip, a perfect run of 10 has
--     probability 2^-10 ≈ 0.1%; a perfect run of 5 has 3.1% and of 3 has 12.5%.
--     Ten is the smallest round n at which a flawless record is not plausibly
--     luck at the 1% level. The 95% Wilson interval for 10/10 is roughly
--     [72%, 100%]; for 3/3 it is roughly [44%, 100%], which does not even
--     exclude a coin.
--
-- The threshold is on DECIDED, not on RESOLVED. A person with nine VOIDs and one
-- CORRECT has ten resolved calls and one piece of information; thresholding on
-- resolved would unlock "100% accurate" from a single call.
--
-- It is a literal here and a literal in src/notifications/record.ts, and
-- tests/socialNotificationsRecord.test.ts reads this file and asserts the two
-- agree — so the schema and the BFF cannot drift into disagreeing about when a
-- percentage is honest.
--
-- ── WHY THIS TABLE IS NOT PUBLIC-READABLE ───────────────────────────────────
--
-- A record aggregates EVERY call the person made, including `followers`-only
-- ones — it has to, or setting visibility to `followers` on the losers would
-- launder the record. But `calls_followers_select` deliberately withholds those
-- rows from a stranger, and an aggregate over them, polled before and after,
-- gives a stranger exactly what that policy withholds. So the RLS read here is
-- OWNER-SCOPED, anon holds no grant at all, and another person's record is
-- served by the BFF (src/notifications/**), which is the layer that decides what
-- aggregate is publishable. Default-deny, one real predicate, no USING (true).
--
-- DEPENDENCY: public.current_app_user_id() (Packet A), public.calls and
-- public.call_results (Packet D), public.venue_markets (Packet B, for category).
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_category_record requires public.current_app_user_id() (Packet A: *_auth_identity_* migrations). Contracts §5 requires every new policy to scope on it.';
  END IF;
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_category_record requires public.calls (Packet D: 20260913140000_social_calls_calls.sql).';
  END IF;
  IF to_regclass('public.call_results') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_category_record requires public.call_results (Packet D: 20260913141000_social_calls_results.sql). A record is derived from venue-derived results and from nothing else (§0.2).';
  END IF;
  IF to_regclass('public.venue_markets') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_category_record requires public.venue_markets (Packet B: *_venue_market_* migrations) — the category of a call is the category of its market.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- call_category_records
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.call_category_records (
  -- §0.3: canonical public.users.id. No wallet column, here or anywhere in
  -- this packet.
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- public.venue_markets.category ('crypto' for MVP).
  category TEXT NOT NULL,

  -- 'free'   = calls whose funding_state is 'NONE' (§3: the free call, and the
  --            only state the MVP ships)
  -- 'funded' = everything else
  -- Part of the PRIMARY KEY, so free accuracy and funded accuracy can never
  -- share a row and a query must name which it wants.
  funding_class TEXT NOT NULL,

  correct_count   INTEGER NOT NULL DEFAULT 0,
  incorrect_count INTEGER NOT NULL DEFAULT 0,
  -- Never a win, never a loss (§3). Present in the record; absent from the base.
  void_count      INTEGER NOT NULL DEFAULT 0,
  resolved_count  INTEGER NOT NULL DEFAULT 0,
  -- The venue has published nothing. Counts towards nothing.
  pending_count   INTEGER NOT NULL DEFAULT 0,

  -- ★ The ONLY base an accuracy may be computed over. VOID is excluded by the
  --   generation expression, so "accuracy over resolved calls" is not even
  --   expressible from this row without deliberately re-adding void_count.
  decided_count INTEGER GENERATED ALWAYS AS (correct_count + incorrect_count) STORED,

  -- ★ The honesty gate. See the header for the two reasons the number is 10.
  --   A literal, because a generation expression must be immutable and because
  --   a literal is what a test can read out of this file and compare with
  --   src/notifications/record.ts.
  accuracy_reportable BOOLEAN GENERATED ALWAYS AS ((correct_count + incorrect_count) >= 10) STORED,

  last_resolved_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  PRIMARY KEY (user_id, category, funding_class),

  CONSTRAINT call_category_records_funding_class_check CHECK (
    funding_class IN ('free', 'funded')
  ),
  CONSTRAINT call_category_records_category_not_blank CHECK (
    length(category) BETWEEN 1 AND 64
  ),
  CONSTRAINT call_category_records_counts_nonnegative CHECK (
    correct_count >= 0
    AND incorrect_count >= 0
    AND void_count >= 0
    AND resolved_count >= 0
    AND pending_count >= 0
  ),

  -- ★ A RECORD MUST INCLUDE MISSES. A row claiming ten resolved and ten
  --   correct is not representable: the arithmetic has to close.
  CONSTRAINT call_category_records_resolved_is_the_whole_story CHECK (
    resolved_count = correct_count + incorrect_count + void_count
  ),

  -- A record with nothing resolved has no last_resolved_at, and one with
  -- something resolved has one.
  CONSTRAINT call_category_records_last_resolved_iff_resolved CHECK (
    (resolved_count > 0) = (last_resolved_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_call_category_records_user
  ON public.call_category_records (user_id, funding_class, category);

-- "Who has a reportable record in this category?" — the only leaderboard shape
-- this packet will support, and it is over DECIDED calls, not over money.
CREATE INDEX IF NOT EXISTS idx_call_category_records_reportable
  ON public.call_category_records (category, funding_class, decided_count DESC)
  WHERE accuracy_reportable;

-- §5 mandatory template (pattern established at 20260719160000:32-34).
ALTER TABLE public.call_category_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.call_category_records FROM anon, authenticated;
GRANT ALL ON public.call_category_records TO service_role;

-- anon gets NOTHING. A signed-in person may read their OWN record and nothing
-- else; see the header for why an aggregate over followers-only calls is not
-- publishable at this layer.
GRANT SELECT ON public.call_category_records TO authenticated;

DROP POLICY IF EXISTS call_category_records_owner_select ON public.call_category_records;
CREATE POLICY call_category_records_owner_select ON public.call_category_records
  FOR SELECT
  TO authenticated
  USING (user_id = public.current_app_user_id());

-- No INSERT, UPDATE or DELETE policy and no such grant for any client role.
-- A record is DERIVED from public.call_results, which is itself service-write
-- only (§5). Nobody states their own record.

-- ---------------------------------------------------------------------------
-- THE MONOTONICITY GUARD
--
-- The CHECK above stops a record being MISSTATED. This stops one being
-- REWRITTEN. correct, incorrect, void and resolved may only ever go up, and a
-- record row is never deleted — so a loss, once counted, cannot be un-counted
-- by a rebuild, by an admin, or by our own bug. pending_count may fall, because
-- a pending call becoming resolved is exactly what should make it fall.
--
-- This binds service_role, which RLS does not, and service_role is what the BFF
-- writes with (§2).
--
-- New, separately-named function; never CREATE OR REPLACE (§5).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.call_category_records_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION
      'call_category_records: a record is never deleted (% / % / %). §3 — hiding a call does not rewrite accuracy history, and neither does anything else.',
      OLD.user_id, OLD.category, OLD.funding_class
      USING ERRCODE = 'raise_exception';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.category IS DISTINCT FROM OLD.category
       OR NEW.funding_class IS DISTINCT FROM OLD.funding_class THEN
      RAISE EXCEPTION 'call_category_records: the key of a record row is immutable.'
        USING ERRCODE = 'raise_exception';
    END IF;

    IF NEW.incorrect_count < OLD.incorrect_count THEN
      RAISE EXCEPTION
        'call_category_records: misses never go down (% / % / %: % -> %). A record that can shed its incorrect calls is not a record (contracts §3).',
        OLD.user_id, OLD.category, OLD.funding_class, OLD.incorrect_count, NEW.incorrect_count
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.correct_count < OLD.correct_count THEN
      RAISE EXCEPTION
        'call_category_records: correct_count never goes down (% / % / %: % -> %).',
        OLD.user_id, OLD.category, OLD.funding_class, OLD.correct_count, NEW.correct_count
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.void_count < OLD.void_count THEN
      RAISE EXCEPTION
        'call_category_records: void_count never goes down (% / % / %: % -> %).',
        OLD.user_id, OLD.category, OLD.funding_class, OLD.void_count, NEW.void_count
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.resolved_count < OLD.resolved_count THEN
      RAISE EXCEPTION
        'call_category_records: resolved_count never goes down (% / % / %: % -> %).',
        OLD.user_id, OLD.category, OLD.funding_class, OLD.resolved_count, NEW.resolved_count
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.last_resolved_at IS NOT NULL AND OLD.last_resolved_at IS NOT NULL
       AND NEW.last_resolved_at < OLD.last_resolved_at THEN
      RAISE EXCEPTION
        'call_category_records: last_resolved_at only moves forward (% / % / %).',
        OLD.user_id, OLD.category, OLD.funding_class
        USING ERRCODE = 'raise_exception';
    END IF;

    NEW.updated_at := NOW();
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.call_category_records_guard() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.call_category_records_guard() TO service_role;

DROP TRIGGER IF EXISTS trg_call_category_records_guard ON public.call_category_records;
CREATE TRIGGER trg_call_category_records_guard
  BEFORE UPDATE OR DELETE ON public.call_category_records
  FOR EACH ROW
  EXECUTE FUNCTION public.call_category_records_guard();

-- ---------------------------------------------------------------------------
-- THE REBUILD
--
-- One scan of a person's calls joined to their venue-derived results and to
-- their markets' categories, producing every count in the same pass. There is
-- no path here that computes correct without computing incorrect: they come out
-- of one GROUP BY, and the CHECK would reject the row if they did not close.
--
-- Idempotent: running it twice writes the same numbers. Safe to run on a loop.
-- Service-role only (§5) — a person does not state their own record.
--
-- New, separately-named function; never CREATE OR REPLACE (§5).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.call_category_record_rebuild(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
DECLARE
  v_rows INTEGER;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'call_category_record_rebuild: a user id is required.'
      USING ERRCODE = 'raise_exception';
  END IF;

  INSERT INTO public.call_category_records AS r (
    user_id, category, funding_class,
    correct_count, incorrect_count, void_count, resolved_count, pending_count,
    last_resolved_at, updated_at
  )
  SELECT
    c.user_id,
    m.category,
    CASE WHEN c.funding_state = 'NONE' THEN 'free' ELSE 'funded' END AS funding_class,
    -- One pass, four counters. COALESCE(res.outcome,'PENDING'): a call with no
    -- derived result row at all is PENDING, which is the only thing the absence
    -- of venue evidence ever means (§0.2).
    count(*) FILTER (WHERE COALESCE(res.outcome, 'PENDING') = 'CORRECT')::int,
    count(*) FILTER (WHERE COALESCE(res.outcome, 'PENDING') = 'INCORRECT')::int,
    count(*) FILTER (WHERE COALESCE(res.outcome, 'PENDING') = 'VOID')::int,
    count(*) FILTER (WHERE COALESCE(res.outcome, 'PENDING') <> 'PENDING')::int,
    count(*) FILTER (WHERE COALESCE(res.outcome, 'PENDING') = 'PENDING')::int,
    max(res.resolved_at) FILTER (WHERE COALESCE(res.outcome, 'PENDING') <> 'PENDING'),
    NOW()
  FROM public.calls c
  JOIN public.venue_markets m ON m.id = c.market_id
  LEFT JOIN public.call_results res ON res.call_id = c.id
  -- NOTE what is NOT filtered here: hidden_at and visibility. A record counts
  -- every call the person made. §3 — "Deleting a public call hides it from
  -- distribution; it does not rewrite CallResult or accuracy history" — and a
  -- record that could be laundered by withdrawing the losses would be worth
  -- nothing.
  WHERE c.user_id = p_user_id
  GROUP BY c.user_id, m.category, CASE WHEN c.funding_state = 'NONE' THEN 'free' ELSE 'funded' END
  ON CONFLICT (user_id, category, funding_class) DO UPDATE SET
    correct_count    = EXCLUDED.correct_count,
    incorrect_count  = EXCLUDED.incorrect_count,
    void_count       = EXCLUDED.void_count,
    resolved_count   = EXCLUDED.resolved_count,
    pending_count    = EXCLUDED.pending_count,
    last_resolved_at = EXCLUDED.last_resolved_at,
    updated_at       = NOW();

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.call_category_record_rebuild(UUID) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.call_category_record_rebuild(UUID) TO service_role;

COMMENT ON TABLE public.call_category_records IS
  'A person''s record per (category, funding class), derived from public.call_results. A NEW table rather than columns on public.user_stats, because that table''s SELECT policy is USING (true) (so a tighter policy beside it is a no-op — contracts §2), because it carries stake_base_units and pnl_base_units in the SAME ROW as calls_won/calls_lost, and because its primary key is (user_id) with no category and no free/funded dimension. THIS TABLE HAS NO MONEY COLUMN, in any row: free-call accuracy and funded P&L are never blended, and P&L lives with public.venue_positions. Counters are MONOTONE and the row is never deleted, so a miss can never be un-counted. Owner-scoped read; service-write only; anon holds no grant at all.';
COMMENT ON COLUMN public.call_category_records.void_count IS
  'VOID results (§3: never a win and never a loss). Present in the record, absent from decided_count, so it can never reach an accuracy ratio.';
COMMENT ON COLUMN public.call_category_records.decided_count IS
  'GENERATED as correct + incorrect. The ONLY base an accuracy may be computed over; VOID and PENDING are excluded by construction.';
COMMENT ON COLUMN public.call_category_records.accuracy_reportable IS
  'GENERATED as decided >= 10. Below ten DECIDED calls the product shows raw counts and no percentage: one call would move the headline by more than ten points, and a perfect run shorter than ten is not distinguishable from a coin flip at the 1% level. The same literal appears in src/notifications/record.ts and a test asserts the two agree.';
COMMENT ON COLUMN public.call_category_records.pending_count IS
  'Calls the venue has published no resolution for. Excluded from resolved_count by CHECK and from decided_count by the generation expression: PENDING counts towards nothing, ever.';
COMMENT ON FUNCTION public.call_category_record_rebuild(UUID) IS
  'Recompute every record row for one person in a single GROUP BY over their calls, their venue-derived results and their markets categories. Counts hidden and followers-only calls deliberately — a record that could be laundered by withdrawing the losses is not a record (§3). Idempotent; service_role only.';
