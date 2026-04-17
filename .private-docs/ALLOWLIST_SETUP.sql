-- ============================================================================
-- USER ALLOWLIST SETUP
-- Copy and paste this into Supabase SQL Editor
-- ============================================================================

-- Step 1: Create allowlist table
CREATE TABLE IF NOT EXISTS allowed_users (
    email TEXT PRIMARY KEY,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    added_by TEXT,
    notes TEXT
);

-- Step 2: Add YOUR email(s) - EDIT THIS LIST if adding more users
-- Email must match the GitHub account's primary email
INSERT INTO allowed_users (email, notes) VALUES
    ('lesnik.vid@gmail.com', 'Owner (GitHub account)')
ON CONFLICT (email) DO NOTHING;

-- Step 3: Create helper function to check if user is allowed
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

-- Step 4: Update ALL RLS policies to add allowlist check
-- This adds "AND is_user_allowed()" to every policy

-- Goals policies
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

-- Whales policies
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

-- Whale Notes policies
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

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check allowlist table
SELECT * FROM allowed_users;

-- Check policies were updated (should return 12 rows)
SELECT tablename, policyname
FROM pg_policies
WHERE tablename IN ('goals', 'whales', 'whale_notes')
ORDER BY tablename, policyname;

-- ============================================================================
-- DONE! Now only users in allowed_users table can access the dashboard.
-- Random GitHub signups will be blocked at the database level.
-- ============================================================================

-- To add more users later, just:
-- INSERT INTO allowed_users (email, notes) VALUES ('new-user@povio.com', 'Team member');
