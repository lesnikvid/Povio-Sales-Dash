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

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable Row Level Security
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE whales ENABLE ROW LEVEL SECURITY;
ALTER TABLE whale_notes ENABLE ROW LEVEL SECURITY;

-- Goals Policies (with UUID to TEXT casting)
DROP POLICY IF EXISTS "Users can view their own goals" ON goals;
CREATE POLICY "Users can view their own goals"
    ON goals FOR SELECT
    USING (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can insert their own goals" ON goals;
CREATE POLICY "Users can insert their own goals"
    ON goals FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can update their own goals" ON goals;
CREATE POLICY "Users can update their own goals"
    ON goals FOR UPDATE
    USING (auth.uid()::text = user_id)
    WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can delete their own goals" ON goals;
CREATE POLICY "Users can delete their own goals"
    ON goals FOR DELETE
    USING (auth.uid()::text = user_id);

-- Whales Policies (with UUID to TEXT casting)
DROP POLICY IF EXISTS "Users can view their own whales" ON whales;
CREATE POLICY "Users can view their own whales"
    ON whales FOR SELECT
    USING (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can insert their own whales" ON whales;
CREATE POLICY "Users can insert their own whales"
    ON whales FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can update their own whales" ON whales;
CREATE POLICY "Users can update their own whales"
    ON whales FOR UPDATE
    USING (auth.uid()::text = user_id)
    WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can delete their own whales" ON whales;
CREATE POLICY "Users can delete their own whales"
    ON whales FOR DELETE
    USING (auth.uid()::text = user_id);

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
    );

DROP POLICY IF EXISTS "Users can update their own notes" ON whale_notes;
CREATE POLICY "Users can update their own notes"
    ON whale_notes FOR UPDATE
    USING (auth.uid()::text = user_id)
    WITH CHECK (auth.uid()::text = user_id);

DROP POLICY IF EXISTS "Users can delete their own notes" ON whale_notes;
CREATE POLICY "Users can delete their own notes"
    ON whale_notes FOR DELETE
    USING (auth.uid()::text = user_id);

-- ============================================================================
-- VERIFICATION QUERIES (run these to confirm)
-- ============================================================================

-- Check RLS is enabled (should return 3 rows with rowsecurity = t)
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('goals', 'whales', 'whale_notes')
AND schemaname = 'public';

-- Check policies exist (should return 12 rows)
SELECT tablename, policyname
FROM pg_policies
WHERE tablename IN ('goals', 'whales', 'whale_notes')
ORDER BY tablename, policyname;

-- ============================================================================
-- DONE! Your database is now secured with Row Level Security.
-- ============================================================================
