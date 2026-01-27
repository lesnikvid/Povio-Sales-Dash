-- ============================================================================
-- QUICK FIX: Copy this entire file and run in Supabase SQL Editor
-- URL: https://supabase.com/dashboard/project/jiufnsnxuvhqwzozhlwm/sql
-- Time: 2 minutes
-- ============================================================================

-- Step 1: Enable Row Level Security (blocks all access by default)
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE whales ENABLE ROW LEVEL SECURITY;
ALTER TABLE whale_notes ENABLE ROW LEVEL SECURITY;

-- Step 2: Create RLS Policies (allow users to access only their own data)

-- Goals Policies
CREATE POLICY "Users can view their own goals" ON goals FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own goals" ON goals FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own goals" ON goals FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own goals" ON goals FOR DELETE USING (auth.uid() = user_id);

-- Whales Policies
CREATE POLICY "Users can view their own whales" ON whales FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own whales" ON whales FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own whales" ON whales FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own whales" ON whales FOR DELETE USING (auth.uid() = user_id);

-- Whale Notes Policies
CREATE POLICY "Users can view notes for their whales" ON whale_notes FOR SELECT USING (EXISTS (SELECT 1 FROM whales WHERE whales.id = whale_notes.whale_id AND whales.user_id = auth.uid()));
CREATE POLICY "Users can insert notes for their whales" ON whale_notes FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM whales WHERE whales.id = whale_notes.whale_id AND whales.user_id = auth.uid()) AND auth.uid() = user_id);
CREATE POLICY "Users can update their own notes" ON whale_notes FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own notes" ON whale_notes FOR DELETE USING (auth.uid() = user_id);

-- Step 3: Add Performance Indexes
CREATE INDEX IF NOT EXISTS idx_whale_notes_user_id ON whale_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_whale_notes_whale_user ON whale_notes(whale_id, user_id);
CREATE INDEX IF NOT EXISTS idx_whale_notes_composite ON whale_notes(whale_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_goals_user_created ON goals(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_whales_user_health ON whales(user_id, health);

-- ============================================================================
-- Verification Queries (run these separately to check everything worked)
-- ============================================================================

-- Check RLS is enabled (should return 3 rows with rowsecurity = t)
SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN ('goals', 'whales', 'whale_notes') AND schemaname = 'public';

-- Check policies exist (should return 12 rows)
SELECT tablename, policyname FROM pg_policies WHERE tablename IN ('goals', 'whales', 'whale_notes') ORDER BY tablename;

-- ============================================================================
-- DONE! Expected result: "Success. No rows returned"
-- Next: Rotate your service_role key in Supabase Dashboard → Settings → API
-- ============================================================================
