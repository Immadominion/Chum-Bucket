-- ============================================================================
-- NOTIFICATIONS — fan-out generation + read model + realtime
-- Created: 2026-07-16
-- ============================================================================
--
-- Builds on the notification_outbox the settlement pipeline already writes
-- (CLAIM_AVAILABLE for winners). Adds:
--   1. FOLLOWED_CALL fan-out — when a caller you follow places a (confirmed)
--      call, every follower gets a notification. This is the FOMO engagement
--      driver ("someone you follow just called HOME on Nigeria–Brazil").
--   2. read state (read_at) + get/mark-read RPCs.
--   3. a public-select policy so clients can subscribe via Supabase Realtime
--      for instant delivery (notifications reference already-public activity).
--
-- Delivery is channel-agnostic: the outbox is the source of truth; a client
-- subscribes to Realtime (or polls get_notifications), and a future FCM worker
-- can drain `status = 'pending'` rows for native push (needs Firebase Admin
-- creds + a device-token registry — documented, not wired here).
-- ============================================================================

ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ;

-- Dedup guard: at most one FOLLOWED_CALL per (recipient, source activity).
CREATE UNIQUE INDEX IF NOT EXISTS uq_notif_followed_call
ON public.notification_outbox (recipient_wallet_address, (data->>'activityId'))
WHERE type = 'FOLLOWED_CALL';

CREATE INDEX IF NOT EXISTS idx_notif_recipient
ON public.notification_outbox (network, recipient_wallet_address, created_at DESC);

-- ---------------------------------------------------------------------------
-- Fan-out: a followed caller's confirmed call notifies their followers.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.notify_followers_on_activity()
RETURNS TRIGGER AS $$
BEGIN
  -- Fire once, on the transition into a public, VERIFIED call (not on the
  -- optimistic PENDING insert), so followers are pinged for real calls only.
  IF NEW.type = 'CALL_PLACED'
     AND NEW.status = 'VERIFIED'
     AND NEW.visibility = 'public'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'VERIFIED') THEN
    INSERT INTO public.notification_outbox (
      network, recipient_user_id, recipient_wallet_address, type, title, body, data
    )
    SELECT
      NEW.network,
      f.follower_user_id,
      f.follower_wallet,
      'FOLLOWED_CALL',
      'A caller you follow just called',
      COALESCE(NEW.bucket, '') || CASE WHEN NEW.match_id IS NOT NULL THEN ' on ' || NEW.match_id ELSE '' END,
      jsonb_build_object(
        'actorWallet', NEW.actor_wallet_address,
        'marketId', NEW.market_id,
        'matchId', NEW.match_id,
        'bucket', NEW.bucket,
        'activityId', NEW.id,
        'txSignature', NEW.tx_signature
      )
    FROM public.follows f
    WHERE f.network = NEW.network
      AND f.followee_wallet = NEW.actor_wallet_address
    ON CONFLICT (recipient_wallet_address, (data->>'activityId')) WHERE type = 'FOLLOWED_CALL'
    DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

DROP TRIGGER IF EXISTS trg_notify_followers ON public.prediction_activity;
CREATE TRIGGER trg_notify_followers
AFTER INSERT OR UPDATE OF status ON public.prediction_activity
FOR EACH ROW EXECUTE FUNCTION public.notify_followers_on_activity();

-- ---------------------------------------------------------------------------
-- Read model.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_notifications(
  p_network TEXT,
  p_wallet TEXT,
  p_limit INTEGER DEFAULT 50,
  p_unread_only BOOLEAN DEFAULT false
)
RETURNS SETOF public.notification_outbox AS $$
  SELECT *
  FROM public.notification_outbox
  WHERE network = p_network
    AND recipient_wallet_address = trim(p_wallet)
    AND (NOT p_unread_only OR read_at IS NULL)
  ORDER BY created_at DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION public.unread_notification_count(
  p_network TEXT,
  p_wallet TEXT
)
RETURNS INTEGER AS $$
  SELECT count(*)::int
  FROM public.notification_outbox
  WHERE network = p_network AND recipient_wallet_address = trim(p_wallet) AND read_at IS NULL;
$$ LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- Scoped to the wallet's OWN notifications (backend wallet-sig-auths the caller).
CREATE OR REPLACE FUNCTION public.mark_notifications_read(
  p_network TEXT,
  p_wallet TEXT,
  p_ids UUID[] DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.notification_outbox
  SET read_at = NOW()
  WHERE network = p_network
    AND recipient_wallet_address = trim(p_wallet)
    AND read_at IS NULL
    AND (p_ids IS NULL OR id = ANY(p_ids));  -- null ids => mark all read
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp;

-- ---------------------------------------------------------------------------
-- RLS + grants. Notifications reference already-public activity, so a public
-- select policy is consistent with the model and enables Realtime subscriptions
-- (clients filter by recipient_wallet_address). mark_notifications_read is a
-- write => service-role only (backend calls it after wallet-signature auth).
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS notification_outbox_public_select ON public.notification_outbox;
CREATE POLICY notification_outbox_public_select ON public.notification_outbox
FOR SELECT USING (true);

REVOKE EXECUTE ON FUNCTION public.mark_notifications_read(TEXT, TEXT, UUID[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(TEXT, TEXT, UUID[]) TO service_role;

COMMENT ON FUNCTION public.notify_followers_on_activity() IS 'FOMO fan-out: a followed caller''s confirmed call notifies every follower (once).';
