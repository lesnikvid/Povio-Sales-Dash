-- =============================================================================
-- Migration 002: Merge "Sales Command Center" (App B) into production
-- =============================================================================
-- Applies on top of:
--   - supabase-schema.sql (the canonical bootstrap — already in production)
--   - .private-docs/ADD_CONTACTS_AND_REFERRALS.sql (contacts/referrals on whales)
--
-- Scope:
--   1. Extend allowed_users with role + directory fields (admin / rep + name, color)
--   2. Add is_admin() helper
--   3. Extend whales with App B's columns (FTE, engagement_type, qbr_history, …)
--   4. Add new tables for B's sections (todos, pipeline_deals, activities, …)
--   5. Rewrite RLS so AMs can read/edit ALL whales but admin-only for the rest
--
-- Run via: Supabase Dashboard → SQL Editor → paste this whole file → Run.
-- Idempotent: safe to re-run. All ADD COLUMN / CREATE TABLE use IF NOT EXISTS.
--
-- ⚠ DESTRUCTIVE NOTE: section 5 DROPS the existing user_id-scoped RLS policies
--    on whales / whale_notes / calendar_events and replaces them. Vid keeps full
--    access via is_admin(); AMs gain access via is_user_allowed().
--    To rollback: re-run supabase-schema.sql + ADD_CONTACTS_AND_REFERRALS.sql.
-- =============================================================================


-- =============================================================================
-- 1. Extend allowed_users — promote it from "allowlist" to "users + roles + directory"
-- =============================================================================

ALTER TABLE allowed_users
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'rep' CHECK (role IN ('admin', 'rep')),
    ADD COLUMN IF NOT EXISTS povio_id TEXT UNIQUE,
    ADD COLUMN IF NOT EXISTS name TEXT,
    ADD COLUMN IF NOT EXISTS initials TEXT,
    ADD COLUMN IF NOT EXISTS color TEXT;

-- Promote Vid to admin (idempotent)
UPDATE allowed_users SET role = 'admin', povio_id = 'u_vl', name = 'Vid Lešnik', initials = 'VL', color = '#1F35FF'
WHERE email = 'lesnik.vid@gmail.com';

-- Seed the 5 active AMs as reps + a sentinel "Unassigned" placeholder.
-- Real emails confirmed by Vid 2026-05-11.
INSERT INTO allowed_users (email, role, povio_id, name, initials, color, notes) VALUES
    ('ziga.triller@povio.com',  'rep', 'u_zt', 'Žiga Triller', 'ŽT', '#7C3AED', 'AM'),
    ('dasa.ravter@povio.com',   'rep', 'u_dr', 'Daša Ravter',  'DR', '#EC4899', 'AM'),
    ('edvin.lovic@povio.com',   'rep', 'u_el', 'Edvin Lovic',  'EL', '#10B981', 'AM'),
    ('gregor.span@povio.com',   'rep', 'u_gs', 'Gregor Špan',  'GŠ', '#F59E0B', 'AM'),
    ('sara.petric@povio.com',   'rep', 'u_sp', 'Sara Petric',  'SP', '#06B6D4', 'AM'),
    ('__unassigned__@internal', 'rep', 'u_unassigned', 'Unassigned', '—', '#A3A3A3', 'Placeholder for accounts with no AM')
ON CONFLICT (email) DO UPDATE SET
    role = EXCLUDED.role,
    povio_id = EXCLUDED.povio_id,
    name = EXCLUDED.name,
    initials = EXCLUDED.initials,
    color = EXCLUDED.color;

-- Inactive / historical AMs that appear as account_manager on existing whales but no longer
-- log in. Seeded with synthetic emails (cannot authenticate via Google Workspace) so the
-- directory lookup still resolves their avatar / initials.
INSERT INTO allowed_users (email, role, povio_id, name, initials, color, notes) VALUES
    ('durdica.inactive@local',  'rep', 'u_dsk', 'Durdica Strunjas Kurt', 'DS', '#06B6D4', 'Inactive — directory only'),
    ('klemen.inactive@local',   'rep', 'u_kv',  'Klemen Vute',           'KV', '#8B5CF6', 'Inactive — directory only'),
    ('lana.inactive@local',     'rep', 'u_ls',  'Lana Špiler',           'LŠ', '#F43F5E', 'Inactive — directory only'),
    ('jakob.inactive@local',    'rep', 'u_jc',  'Jakob Cvetko',          'JC', '#0EA5E9', 'Inactive — directory only'),
    ('jernej.inactive@local',   'rep', 'u_jl',  'Jernej Lešnik',         'JL', '#84CC16', 'Inactive — directory only')
ON CONFLICT (email) DO UPDATE SET
    name = EXCLUDED.name,
    notes = EXCLUDED.notes;


-- =============================================================================
-- 2. Helper functions
-- =============================================================================

-- Is the current authenticated user an admin?
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1 FROM allowed_users
        WHERE email = (auth.jwt() ->> 'email') AND role = 'admin'
    );
$$;

-- The povio_id for the current user (u_vl, u_zt, …) — used to stamp audit fields
CREATE OR REPLACE FUNCTION current_povio_id()
RETURNS TEXT
LANGUAGE SQL STABLE SECURITY DEFINER
AS $$
    SELECT povio_id FROM allowed_users WHERE email = (auth.jwt() ->> 'email');
$$;


-- =============================================================================
-- 3. Extend whales with App B's columns
-- =============================================================================

ALTER TABLE whales
    ADD COLUMN IF NOT EXISTS is_key_account       boolean DEFAULT false,
    ADD COLUMN IF NOT EXISTS fte                  numeric,
    ADD COLUMN IF NOT EXISTS engagement_type      text,                          -- team_aug | agency | hybrid
    ADD COLUMN IF NOT EXISTS engagement_hours_week text,
    ADD COLUMN IF NOT EXISTS account_status_raw   text,                          -- "All good" / "Observing" / "Firefighting"
    ADD COLUMN IF NOT EXISTS forecast_raw         text,                          -- "Increasing Revenue ↗️" etc.
    ADD COLUMN IF NOT EXISTS expansion_potential  text,                          -- low | medium | high | none
    ADD COLUMN IF NOT EXISTS potential_flag       text,                          -- "Yes" / "No" / "Don't know yet"
    ADD COLUMN IF NOT EXISTS last_note            text,
    ADD COLUMN IF NOT EXISTS project_manager      text,
    ADD COLUMN IF NOT EXISTS team_members         jsonb DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS invoicing_note       text,
    ADD COLUMN IF NOT EXISTS qbr_history          jsonb DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS owner_povio_id       text,                          -- u_vl / u_zt / … (separate from existing account_manager text)
    ADD COLUMN IF NOT EXISTS created_date         date,
    ADD COLUMN IF NOT EXISTS last_touch_at        date,
    ADD COLUMN IF NOT EXISTS source               text DEFAULT 'manual',         -- 'am_board_import' for the 198
    ADD COLUMN IF NOT EXISTS updated_by_povio_id  text;                          -- audit trail

-- Mark all currently-existing whales as key accounts (they are Vid's hand-picked ones)
UPDATE whales SET is_key_account = true WHERE source IS NULL OR source = 'manual';

CREATE INDEX IF NOT EXISTS idx_whales_owner_povio    ON whales(owner_povio_id);
CREATE INDEX IF NOT EXISTS idx_whales_is_key_account ON whales(is_key_account);
CREATE INDEX IF NOT EXISTS idx_whales_source         ON whales(source);


-- =============================================================================
-- 4. New tables — admin-only sections (Dashboard, My Week, Process, Admin)
--    + activities (collaborative audit trail on whales)
-- =============================================================================

-- Activities — audit trail on whale edits + manual notes. Readable + writable
-- by any AM (so audit logging works for everyone), deletable only by admin.
CREATE TABLE IF NOT EXISTS activities (
    id SERIAL PRIMARY KEY,
    whale_id INTEGER REFERENCES whales(id) ON DELETE CASCADE,
    actor_povio_id TEXT,                                  -- references allowed_users.povio_id
    kind TEXT NOT NULL DEFAULT 'note',                    -- note | call | email | meeting | qbr | edit | escalation
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    summary TEXT NOT NULL,
    payload JSONB DEFAULT '{}'::jsonb,                    -- {before:{...}, after:{...}} for kind='edit'
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_activities_whale_time ON activities(whale_id, occurred_at DESC);

-- Todos — admin-only personal todo list (Vid's My Week)
CREATE TABLE IF NOT EXISTS todos (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,                                -- auth.uid()::text of admin who owns it
    title TEXT NOT NULL,
    tag TEXT,                                             -- outbound | new_sales | am | internal | ceo
    due_date DATE,
    is_recurring BOOLEAN DEFAULT false,
    recurrence_rule TEXT,
    done BOOLEAN DEFAULT false,
    source TEXT,                                          -- 'manual' | 'alert:stale_pipeline' | …
    whale_id INTEGER REFERENCES whales(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_todos_user ON todos(user_id, due_date);

-- Pipeline deals — new-sales pipeline
CREATE TABLE IF NOT EXISTS pipeline_deals (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    company_name TEXT NOT NULL,
    deal_name TEXT,
    value NUMERIC DEFAULT 0,                              -- in thousands, matching whales.arr convention
    stage TEXT DEFAULT 'lead' CHECK (stage IN ('lead','qualified','proposal','negotiation','closed_won','closed_lost')),
    owner_povio_id TEXT,
    source TEXT CHECK (source IN ('inbound','outbound','referral','partnership')),
    loss_reason TEXT,
    expected_close_date DATE,
    days_in_stage INTEGER DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    closed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_pipeline_user_stage ON pipeline_deals(user_id, stage);

-- Outbound metrics — per-week roll-up
CREATE TABLE IF NOT EXISTS outbound_metrics (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    week_start DATE NOT NULL,
    emails_sent INTEGER DEFAULT 0,
    responses INTEGER DEFAULT 0,
    calls_scheduled INTEGER DEFAULT 0,
    linkedin_sent INTEGER DEFAULT 0,
    linkedin_responses INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, week_start)
);

-- Weekly CEO reports
CREATE TABLE IF NOT EXISTS weekly_reports (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    week_start DATE NOT NULL,
    pipeline_summary JSONB DEFAULT '{}'::jsonb,
    account_summary JSONB DEFAULT '{}'::jsonb,
    team_highlights TEXT,
    risks TEXT,
    strategic_commentary TEXT,
    next_week_priorities TEXT,
    improvement_of_the_week TEXT,
    sent_via TEXT CHECK (sent_via IN ('email','slack','none')),
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, week_start)
);

-- QBR reviews — structured records of completed/upcoming QBRs
CREATE TABLE IF NOT EXISTS qbr_reviews (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    whale_id INTEGER REFERENCES whales(id) ON DELETE CASCADE,
    quarter TEXT NOT NULL,                                -- "Q1 2026"
    status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled','prep','in_progress','completed','skipped')),
    scheduled_date DATE,
    completed_date DATE,
    intro_notes TEXT,
    service_review TEXT,
    feedback_challenges TEXT,
    operational_updates TEXT,
    risk_assessment TEXT,
    commercial_review TEXT,
    price_increase_discussed BOOLEAN DEFAULT false,
    strategic_alignment TEXT,
    action_items JSONB DEFAULT '[]'::jsonb,
    follow_up_email_sent BOOLEAN DEFAULT false,
    next_review_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_qbr_whale ON qbr_reviews(whale_id);

-- Sales playbook — process steps per flow type
CREATE TABLE IF NOT EXISTS process_steps (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    flow_type TEXT NOT NULL CHECK (flow_type IN ('outbound','inbound','partnership')),
    step_number INTEGER NOT NULL,
    step_name TEXT NOT NULL,
    description TEXT,
    owner TEXT,
    tools_used TEXT,
    templates_linked TEXT,
    expected_duration TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tools inventory
CREATE TABLE IF NOT EXISTS tools_inventory (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    purpose TEXT,
    cost_monthly NUMERIC DEFAULT 0,
    used_by JSONB DEFAULT '[]'::jsonb,
    login_info TEXT,
    contract_renewal_date DATE,
    slack_channel TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Budget items
CREATE TABLE IF NOT EXISTS budget_items (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('salaries','tools','education','other')),
    description TEXT,
    amount_planned NUMERIC DEFAULT 0,
    amount_actual NUMERIC DEFAULT 0,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    year INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);


-- =============================================================================
-- 5. RLS — rewrite policies to support the role model
--    Whales + whale_notes + activities + calendar_events: any allowed user can
--      read; whales/whale_notes/activities also writable by any allowed user;
--      calendar_events writable by admin only.
--    Goals + team_data + all new admin tables: admin only.
-- =============================================================================

-- 5a. WHALES — drop old user_id-scoped policies, allow all allowed users
DROP POLICY IF EXISTS "Users can view their own whales"   ON whales;
DROP POLICY IF EXISTS "Users can insert their own whales" ON whales;
DROP POLICY IF EXISTS "Users can update their own whales" ON whales;
DROP POLICY IF EXISTS "Users can delete their own whales" ON whales;

CREATE POLICY "Allowed users can view whales"
    ON whales FOR SELECT
    USING (is_user_allowed());

CREATE POLICY "Allowed users can insert whales"
    ON whales FOR INSERT
    WITH CHECK (is_user_allowed());

CREATE POLICY "Allowed users can update whales"
    ON whales FOR UPDATE
    USING (is_user_allowed())
    WITH CHECK (is_user_allowed());

CREATE POLICY "Admin can delete whales"
    ON whales FOR DELETE
    USING (is_admin());

-- 5b. WHALE_NOTES — same collaborative pattern
DROP POLICY IF EXISTS "Users can view notes for their whales"   ON whale_notes;
DROP POLICY IF EXISTS "Users can insert notes for their whales" ON whale_notes;
DROP POLICY IF EXISTS "Users can update their own notes"        ON whale_notes;
DROP POLICY IF EXISTS "Users can delete their own notes"        ON whale_notes;

CREATE POLICY "Allowed users can view whale_notes"
    ON whale_notes FOR SELECT USING (is_user_allowed());
CREATE POLICY "Allowed users can insert whale_notes"
    ON whale_notes FOR INSERT WITH CHECK (is_user_allowed());
CREATE POLICY "Allowed users can update whale_notes"
    ON whale_notes FOR UPDATE USING (is_user_allowed()) WITH CHECK (is_user_allowed());
CREATE POLICY "Admin can delete whale_notes"
    ON whale_notes FOR DELETE USING (is_admin());

-- 5c. CALENDAR_EVENTS — read for any allowed user, write admin only
DROP POLICY IF EXISTS "Users can view their own events"   ON calendar_events;
DROP POLICY IF EXISTS "Users can insert their own events" ON calendar_events;
DROP POLICY IF EXISTS "Users can update their own events" ON calendar_events;
DROP POLICY IF EXISTS "Users can delete their own events" ON calendar_events;

CREATE POLICY "Allowed users can view calendar_events"
    ON calendar_events FOR SELECT USING (is_user_allowed());
CREATE POLICY "Admin can insert calendar_events"
    ON calendar_events FOR INSERT WITH CHECK (is_admin());
CREATE POLICY "Admin can update calendar_events"
    ON calendar_events FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY "Admin can delete calendar_events"
    ON calendar_events FOR DELETE USING (is_admin());

-- 5d. GOALS — admin only (tighten from existing user_id filter)
DROP POLICY IF EXISTS "Users can view their own goals"   ON goals;
DROP POLICY IF EXISTS "Users can insert their own goals" ON goals;
DROP POLICY IF EXISTS "Users can update their own goals" ON goals;
DROP POLICY IF EXISTS "Users can delete their own goals" ON goals;

CREATE POLICY "Admin manages goals"
    ON goals FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 5e. TEAM_DATA — admin only
DROP POLICY IF EXISTS "Users can view their own team"   ON team_data;
DROP POLICY IF EXISTS "Users can insert their own team" ON team_data;
DROP POLICY IF EXISTS "Users can update their own team" ON team_data;
DROP POLICY IF EXISTS "Users can delete their own team" ON team_data;

CREATE POLICY "Admin manages team_data"
    ON team_data FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 5f. ALLOWED_USERS — anyone authenticated can read (for avatar lookups, "who's in the org");
-- admin only can write (add / remove team members)
ALTER TABLE allowed_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allowed users can read directory" ON allowed_users;
DROP POLICY IF EXISTS "Admin manages allowed_users"      ON allowed_users;
CREATE POLICY "Allowed users can read directory"
    ON allowed_users FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admin manages allowed_users"
    ON allowed_users FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- 5g. ACTIVITIES — collaborative read+write by any allowed user; admin-only delete
ALTER TABLE activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allowed users can read activities"
    ON activities FOR SELECT USING (is_user_allowed());
CREATE POLICY "Allowed users can insert activities"
    ON activities FOR INSERT WITH CHECK (is_user_allowed());
CREATE POLICY "Admin can delete activities"
    ON activities FOR DELETE USING (is_admin());

-- 5h. New admin-only tables: todos / pipeline_deals / outbound_metrics / weekly_reports /
--     qbr_reviews / process_steps / tools_inventory / budget_items
DO $$ DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['todos','pipeline_deals','outbound_metrics','weekly_reports',
                             'qbr_reviews','process_steps','tools_inventory','budget_items']
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('DROP POLICY IF EXISTS "Admin manages %I" ON %I', t, t);
        EXECUTE format('CREATE POLICY "Admin manages %I" ON %I FOR ALL USING (is_admin()) WITH CHECK (is_admin())', t, t);
    END LOOP;
END $$;


-- =============================================================================
-- 6. Verification queries — run these after the migration to sanity-check
-- =============================================================================

-- Should return at least 11 rows (Vid + 9 AMs + Unassigned). Roles set correctly.
-- SELECT povio_id, name, role, email FROM allowed_users ORDER BY role DESC, povio_id;

-- Should return 'true' if you're logged in as Vid; 'false' if logged in as an AM.
-- SELECT is_admin();

-- Should return 'u_vl' if you're Vid; the AM's povio_id otherwise.
-- SELECT current_povio_id();

-- Whales: 16 new columns + 6 existing. Count should match.
-- SELECT count(*) FROM information_schema.columns WHERE table_name = 'whales';

-- New tables exist:
-- SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;

-- RLS enabled on all merged tables (rowsecurity = t for 13 rows):
-- SELECT tablename, rowsecurity FROM pg_tables
-- WHERE schemaname = 'public'
--   AND tablename IN ('whales','whale_notes','goals','team_data','calendar_events',
--                     'allowed_users','activities','todos','pipeline_deals',
--                     'outbound_metrics','weekly_reports','qbr_reviews',
--                     'process_steps','tools_inventory','budget_items');

-- =============================================================================
-- DONE. Next: bootstrap the 198 accounts via the in-app Admin → Import flow.
-- =============================================================================
