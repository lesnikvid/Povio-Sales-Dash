-- =============================================================================
-- Migration 015: Ensure todos.completed_at column exists + backfill done rows
-- =============================================================================
-- Migration 002's CREATE TABLE for `todos` did not include a completed_at
-- column. The React code has been calling .update({ completed_at: ... })
-- which silently fails. As a result, every done task has completed_at
-- null and the "✓ done <when>" chip never renders.
--
-- Fix:
--   1. Add the column (idempotent — IF NOT EXISTS).
--   2. Backfill it for already-done tasks: best guess is created_at.
--      (We have no record of WHEN they were actually checked off, so
--      created_at is the only sensible fallback for historical rows.)
--
-- New checkoffs from the React UI will set completed_at correctly now
-- that the column exists.
-- =============================================================================

ALTER TABLE todos ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE todos
SET completed_at = created_at
WHERE done = true AND completed_at IS NULL;

-- Verification:
-- SELECT count(*) FROM todos WHERE done = true AND completed_at IS NULL;
--   -- should return 0 after this migration
