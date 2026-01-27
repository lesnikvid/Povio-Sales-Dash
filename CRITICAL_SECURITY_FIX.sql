-- ============================================================================
-- CRITICAL SECURITY FIX: Row Level Security (RLS) Policies
-- ============================================================================
-- ⚠️  RUN THIS IMMEDIATELY IN SUPABASE SQL EDITOR
-- ⚠️  Your database is currently COMPLETELY OPEN to all users
-- ⚠️  Any user can read/modify/delete ANY data from ANY user
-- ============================================================================

-- Step 1: Enable Row Level Security on all tables
-- This BLOCKS all access by default until policies are defined

ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE whales ENABLE ROW LEVEL SECURITY;
ALTER TABLE whale_notes ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Step 2: Create RLS Policies for GOALS table
-- Users can only access their own goals
-- ============================================================================

-- SELECT: Users can view their own goals
CREATE POLICY "Users can view their own goals"
    ON goals FOR SELECT
    USING (auth.uid() = user_id);

-- INSERT: Users can only create goals with their own user_id
CREATE POLICY "Users can insert their own goals"
    ON goals FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- UPDATE: Users can only update their own goals
CREATE POLICY "Users can update their own goals"
    ON goals FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- DELETE: Users can only delete their own goals
CREATE POLICY "Users can delete their own goals"
    ON goals FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- Step 3: Create RLS Policies for WHALES table
-- Users can only access their own whale accounts
-- ============================================================================

-- SELECT: Users can view their own whales
CREATE POLICY "Users can view their own whales"
    ON whales FOR SELECT
    USING (auth.uid() = user_id);

-- INSERT: Users can only create whales with their own user_id
CREATE POLICY "Users can insert their own whales"
    ON whales FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- UPDATE: Users can only update their own whales
CREATE POLICY "Users can update their own whales"
    ON whales FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- DELETE: Users can only delete their own whales
CREATE POLICY "Users can delete their own whales"
    ON whales FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- Step 4: Create RLS Policies for WHALE_NOTES table
-- Users can only access notes for whales they own
-- ============================================================================

-- SELECT: Users can view notes for their own whales
CREATE POLICY "Users can view notes for their whales"
    ON whale_notes FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM whales
            WHERE whales.id = whale_notes.whale_id
            AND whales.user_id = auth.uid()
        )
    );

-- INSERT: Users can only create notes for their own whales
CREATE POLICY "Users can insert notes for their whales"
    ON whale_notes FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM whales
            WHERE whales.id = whale_notes.whale_id
            AND whales.user_id = auth.uid()
        )
        AND auth.uid() = user_id
    );

-- UPDATE: Users can only update their own notes
CREATE POLICY "Users can update their own notes"
    ON whale_notes FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- DELETE: Users can only delete their own notes
CREATE POLICY "Users can delete their own notes"
    ON whale_notes FOR DELETE
    USING (auth.uid() = user_id);

-- ============================================================================
-- Step 5: Add missing database indexes for performance
-- ============================================================================

-- Index for whale_notes by user_id
CREATE INDEX IF NOT EXISTS idx_whale_notes_user_id ON whale_notes(user_id);

-- Composite index for efficient whale-user queries
CREATE INDEX IF NOT EXISTS idx_whale_notes_whale_user ON whale_notes(whale_id, user_id);

-- Composite index for whale_notes ordering
CREATE INDEX IF NOT EXISTS idx_whale_notes_composite ON whale_notes(whale_id, created_at DESC);

-- Optimize user-based goal queries
CREATE INDEX IF NOT EXISTS idx_goals_user_created ON goals(user_id, created_at DESC);

-- Optimize whale queries by user and health
CREATE INDEX IF NOT EXISTS idx_whales_user_health ON whales(user_id, health);

-- ============================================================================
-- Step 6: Verify RLS is enabled
-- ============================================================================

-- Check RLS status (should return 't' for all tables)
SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_tables
WHERE tablename IN ('goals', 'whales', 'whale_notes')
AND schemaname = 'public';

-- Check RLS policies exist (should return multiple rows)
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd
FROM pg_policies
WHERE tablename IN ('goals', 'whales', 'whale_notes')
ORDER BY tablename, cmd;

-- ============================================================================
-- NEXT STEPS AFTER RUNNING THIS SQL:
-- ============================================================================
-- 1. ✅ Verify RLS is enabled (queries above)
-- 2. ✅ Test that you can still access your own data
-- 3. ✅ Rotate your Supabase service_role key (Settings → API)
-- 4. ✅ Configure Auth0 JWT in Supabase (Authentication → Providers)
-- 5. ✅ Update your app to pass JWT tokens to Supabase
--
-- See SECURITY_AUDIT_REPORT.md for detailed next steps
-- ============================================================================
