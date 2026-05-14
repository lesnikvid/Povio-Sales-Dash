-- =============================================================================
-- Migration 016: Recurring tasks
-- =============================================================================
-- Adds a `recurrence` column on todos so a task can repeat. Pattern:
-- spawn-on-complete — when a recurring task is checked off, the client
-- inserts a new instance with due_date advanced by the recurrence interval.
-- The completed task stays in Done; the new one appears in the appropriate
-- date bucket.
--
-- Values: NULL (no repeat), 'daily', 'weekly', 'biweekly', 'monthly'.
-- =============================================================================

ALTER TABLE todos
    ADD COLUMN IF NOT EXISTS recurrence TEXT;

ALTER TABLE todos
    DROP CONSTRAINT IF EXISTS todos_recurrence_check;
ALTER TABLE todos
    ADD CONSTRAINT todos_recurrence_check
    CHECK (recurrence IS NULL OR recurrence IN ('daily', 'weekly', 'biweekly', 'monthly'));

-- Verification:
-- SELECT count(*) FROM todos WHERE recurrence IS NOT NULL;  -- 0 today
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name='todos' AND column_name='recurrence';
