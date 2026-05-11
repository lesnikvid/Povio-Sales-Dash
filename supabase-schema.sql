-- Povio Sales Dashboard Database Schema
-- Run this in Supabase SQL Editor (SQL Editor tab in left sidebar)

-- ============================================================================
-- TABLES
-- ============================================================================

-- Goals Table
CREATE TABLE IF NOT EXISTS goals (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    number TEXT NOT NULL,
    title TEXT NOT NULL,
    target TEXT NOT NULL,
    deadline TEXT,
    category TEXT,
    milestones JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Whales Table
CREATE TABLE IF NOT EXISTS whales (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    industry TEXT NOT NULL,
    health TEXT NOT NULL,
    arr NUMERIC NOT NULL, -- Annual Recurring Revenue in thousands (e.g., 500 = $500K)
    ltv NUMERIC NOT NULL, -- Lifetime Value in thousands (e.g., 2500 = $2.5M)
    contract_end TEXT,
    account_manager TEXT,
    last_qbr TEXT,
    next_qbr TEXT,
    expansion TEXT,
    churn_risk TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Whale Notes Table (for timestamped history)
CREATE TABLE IF NOT EXISTS whale_notes (
    id SERIAL PRIMARY KEY,
    whale_id INTEGER NOT NULL REFERENCES whales(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    note_type TEXT NOT NULL DEFAULT 'general', -- 'general', 'meeting', 'update', etc.
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by TEXT NOT NULL
);

-- Team Data Table (one row per user, full org structure stored as JSONB)
CREATE TABLE IF NOT EXISTS team_data (
    user_id TEXT PRIMARY KEY,
    structure JSONB NOT NULL DEFAULT '{"members":{},"root":null,"departments":[]}'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Calendar Events Table (team member vacations and work trips)
CREATE TABLE IF NOT EXISTS calendar_events (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    member_id TEXT NOT NULL,
    member_name TEXT NOT NULL,
    event_type TEXT NOT NULL DEFAULT 'vacation',
    title TEXT,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_goals_user_id ON goals(user_id);
CREATE INDEX IF NOT EXISTS idx_goals_user_created ON goals(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whales_user_id ON whales(user_id);
CREATE INDEX IF NOT EXISTS idx_whales_user_health ON whales(user_id, health);
CREATE INDEX IF NOT EXISTS idx_whale_notes_whale_id ON whale_notes(whale_id);
CREATE INDEX IF NOT EXISTS idx_whale_notes_user_id ON whale_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_whale_notes_whale_user ON whale_notes(whale_id, user_id);
CREATE INDEX IF NOT EXISTS idx_whale_notes_composite ON whale_notes(whale_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whale_notes_created_at ON whale_notes(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_id ON calendar_events(user_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_member_id ON calendar_events(member_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_dates ON calendar_events(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_dates ON calendar_events(user_id, start_date, end_date);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add triggers to auto-update updated_at timestamps
DROP TRIGGER IF EXISTS update_goals_updated_at ON goals;
CREATE TRIGGER update_goals_updated_at BEFORE UPDATE ON goals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_whales_updated_at ON whales;
CREATE TRIGGER update_whales_updated_at BEFORE UPDATE ON whales
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_team_data_updated_at ON team_data;
CREATE TRIGGER update_team_data_updated_at BEFORE UPDATE ON team_data
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_calendar_events_updated_at ON calendar_events;
CREATE TRIGGER update_calendar_events_updated_at BEFORE UPDATE ON calendar_events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable Row Level Security
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE whales ENABLE ROW LEVEL SECURITY;
ALTER TABLE whale_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- USER ALLOWLIST (only these emails can access the dashboard)
-- ============================================================================

CREATE TABLE IF NOT EXISTS allowed_users (
    email TEXT PRIMARY KEY,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    added_by TEXT,
    notes TEXT
);

-- Seed with owner email — EDIT THIS if running on a fresh DB
INSERT INTO allowed_users (email, notes) VALUES
    ('lesnik.vid@gmail.com', 'Owner (GitHub account)')
ON CONFLICT (email) DO NOTHING;

-- Helper function: returns true only if the authenticated user's email is in allowed_users
CREATE OR REPLACE FUNCTION is_user_allowed()
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM allowed_users
        WHERE email = (auth.jwt() ->> 'email')
    );
$$;

-- Goals Policies (user_id match + allowlist check)
DROP POLICY IF EXISTS "Users can view their own goals" ON goals;
CREATE POLICY "Users can view their own goals"
    ON goals FOR SELECT
    USING (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can insert their own goals" ON goals;
CREATE POLICY "Users can insert their own goals"
    ON goals FOR INSERT
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can update their own goals" ON goals;
CREATE POLICY "Users can update their own goals"
    ON goals FOR UPDATE
    USING (auth.uid()::text = user_id AND is_user_allowed())
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can delete their own goals" ON goals;
CREATE POLICY "Users can delete their own goals"
    ON goals FOR DELETE
    USING (auth.uid()::text = user_id AND is_user_allowed());

-- Whales Policies (user_id match + allowlist check)
DROP POLICY IF EXISTS "Users can view their own whales" ON whales;
CREATE POLICY "Users can view their own whales"
    ON whales FOR SELECT
    USING (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can insert their own whales" ON whales;
CREATE POLICY "Users can insert their own whales"
    ON whales FOR INSERT
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can update their own whales" ON whales;
CREATE POLICY "Users can update their own whales"
    ON whales FOR UPDATE
    USING (auth.uid()::text = user_id AND is_user_allowed())
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can delete their own whales" ON whales;
CREATE POLICY "Users can delete their own whales"
    ON whales FOR DELETE
    USING (auth.uid()::text = user_id AND is_user_allowed());

-- Whale Notes Policies (with UUID to TEXT casting)
DROP POLICY IF EXISTS "Users can view notes for their whales" ON whale_notes;
CREATE POLICY "Users can view notes for their whales"
    ON whale_notes FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM whales
            WHERE whales.id = whale_notes.whale_id
            AND whales.user_id = auth.uid()::text
        )
        AND is_user_allowed()
    );

DROP POLICY IF EXISTS "Users can insert notes for their whales" ON whale_notes;
CREATE POLICY "Users can insert notes for their whales"
    ON whale_notes FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM whales
            WHERE whales.id = whale_notes.whale_id
            AND whales.user_id = auth.uid()::text
        )
        AND auth.uid()::text = user_id
        AND is_user_allowed()
    );

DROP POLICY IF EXISTS "Users can update their own notes" ON whale_notes;
CREATE POLICY "Users can update their own notes"
    ON whale_notes FOR UPDATE
    USING (auth.uid()::text = user_id AND is_user_allowed())
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can delete their own notes" ON whale_notes;
CREATE POLICY "Users can delete their own notes"
    ON whale_notes FOR DELETE
    USING (auth.uid()::text = user_id AND is_user_allowed());

-- Team Data Policies (user_id match + allowlist check)
DROP POLICY IF EXISTS "Users can view their own team" ON team_data;
CREATE POLICY "Users can view their own team"
    ON team_data FOR SELECT
    USING (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can insert their own team" ON team_data;
CREATE POLICY "Users can insert their own team"
    ON team_data FOR INSERT
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can update their own team" ON team_data;
CREATE POLICY "Users can update their own team"
    ON team_data FOR UPDATE
    USING (auth.uid()::text = user_id AND is_user_allowed())
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can delete their own team" ON team_data;
CREATE POLICY "Users can delete their own team"
    ON team_data FOR DELETE
    USING (auth.uid()::text = user_id AND is_user_allowed());

-- Size constraint on structure JSON (prevent JSON bombs)
ALTER TABLE team_data
    DROP CONSTRAINT IF EXISTS team_data_structure_size;
ALTER TABLE team_data
    ADD CONSTRAINT team_data_structure_size CHECK (pg_column_size(structure) <= 200000);

-- Calendar Events Policies (user_id match + allowlist check)
DROP POLICY IF EXISTS "Users can view their own events" ON calendar_events;
CREATE POLICY "Users can view their own events"
    ON calendar_events FOR SELECT
    USING (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can insert their own events" ON calendar_events;
CREATE POLICY "Users can insert their own events"
    ON calendar_events FOR INSERT
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can update their own events" ON calendar_events;
CREATE POLICY "Users can update their own events"
    ON calendar_events FOR UPDATE
    USING (auth.uid()::text = user_id AND is_user_allowed())
    WITH CHECK (auth.uid()::text = user_id AND is_user_allowed());

DROP POLICY IF EXISTS "Users can delete their own events" ON calendar_events;
CREATE POLICY "Users can delete their own events"
    ON calendar_events FOR DELETE
    USING (auth.uid()::text = user_id AND is_user_allowed());

-- Calendar events constraints (prevent invalid data)
ALTER TABLE calendar_events
    DROP CONSTRAINT IF EXISTS calendar_events_type_valid;
ALTER TABLE calendar_events
    ADD CONSTRAINT calendar_events_type_valid CHECK (
        event_type IN ('vacation', 'work_trip')
    );

ALTER TABLE calendar_events
    DROP CONSTRAINT IF EXISTS calendar_events_dates_valid;
ALTER TABLE calendar_events
    ADD CONSTRAINT calendar_events_dates_valid CHECK (
        end_date >= start_date
    );

ALTER TABLE calendar_events
    DROP CONSTRAINT IF EXISTS calendar_events_title_length;
ALTER TABLE calendar_events
    ADD CONSTRAINT calendar_events_title_length CHECK (length(title) <= 200);

ALTER TABLE calendar_events
    DROP CONSTRAINT IF EXISTS calendar_events_notes_length;
ALTER TABLE calendar_events
    ADD CONSTRAINT calendar_events_notes_length CHECK (length(notes) <= 1000);

-- ============================================================================
-- VERIFICATION QUERIES (run these to confirm)
-- ============================================================================

-- Check RLS is enabled (should return 5 rows with rowsecurity = t)
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('goals', 'whales', 'whale_notes', 'team_data', 'calendar_events')
AND schemaname = 'public';

-- Check policies exist (should return 20 rows)
SELECT tablename, policyname
FROM pg_policies
WHERE tablename IN ('goals', 'whales', 'whale_notes', 'team_data', 'calendar_events')
ORDER BY tablename, policyname;

-- ============================================================================
-- DONE! Your database is now secured with Row Level Security.
-- ============================================================================
