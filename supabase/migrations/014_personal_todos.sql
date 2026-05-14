-- =============================================================================
-- Migration 014: Open `todos` to per-user access (each user manages their own)
-- =============================================================================
-- Migration 002 created `todos` as admin-only. Now we want every authenticated
-- user (Vid + 6 AMs) to have their own personal task list. Same table, RLS
-- scoped per-user via auth.uid().
--
-- Also adds a `tag` column for simple single-tag UI (the original schema had
-- tags text[] which is overkill for the simple-but-efficient list Vid asked
-- for; keeping tags[] for future multi-tag and adding singular tag for the
-- current UI to read/write).
--
-- Idempotent.
-- =============================================================================


-- 1. New per-user RLS policy (replaces the admin-only one from migration 002)
DROP POLICY IF EXISTS "Admin manages todos" ON todos;
DROP POLICY IF EXISTS "Users manage their own todos" ON todos;
CREATE POLICY "Users manage their own todos"
    ON todos FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());


-- 2. Simple single-tag column for the UI (alongside the existing tags array)
ALTER TABLE todos ADD COLUMN IF NOT EXISTS tag TEXT;


-- 3. Small data hygiene — make sure existing rows have user_id set.
-- (None should be orphaned; this is a no-op if everything is well-formed.)
-- Leave as commented for safety; uncomment only if a stale row blocks RLS.
-- DELETE FROM todos WHERE user_id IS NULL;


-- =============================================================================
-- Verification:
-- SELECT count(*) FROM todos;                        -- existing rows still there
-- SELECT policyname FROM pg_policies WHERE tablename = 'todos';
--    -- should show only "Users manage their own todos"
-- =============================================================================
