-- ============================================================================
-- PACKET B — venue market catalog: venue_markets + market_snapshots
-- Created: 2026-09-13
-- Contract: docs/contracts/pivot-contracts-v1.md §3 (normalized vocabulary),
--           §4 (adapter rules), §5 (additive, new tables, default-deny)
-- ============================================================================
--
-- WHY NEW TABLES AND NOT prediction_markets:
--   prediction_markets.match_id is NOT NULL (20260715134226:176-183). A venue
--   market has no fixture, so reusing that table would mean relaxing a legacy
--   NOT NULL — a rewrite, not an addition (§2). Worse, the legacy table already
--   carries `USING (true)` policies, and PostgreSQL ORs permissive policies
--   together, so a tight policy added beside one is a no-op (§2). Hence: new
--   tables, default-deny, per the §5 template.
--
-- WHY BOTH raw_payload AND the normalized columns:
--   §4 requires the raw provider payload to be stored for debugging AND the
--   versioned normalized form. payload_version says which normalisation wrote
--   the row, so a later adapter change is diagnosable instead of ambiguous.
--
-- WHY is_demo IS GENERATED, NOT SET BY THE WRITER:
--   §4 says fixture data must be visibly labelled and can never present as a
--   live result. Deriving it from `venue` makes that structural: there is no
--   write that produces a fixture row without the demo flag.
--
-- NOTE (§9): verify against the LIVE database before applying. Writing additive
-- new tables is safe without that reconciliation; altering anything existing is
-- not, and this migration alters nothing existing.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- venue_markets — one row per normalized market, keyed by the stable
-- Chumbucket UUID the BFF derives deterministically from (venue, venue_market_id).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.venue_markets (
  -- Supplied by the BFF (a deterministic UUIDv5 over venue + venue_market_id),
  -- never defaulted here: re-syncing the same venue market must hit the same row.
  id UUID PRIMARY KEY,
  venue TEXT NOT NULL,
  venue_event_id TEXT NOT NULL,
  -- Preserved verbatim, never re-encoded (§3).
  venue_market_id TEXT NOT NULL,
  question TEXT NOT NULL,
  -- The venue's exact resolution criteria — never paraphrased (§3).
  rules_text TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'crypto',
  outcomes JSONB NOT NULL,
  status TEXT NOT NULL,
  -- The venue's own status string, unmapped (§3) — the audit trail for a
  -- normalisation dispute.
  raw_status TEXT NOT NULL,
  opens_at TIMESTAMPTZ,
  closes_at TIMESTAMPTZ,
  resolves_at TIMESTAMPTZ,
  resolution_source TEXT,
  last_synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload_version INTEGER NOT NULL,
  -- The provider payload the normalized columns were read out of (§4).
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Lets a market be withdrawn from public reads without deleting evidence.
  -- Also the reason the SELECT policy below is a real predicate, not USING (true).
  is_public BOOLEAN NOT NULL DEFAULT TRUE,
  is_demo BOOLEAN GENERATED ALWAYS AS (venue = 'fixture') STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT venue_markets_venue_check CHECK (venue IN ('jupiter', 'fixture')),
  -- The five MarketStatus values are frozen (§3). Never collapse them.
  CONSTRAINT venue_markets_status_check CHECK (
    status IN ('OPEN', 'CLOSED_PENDING_RESOLUTION', 'RESOLVED', 'CANCELLED', 'PAUSED')
  ),
  CONSTRAINT venue_markets_payload_version_check CHECK (payload_version > 0),
  -- A binary market has exactly one YES and one NO outcome. A market that stops
  -- being binary is a schema change and must not land as a half-parsed row (§4).
  CONSTRAINT venue_markets_outcomes_binary CHECK (
    jsonb_typeof(outcomes) = 'array'
    AND jsonb_array_length(outcomes) = 2
    AND outcomes @> '[{"side": "YES"}]'::jsonb
    AND outcomes @> '[{"side": "NO"}]'::jsonb
  ),
  -- A LIVE venue row must always carry the payload it was parsed from. Without
  -- it, a disputed normalisation cannot be re-derived from anything.
  CONSTRAINT venue_markets_live_rows_keep_raw CHECK (
    venue <> 'jupiter' OR raw_payload <> '{}'::jsonb
  ),
  UNIQUE (venue, venue_market_id)
);

CREATE INDEX IF NOT EXISTS idx_venue_markets_status
  ON public.venue_markets (status, closes_at);
CREATE INDEX IF NOT EXISTS idx_venue_markets_event
  ON public.venue_markets (venue, venue_event_id);
CREATE INDEX IF NOT EXISTS idx_venue_markets_category
  ON public.venue_markets (category, status);

-- §5 mandatory template (pattern established at 20260719160000:32-34).
ALTER TABLE public.venue_markets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.venue_markets FROM anon, authenticated;
GRANT ALL ON public.venue_markets TO service_role;

-- Market data is public-readable (§5, Packet B). The grant is SELECT ONLY, and
-- the policy is a real predicate — NOT `USING (true)`, which §5 forbids on a new
-- table — so a market can be withdrawn from public reads by flipping is_public.
GRANT SELECT ON public.venue_markets TO anon, authenticated;

DROP POLICY IF EXISTS venue_markets_public_select ON public.venue_markets;
CREATE POLICY venue_markets_public_select ON public.venue_markets
  FOR SELECT
  TO anon, authenticated
  USING (is_public AND venue IN ('jupiter', 'fixture'));

-- No INSERT / UPDATE / DELETE policy exists: writes are service_role only, which
-- is the BFF synchroniser. Contract §0.2 — the venue is the only source of a
-- result, and the BFF is the only writer of venue data.

COMMENT ON TABLE public.venue_markets IS
  'Normalized venue markets (contracts §3). Public SELECT via is_public; ALL writes are service_role (the BFF synchroniser) only. raw_payload keeps the provider JSON the normalized columns were parsed from; payload_version says which adapter normalisation produced them.';
COMMENT ON COLUMN public.venue_markets.is_demo IS
  'Generated from venue. TRUE = fixture/demo catalog. Never a live result; the UI must label it.';
COMMENT ON COLUMN public.venue_markets.raw_status IS
  'The venue''s own status string, unmapped. Kept so a normalisation dispute is decidable.';

-- ---------------------------------------------------------------------------
-- market_snapshots — the price series behind entry_probability on a call.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.market_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  market_id UUID NOT NULL REFERENCES public.venue_markets(id) ON DELETE CASCADE,
  -- Probabilities are numbers in [0,1] (§3). NUMERIC, never a float.
  yes_probability NUMERIC(9, 8) NOT NULL,
  observed_at TIMESTAMPTZ NOT NULL,
  source TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT market_snapshots_probability_range CHECK (yes_probability >= 0 AND yes_probability <= 1),
  CONSTRAINT market_snapshots_source_check CHECK (source IN ('venue', 'fixture')),
  -- Idempotent polling: re-observing the same instant from the same source is
  -- the SAME row, not a duplicate. (Contrast prediction_activity, whose nullable
  -- tx_signature in a UNIQUE lets NULLs duplicate without bound — §8.6.)
  UNIQUE (market_id, observed_at, source)
);

CREATE INDEX IF NOT EXISTS idx_market_snapshots_latest
  ON public.market_snapshots (market_id, observed_at DESC);

ALTER TABLE public.market_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.market_snapshots FROM anon, authenticated;
GRANT ALL ON public.market_snapshots TO service_role;

GRANT SELECT ON public.market_snapshots TO anon, authenticated;

DROP POLICY IF EXISTS market_snapshots_public_select ON public.market_snapshots;
CREATE POLICY market_snapshots_public_select ON public.market_snapshots
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.venue_markets m
      WHERE m.id = market_snapshots.market_id
        AND m.is_public
    )
  );

COMMENT ON TABLE public.market_snapshots IS
  'Observed YES probability for a venue market (contracts §3). Readable exactly when its market is public; written only by the BFF (service_role). UNIQUE(market_id, observed_at, source) makes repeated polling idempotent.';
