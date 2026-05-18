-- =============================================================================
-- Migration 018: Povio API sync — Phase 1 schema
-- =============================================================================
-- Establishes the link between our `whales` and Povio's `clients` (the public
-- API at https://app.povio.com/api/public/openapi). Adds a parallel ARR column
-- so the Povio-derived number lives alongside the manual estimate without
-- overwriting it. Also adds a sync-run log so the Admin UI can show "last
-- sync 2h ago · 23 invoices · 18 whales updated".
--
-- The actual sync runs in a Supabase Edge Function (supabase/functions/
-- povio-sync) — this migration only sets up the tables it reads/writes.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Link table: whale.id ⇄ Povio client_id
--    One row per whale that maps to a Povio client. Whales not billed via
--    Povio (deals, prospects, partners) simply have no row here — they will
--    show up in the Admin "unlinked" list for explicit review.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS povio_clients (
    whale_id          integer PRIMARY KEY REFERENCES whales(id) ON DELETE CASCADE,
    povio_client_id   integer NOT NULL,
    povio_company     text NOT NULL,                          -- snapshot of the name at link time, for "diverged?" detection
    match_confidence  text NOT NULL,                          -- 'exact' | 'fuzzy' | 'manual'
    linked_by         text REFERENCES allowed_users(povio_id),
    linked_at         timestamptz DEFAULT now(),
    last_synced_at    timestamptz,
    CONSTRAINT povio_clients_uniq_povio UNIQUE (povio_client_id),
    CONSTRAINT povio_clients_match_confidence_check
        CHECK (match_confidence IN ('exact', 'fuzzy', 'manual'))
);

CREATE INDEX IF NOT EXISTS idx_povio_clients_client_id ON povio_clients(povio_client_id);

-- -----------------------------------------------------------------------------
-- 2. Parallel ARR field on whales.
--    Always overwritten by sync; manual `whales.arr` is untouched.
--    Stored in $K, same scale as the existing arr column, so the UI can
--    show both side-by-side without unit-conversion gymnastics.
-- -----------------------------------------------------------------------------
ALTER TABLE whales
    ADD COLUMN IF NOT EXISTS arr_from_povio numeric,
    ADD COLUMN IF NOT EXISTS povio_synced_at timestamptz;

-- -----------------------------------------------------------------------------
-- 3. Sync-run log.
--    Each invocation of the Edge Function's sync action inserts one row.
--    Admin UI shows the last 10 rows in a table for visibility into when
--    the integration is healthy vs degraded.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS povio_sync_runs (
    id              bigserial PRIMARY KEY,
    started_at      timestamptz DEFAULT now(),
    finished_at     timestamptz,
    triggered_by    text,                                     -- povio_id of admin who clicked "Sync now"; null for cron
    invoices_pulled int DEFAULT 0,
    whales_updated  int DEFAULT 0,
    errors          text[],
    summary         text
);

CREATE INDEX IF NOT EXISTS idx_povio_sync_runs_started ON povio_sync_runs(started_at DESC);

-- -----------------------------------------------------------------------------
-- 4. RLS — admin reads/writes only for the operational tables.
--    Reps don't need to see the wiring; they only need the resulting
--    whales.arr_from_povio number which they get for free via the existing
--    whales RLS.
-- -----------------------------------------------------------------------------
ALTER TABLE povio_clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE povio_sync_runs ENABLE ROW LEVEL SECURITY;

-- povio_clients: any authenticated user can READ (so the sidebar can show
-- "linked to Povio" indicator); WRITE is admin-only (matching is a
-- Vid-curated operation).
CREATE POLICY pc_read   ON povio_clients FOR SELECT USING (is_user_allowed());
CREATE POLICY pc_write  ON povio_clients FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- povio_sync_runs: admin-only end-to-end (operational diagnostic data).
CREATE POLICY psr_read  ON povio_sync_runs FOR SELECT USING (is_admin());
CREATE POLICY psr_write ON povio_sync_runs FOR INSERT WITH CHECK (is_admin());
CREATE POLICY psr_upd   ON povio_sync_runs FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());

-- -----------------------------------------------------------------------------
-- 5. Verification (run manually after the migration lands):
--
--   -- Tables exist:
--   SELECT table_name FROM information_schema.tables
--    WHERE table_name IN ('povio_clients','povio_sync_runs');
--   -- Columns exist on whales:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='whales'
--      AND column_name IN ('arr_from_povio','povio_synced_at');
--   -- RLS enabled:
--   SELECT relname, relrowsecurity FROM pg_class
--    WHERE relname IN ('povio_clients','povio_sync_runs');
-- -----------------------------------------------------------------------------
