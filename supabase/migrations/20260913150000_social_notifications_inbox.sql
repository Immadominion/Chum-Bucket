-- ============================================================================
-- PACKET F — public.social_notifications: the four relational notifications
-- Created: 2026-09-13
-- Contract: pivot-contracts-v1.md §0.3 (identity is public.users.id), §3
--           (CallResponse kinds, CallOutcome), §5 (additive only, default-deny,
--           no USING (true), pinned search_path, REVOKE/GRANT on every
--           function, never CREATE OR REPLACE an existing function), §8
--           findings 3 and 6.
-- ============================================================================
--
-- ── THE DECISION: A NEW DEFAULT-DENY TABLE, NOT AN EXTENSION OF
--    public.notification_outbox. AND WHY. ──────────────────────────────────
--
-- The legacy outbox is right there, it already has recipient_user_id, type,
-- title, body, data, read_at and a drain worker. Extending it would have been
-- fewer lines. It is nonetheless the wrong table, for four independent reasons,
-- each of which is on its own sufficient:
--
--   1. RLS. `notification_outbox_public_select` is `FOR SELECT USING (true)`
--      (20260716010000:139-141). PostgreSQL ORs permissive policies together,
--      so a tight `recipient_user_id = public.current_app_user_id()` policy
--      added BESIDE it is a no-op — the world-readable policy still matches
--      every row. Contracts §2 states exactly this, and §8 finding 3 records
--      the consequence: "Any anon caller reads any wallet's inbox by passing
--      that wallet string." The only way to add a tight policy is to remove the
--      loose one, which is a production change requiring founder approval and
--      is tracked separately from packet work (§8, closing paragraph). So the
--      pivot's inbox lands on a NEW table whose first policy is the tight one.
--
--   2. ADDRESSING. The outbox addresses a person by
--      `recipient_wallet_address`, and `get_notifications(p_network, p_wallet)`
--      is SECURITY DEFINER, never revoked from anon, and takes the wallet as an
--      ARGUMENT. §0.3 says identity IS public.users.id and a wallet is a linked
--      credential; §8 findings 3 and 4 say that taking a wallet as an argument
--      with no proof is the live defect. A table addressed by wallet cannot be
--      made to obey §0.3 by adding a column: the wallet column, its index, its
--      dedupe index and its RPCs would all still be there and still be the
--      path anyone actually uses.
--
--   3. DEDUPE. §8 finding 6: `prediction_activity` dedupes on
--      `UNIQUE(network, tx_signature, type)` with `tx_signature` NULLABLE, and
--      PostgreSQL treats NULLs as distinct, so off-chain rows never conflict
--      and duplicate without bound. The outbox's own dedupe index,
--      `uq_notif_followed_call (recipient_wallet_address, (data->>'activityId'))`,
--      has the SAME shape of hole twice over: `recipient_wallet_address` is
--      nullable, and `data->>'activityId'` is a JSON extraction that is NULL
--      whenever the key is absent — so two notifications with no activityId
--      never conflict either. This file's dedupe key is a NOT NULL text column
--      whose value is COMPUTED BY A TRIGGER out of columns a CHECK forces to be
--      NOT NULL for that kind. There is no NULL anywhere in the uniqueness
--      argument, so there is nothing for PostgreSQL to treat as distinct.
--
--   4. COPY. The outbox stores `title` and `body` as free text written by the
--      trigger that produced the row — and the trigger that writes them today
--      renders football copy about a match and a bucket, with `txSignature` in
--      `data`. This table stores FACTS, NOT COPY: there is no title column, no
--      body column, no note column, no thesis column, no amount column and no
--      signature column. Copy is rendered at read time from `kind`, out of a
--      fixed template table in src/notifications/copy.ts. That absence is the
--      enforcement of the product rule — a stored body cannot carry a stake, a
--      balance, a signature or somebody's thesis if there is no column that
--      could hold one, and no future writer can add one by filling a field in.
--
-- Nothing in the legacy outbox is touched by this file. It keeps working
-- exactly as it does today; the pivot simply does not build on it.
--
-- ── WHAT THIS TABLE DELIVERS ────────────────────────────────────────────────
--
-- The four events that make the loop return, and only these four:
--
--   BACKED    somebody backed your call
--   FADED     somebody faded your call
--   RESOLVED  the venue published a result for your call
--   REMATCH   a rematch is available — either a challenge aimed at you
--             (rematch_reason = 'challenge'), or the person you faded has gone
--             on record again (rematch_reason = 'rival_called_again')
--
-- There is no FOLLOWED_CALL here, and no "someone you follow just called".
-- That is a broadcast, not a relationship: it fires on other people's activity
-- rather than on yours, and it is the copy §0 forbids. Every row in this table
-- is about something that happened TO THE RECIPIENT'S OWN CALL — which is why
-- `subject_call_id` is NOT NULL for every kind and the trigger insists the
-- recipient authored it.
--
-- ── WHAT IS STRUCTURALLY IMPOSSIBLE HERE ────────────────────────────────────
--
--   · Notifying someone about their own action. `actor_user_id` is a CHECKed
--     DISTINCT FROM `recipient_user_id`, and the trigger additionally refuses a
--     response whose actor is the subject call's author.
--   · A duplicate. See reason 3 above.
--   · A stake, a P&L, a balance, a signature, a secret, a thesis or a note.
--     There is no column.
--   · Reading someone else's inbox. `anon` holds no grant at all; the only
--     SELECT policy is `recipient_user_id = public.current_app_user_id()`, and
--     that function is argument-free so it cannot be pointed at another
--     account (Packet A).
--
-- DEPENDENCY: public.current_app_user_id() (Packet A), public.calls and
-- public.call_responses and public.call_results (Packet D).
-- ============================================================================

DO $$
BEGIN
  IF to_regprocedure('public.current_app_user_id()') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_inbox requires public.current_app_user_id() (Packet A: *_auth_identity_* migrations). Apply the auth-identity migrations first; contracts §5 requires every new policy to scope on it.';
  END IF;
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_inbox requires public.calls (Packet D: 20260913140000_social_calls_calls.sql).';
  END IF;
  IF to_regclass('public.call_responses') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_inbox requires public.call_responses (Packet D: 20260913140500_social_calls_responses.sql).';
  END IF;
  IF to_regclass('public.call_results') IS NULL THEN
    RAISE EXCEPTION
      'social_notifications_inbox requires public.call_results (Packet D: 20260913141000_social_calls_results.sql).';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- social_notifications
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.social_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- §0.3: the canonical public.users.id. There is deliberately NO
  -- recipient_wallet_address column — a wallet is a linked credential and
  -- nothing here addresses, authorises or dedupes on one.
  -- ON DELETE CASCADE: an inbox is not a record. When the account goes, the
  -- unread badge goes with it. (Contrast public.calls, which is ON DELETE
  -- RESTRICT because a call IS a record.)
  recipient_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  kind TEXT NOT NULL,

  -- The OTHER person. NULL for RESOLVED, and only for RESOLVED: the venue
  -- published the result and the venue is not a person (§0.2).
  actor_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,

  -- The recipient's OWN call that this is about. NOT NULL for every kind —
  -- that is what makes this an inbox about YOUR calls rather than a broadcast
  -- about other people's activity.
  subject_call_id UUID NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,

  -- The back / fade / challenge that caused it. NULL only where no response
  -- caused it (RESOLVED, and REMATCH/'rival_called_again').
  response_id UUID REFERENCES public.call_responses(id) ON DELETE CASCADE,

  -- REMATCH/'rival_called_again' only: the NEW call the person you faded has
  -- just made. Never the recipient's own.
  rival_call_id UUID REFERENCES public.calls(id) ON DELETE CASCADE,

  -- RESOLVED only. A copy of the §3 CallOutcome the venue evidence derived —
  -- the trigger below refuses any value that disagrees with public.call_results,
  -- so this can never become a second, softer source of a result.
  call_result_outcome TEXT,

  -- REMATCH only.
  rematch_reason TEXT,

  -- ★ THE DEDUPE KEY (§8 finding 6). NOT NULL, non-empty, and COMPUTED by
  --   public.social_notifications_guard() from columns a CHECK forces NOT NULL
  --   for that kind — so a writer cannot supply a weak one and no NULL can
  --   enter the uniqueness argument.
  dedupe_key TEXT NOT NULL DEFAULT '',

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ,

  CONSTRAINT social_notifications_kind_check CHECK (
    kind IN ('BACKED', 'FADED', 'RESOLVED', 'REMATCH')
  ),
  CONSTRAINT social_notifications_outcome_check CHECK (
    call_result_outcome IS NULL OR call_result_outcome IN ('CORRECT', 'INCORRECT', 'VOID')
  ),
  CONSTRAINT social_notifications_rematch_reason_check CHECK (
    rematch_reason IS NULL OR rematch_reason IN ('challenge', 'rival_called_again')
  ),

  -- ★ NEVER NOTIFY SOMEONE ABOUT THEIR OWN ACTION. IS DISTINCT FROM keeps this
  --   total: `actor <> recipient` would evaluate to NULL (and therefore PASS)
  --   on the RESOLVED rows where actor_user_id is NULL.
  CONSTRAINT social_notifications_never_self CHECK (
    actor_user_id IS DISTINCT FROM recipient_user_id
  ),

  -- A rematch never points at the recipient's own call as the rival's call.
  CONSTRAINT social_notifications_rival_is_not_subject CHECK (
    rival_call_id IS NULL OR rival_call_id <> subject_call_id
  ),

  CONSTRAINT social_notifications_dedupe_key_not_blank CHECK (
    length(dedupe_key) BETWEEN 1 AND 200
  ),

  -- ★ THE SHAPE RULE. Exactly one branch matches per row, and each branch
  --   names every column that kind requires and forbids every column it does
  --   not. This is what guarantees the dedupe key is built from NOT NULL
  --   columns: for each kind, the column the key quotes appears in that
  --   branch as IS NOT NULL.
  CONSTRAINT social_notifications_shape CHECK (
    (
      kind IN ('BACKED', 'FADED')
      AND actor_user_id IS NOT NULL
      AND response_id IS NOT NULL
      AND rival_call_id IS NULL
      AND call_result_outcome IS NULL
      AND rematch_reason IS NULL
    )
    OR (
      kind = 'RESOLVED'
      AND actor_user_id IS NULL
      AND response_id IS NULL
      AND rival_call_id IS NULL
      AND call_result_outcome IS NOT NULL
      AND rematch_reason IS NULL
    )
    OR (
      kind = 'REMATCH'
      AND rematch_reason = 'challenge'
      AND actor_user_id IS NOT NULL
      AND response_id IS NOT NULL
      AND rival_call_id IS NULL
      AND call_result_outcome IS NULL
    )
    OR (
      kind = 'REMATCH'
      AND rematch_reason = 'rival_called_again'
      AND actor_user_id IS NOT NULL
      AND rival_call_id IS NOT NULL
      AND response_id IS NULL
      AND call_result_outcome IS NULL
    )
  )
);

-- ★ THE DEDUPE INDEX. Two NOT NULL columns and nothing else. The same person
--   backing the same call twice is the same fact and produces one row: the
--   second INSERT conflicts here rather than sliding past a NULL (§8.6).
CREATE UNIQUE INDEX IF NOT EXISTS uq_social_notifications_dedupe
  ON public.social_notifications (recipient_user_id, dedupe_key);

-- The inbox itself: newest first.
CREATE INDEX IF NOT EXISTS idx_social_notifications_inbox
  ON public.social_notifications (recipient_user_id, created_at DESC);

-- The unread badge.
CREATE INDEX IF NOT EXISTS idx_social_notifications_unread
  ON public.social_notifications (recipient_user_id, created_at DESC)
  WHERE read_at IS NULL;

-- "What has happened to this call?"
CREATE INDEX IF NOT EXISTS idx_social_notifications_subject
  ON public.social_notifications (subject_call_id, created_at DESC);

-- §5 mandatory template (pattern established at 20260719160000:32-34).
ALTER TABLE public.social_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.social_notifications FROM anon, authenticated;
GRANT ALL ON public.social_notifications TO service_role;

-- anon gets NOTHING. Not a grant, not a policy. This is the specific
-- difference from the legacy outbox that §8 finding 3 describes.
GRANT SELECT ON public.social_notifications TO authenticated;

-- The ONLY client-writable column, and the whole of the client write surface.
GRANT UPDATE (read_at) ON public.social_notifications TO authenticated;

-- No INSERT grant and no DELETE grant for any client role: a notification is
-- SERVICE-DERIVED, like a call_result. Nobody may post into someone's inbox.

-- ── SELECT: your own inbox. One real predicate; never USING (true) (§5). ──
DROP POLICY IF EXISTS social_notifications_recipient_select ON public.social_notifications;
CREATE POLICY social_notifications_recipient_select ON public.social_notifications
  FOR SELECT
  TO authenticated
  USING (recipient_user_id = public.current_app_user_id());

-- ── UPDATE: mark your own notifications read (or unread again). The column
--    grant above already limits WHICH column; the trigger below refuses every
--    other change for every writer, service_role included.
DROP POLICY IF EXISTS social_notifications_recipient_mark_read ON public.social_notifications;
CREATE POLICY social_notifications_recipient_mark_read ON public.social_notifications
  FOR UPDATE
  TO authenticated
  USING (recipient_user_id = public.current_app_user_id())
  WITH CHECK (recipient_user_id = public.current_app_user_id());

-- No INSERT policy and no DELETE policy. Deliberately (§5): writes are
-- service_role only, and service_role is the derivation pass in
-- src/notifications/NotificationDeriver.ts.

-- ---------------------------------------------------------------------------
-- THE DEDUPE KEY, as a function so the composition is stated once.
--
-- Per kind it quotes exactly the column that kind's branch of
-- social_notifications_shape makes IS NOT NULL, so the result can never contain
-- a NULL and can never be ambiguous:
--
--   BACKED / FADED                 -> 'BACKED:'  || response_id
--   RESOLVED                       -> 'RESOLVED:' || subject_call_id
--   REMATCH 'challenge'            -> 'REMATCH:challenge:' || response_id
--   REMATCH 'rival_called_again'   -> 'REMATCH:rival:' || rival_call_id
--
-- Scoped by recipient_user_id in the unique index rather than in the key, so
-- two different people may each be told about the same rival call exactly once.
--
-- New, separately-named function; never CREATE OR REPLACE (§5).
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.social_notification_dedupe_key(
  p_kind TEXT,
  p_rematch_reason TEXT,
  p_subject_call_id UUID,
  p_response_id UUID,
  p_rival_call_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
BEGIN
  IF p_kind IN ('BACKED', 'FADED') THEN
    IF p_response_id IS NULL THEN
      RAISE EXCEPTION 'social_notifications: a % needs the response it came from (contracts §8.6: a dedupe key may never quote a nullable column).', p_kind
        USING ERRCODE = 'raise_exception';
    END IF;
    RETURN p_kind || ':' || p_response_id::text;
  END IF;

  IF p_kind = 'RESOLVED' THEN
    IF p_subject_call_id IS NULL THEN
      RAISE EXCEPTION 'social_notifications: a RESOLVED needs the call it is about.'
        USING ERRCODE = 'raise_exception';
    END IF;
    RETURN 'RESOLVED:' || p_subject_call_id::text;
  END IF;

  IF p_kind = 'REMATCH' AND p_rematch_reason = 'challenge' THEN
    IF p_response_id IS NULL THEN
      RAISE EXCEPTION 'social_notifications: a challenge rematch needs the challenge response it came from.'
        USING ERRCODE = 'raise_exception';
    END IF;
    RETURN 'REMATCH:challenge:' || p_response_id::text;
  END IF;

  IF p_kind = 'REMATCH' AND p_rematch_reason = 'rival_called_again' THEN
    IF p_rival_call_id IS NULL THEN
      RAISE EXCEPTION 'social_notifications: a rival rematch needs the rival''s new call.'
        USING ERRCODE = 'raise_exception';
    END IF;
    RETURN 'REMATCH:rival:' || p_rival_call_id::text;
  END IF;

  RAISE EXCEPTION 'social_notifications: no dedupe key is defined for kind % / reason %.', p_kind, COALESCE(p_rematch_reason, 'none')
    USING ERRCODE = 'raise_exception';
END;
$$;

REVOKE EXECUTE ON FUNCTION public.social_notification_dedupe_key(TEXT, TEXT, UUID, UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.social_notification_dedupe_key(TEXT, TEXT, UUID, UUID, UUID) TO service_role;

-- ---------------------------------------------------------------------------
-- THE GUARD. Everything a CHECK cannot see, plus the immutability of a
-- delivered notification.
--
-- It binds service_role as well as clients — RLS does not, and service_role is
-- what the BFF uses for every write (§2). This is therefore the only layer that
-- protects these rules from our own bugs.
-- ---------------------------------------------------------------------------

CREATE FUNCTION public.social_notifications_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp   -- REQUIRED (§5)
AS $$
DECLARE
  v_subject_author  UUID;
  v_resp_actor      UUID;
  v_resp_kind       TEXT;
  v_resp_target     UUID;
  v_rival_author    UUID;
  v_rival_hidden    TIMESTAMPTZ;
  v_outcome         TEXT;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    -- read_at is the ONLY thing that may move. Everything else is the fact the
    -- notification states, and a delivered fact is not editable.
    IF NEW.id                  IS DISTINCT FROM OLD.id
       OR NEW.recipient_user_id IS DISTINCT FROM OLD.recipient_user_id
       OR NEW.kind              IS DISTINCT FROM OLD.kind
       OR NEW.actor_user_id     IS DISTINCT FROM OLD.actor_user_id
       OR NEW.subject_call_id   IS DISTINCT FROM OLD.subject_call_id
       OR NEW.response_id       IS DISTINCT FROM OLD.response_id
       OR NEW.rival_call_id     IS DISTINCT FROM OLD.rival_call_id
       OR NEW.call_result_outcome IS DISTINCT FROM OLD.call_result_outcome
       OR NEW.rematch_reason    IS DISTINCT FROM OLD.rematch_reason
       OR NEW.dedupe_key        IS DISTINCT FROM OLD.dedupe_key
       OR NEW.created_at        IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION
        'social_notifications: only read_at may change after delivery (notification %).', OLD.id
        USING ERRCODE = 'raise_exception';
    END IF;
    RETURN NEW;
  END IF;

  -- ── INSERT ──

  -- ★ The key is OURS, not the writer's. Whatever arrived is overwritten with
  --   the canonical composition, so a caller cannot weaken dedupe by supplying
  --   a unique-per-attempt string (§8.6).
  NEW.dedupe_key := public.social_notification_dedupe_key(
    NEW.kind, NEW.rematch_reason, NEW.subject_call_id, NEW.response_id, NEW.rival_call_id
  );

  SELECT c.user_id INTO v_subject_author FROM public.calls c WHERE c.id = NEW.subject_call_id;
  IF v_subject_author IS NULL THEN
    RAISE EXCEPTION 'social_notifications: subject call % does not exist.', NEW.subject_call_id
      USING ERRCODE = 'raise_exception';
  END IF;

  -- ★ An inbox is about YOUR OWN calls. Every kind, no exception.
  IF v_subject_author <> NEW.recipient_user_id THEN
    RAISE EXCEPTION
      'social_notifications: call % belongs to %, not to recipient % — this table carries notifications about the recipient''s OWN calls, never a broadcast about someone else''s activity.',
      NEW.subject_call_id, v_subject_author, NEW.recipient_user_id
      USING ERRCODE = 'raise_exception';
  END IF;

  IF NEW.response_id IS NOT NULL THEN
    SELECT r.actor_user_id, r.kind, r.target_call_id
      INTO v_resp_actor, v_resp_kind, v_resp_target
      FROM public.call_responses r WHERE r.id = NEW.response_id;

    IF v_resp_actor IS NULL THEN
      RAISE EXCEPTION 'social_notifications: response % does not exist.', NEW.response_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- The response must be about the very call this notification is about.
    IF v_resp_target <> NEW.subject_call_id THEN
      RAISE EXCEPTION
        'social_notifications: response % is about call %, not about call %.',
        NEW.response_id, v_resp_target, NEW.subject_call_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- The actor named must be the person who actually acted.
    IF v_resp_actor <> NEW.actor_user_id THEN
      RAISE EXCEPTION
        'social_notifications: response % was made by %, but the notification names % as the actor.',
        NEW.response_id, v_resp_actor, NEW.actor_user_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- ★ Never notify someone about their own action. public.call_responses
    --   already refuses a self-response, so reaching this means the row was
    --   inserted before that guard existed or around it.
    IF v_resp_actor = NEW.recipient_user_id THEN
      RAISE EXCEPTION
        'social_notifications: % is the person who acted; nobody is notified about their own action.', v_resp_actor
        USING ERRCODE = 'raise_exception';
    END IF;

    -- back -> BACKED, fade -> FADED, challenge -> REMATCH/'challenge'. The
    -- words have to keep meaning what they say.
    IF NEW.kind = 'BACKED' AND v_resp_kind <> 'back' THEN
      RAISE EXCEPTION 'social_notifications: a BACKED must cite a ''back'' response (response % is a %).', NEW.response_id, v_resp_kind
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.kind = 'FADED' AND v_resp_kind <> 'fade' THEN
      RAISE EXCEPTION 'social_notifications: a FADED must cite a ''fade'' response (response % is a %).', NEW.response_id, v_resp_kind
        USING ERRCODE = 'raise_exception';
    END IF;
    IF NEW.kind = 'REMATCH' AND NEW.rematch_reason = 'challenge' AND v_resp_kind <> 'challenge' THEN
      RAISE EXCEPTION 'social_notifications: a challenge rematch must cite a ''challenge'' response (response % is a %).', NEW.response_id, v_resp_kind
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  IF NEW.rival_call_id IS NOT NULL THEN
    SELECT c.user_id, c.hidden_at INTO v_rival_author, v_rival_hidden
      FROM public.calls c WHERE c.id = NEW.rival_call_id;

    IF v_rival_author IS NULL THEN
      RAISE EXCEPTION 'social_notifications: rival call % does not exist.', NEW.rival_call_id
        USING ERRCODE = 'raise_exception';
    END IF;
    IF v_rival_author <> NEW.actor_user_id THEN
      RAISE EXCEPTION
        'social_notifications: rival call % belongs to %, but the notification names % as the actor.',
        NEW.rival_call_id, v_rival_author, NEW.actor_user_id
        USING ERRCODE = 'raise_exception';
    END IF;
    IF v_rival_author = NEW.recipient_user_id THEN
      RAISE EXCEPTION
        'social_notifications: nobody is told they have called again; a rematch names the OTHER person.'
        USING ERRCODE = 'raise_exception';
    END IF;
    -- A hidden call is withdrawn from distribution (§3). It cannot be the
    -- reason for a notification either.
    IF v_rival_hidden IS NOT NULL THEN
      RAISE EXCEPTION
        'social_notifications: rival call % is hidden and is not distributed (contracts §3).', NEW.rival_call_id
        USING ERRCODE = 'raise_exception';
    END IF;

    -- ★ "The person you faded has called again" requires that you actually
    --   faded them. Without this, a rematch would be an unsolicited ping about
    --   a stranger's activity — the broadcast this table exists not to be.
    IF NOT EXISTS (
      SELECT 1
      FROM public.call_responses f
      JOIN public.calls t ON t.id = f.target_call_id
      WHERE f.kind = 'fade'
        AND f.actor_user_id = NEW.recipient_user_id
        AND t.user_id = NEW.actor_user_id
    ) THEN
      RAISE EXCEPTION
        'social_notifications: % has never faded a call by %, so there is no rematch to offer.',
        NEW.recipient_user_id, NEW.actor_user_id
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  IF NEW.kind = 'RESOLVED' THEN
    SELECT r.outcome INTO v_outcome FROM public.call_results r WHERE r.call_id = NEW.subject_call_id;
    IF v_outcome IS NULL THEN
      RAISE EXCEPTION
        'social_notifications: call % has no derived result at all, so nothing has resolved (contracts §0.2).', NEW.subject_call_id
        USING ERRCODE = 'raise_exception';
    END IF;
    -- ★ PENDING is never a notification. A market that closed long ago, or
    --   whose status reads RESOLVED while the venue has published nothing,
    --   stays silent. Absence of evidence is not evidence (§0.2).
    IF v_outcome = 'PENDING' THEN
      RAISE EXCEPTION
        'social_notifications: call % is still PENDING; the venue has published no resolution and PENDING is never announced (contracts §0.2/§3).', NEW.subject_call_id
        USING ERRCODE = 'raise_exception';
    END IF;
    -- This column may only ever quote public.call_results. It is not a second,
    -- softer source of a result.
    IF NEW.call_result_outcome <> v_outcome THEN
      RAISE EXCEPTION
        'social_notifications: call % resolved %, but the notification says % — a notification quotes call_results, it never restates it (contracts §0.2).',
        NEW.subject_call_id, v_outcome, NEW.call_result_outcome
        USING ERRCODE = 'raise_exception';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.social_notifications_guard() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.social_notifications_guard() TO service_role;

DROP TRIGGER IF EXISTS trg_social_notifications_guard ON public.social_notifications;
CREATE TRIGGER trg_social_notifications_guard
  BEFORE INSERT OR UPDATE ON public.social_notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.social_notifications_guard();

COMMENT ON TABLE public.social_notifications IS
  'The four relational notifications that make the loop return: BACKED, FADED, RESOLVED, REMATCH. A NEW default-deny table rather than an extension of public.notification_outbox, because that table''s SELECT policy is USING (true) and PostgreSQL ORs permissive policies together, so a tight policy beside it is a no-op (contracts §2, §8 finding 3). Addressed by canonical public.users.id, never by wallet (§0.3). Stores FACTS, NOT COPY: there is no title, body, note, thesis, amount, stake, balance or signature column, so a notification cannot carry one. Service-write only; a client may read its own rows and set read_at, and anon holds no grant at all.';
COMMENT ON COLUMN public.social_notifications.dedupe_key IS
  'Computed by the guard trigger from columns a CHECK forces NOT NULL for that kind, and unique per recipient. Contrast §8 finding 6: prediction_activity dedupes on UNIQUE(network, tx_signature, type) with tx_signature NULLABLE, and PostgreSQL treats NULLs as distinct, so those rows duplicate without bound. No NULL appears anywhere in this uniqueness argument.';
COMMENT ON COLUMN public.social_notifications.subject_call_id IS
  'The RECIPIENT''S OWN call, for every kind — enforced by the guard trigger. This is what makes the table an inbox about your calls rather than a broadcast about other people''s activity.';
COMMENT ON COLUMN public.social_notifications.call_result_outcome IS
  'RESOLVED only, and only ever a verbatim quote of public.call_results.outcome, checked by the trigger. PENDING is never announced (§0.2).';
COMMENT ON COLUMN public.social_notifications.rematch_reason IS
  '''challenge'' = somebody challenged a call of yours. ''rival_called_again'' = somebody you FADED has gone on record again; the trigger verifies the fade actually happened.';
