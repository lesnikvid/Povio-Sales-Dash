-- ============================================================================
-- TEAM DATA TABLE SETUP
-- Copy and paste this into Supabase SQL Editor
-- Adds editable team/org-chart storage for the dashboard
-- ============================================================================

-- Step 1: Create team_data table (one row per user, full org structure as JSONB)
CREATE TABLE IF NOT EXISTS team_data (
    user_id TEXT PRIMARY KEY,
    structure JSONB NOT NULL DEFAULT '{"members":{},"root":null,"departments":[]}'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 2: Enable RLS
ALTER TABLE team_data ENABLE ROW LEVEL SECURITY;

-- Step 3: Policies (allowlist-gated, same pattern as goals/whales)
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

-- Step 4: Auto-update updated_at trigger
DROP TRIGGER IF EXISTS update_team_data_updated_at ON team_data;
CREATE TRIGGER update_team_data_updated_at BEFORE UPDATE ON team_data
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Step 5: Size constraint (prevent JSON bombs, ~200KB cap)
ALTER TABLE team_data
    DROP CONSTRAINT IF EXISTS team_data_structure_size;
ALTER TABLE team_data
    ADD CONSTRAINT team_data_structure_size CHECK (pg_column_size(structure) <= 200000);

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check table exists and RLS is on
SELECT tablename, rowsecurity FROM pg_tables
WHERE tablename = 'team_data' AND schemaname = 'public';

-- Check policies (should return 4 rows)
SELECT tablename, policyname FROM pg_policies
WHERE tablename = 'team_data'
ORDER BY policyname;

-- ============================================================================
-- DONE! Team data is now stored per-user with RLS + allowlist enforcement.
-- ============================================================================
