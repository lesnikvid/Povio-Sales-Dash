-- ============================================================================
-- CALENDAR EVENTS TABLE SETUP
-- Copy and paste this into Supabase SQL Editor
-- Tracks team member vacations and work trips
-- ============================================================================

-- Step 1: Create calendar_events table
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

-- Step 2: Indexes for performance
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_id ON calendar_events(user_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_member_id ON calendar_events(member_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_dates ON calendar_events(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_dates ON calendar_events(user_id, start_date, end_date);

-- Step 3: Constraints
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

-- Step 4: Trigger for auto-updating updated_at
DROP TRIGGER IF EXISTS update_calendar_events_updated_at ON calendar_events;
CREATE TRIGGER update_calendar_events_updated_at BEFORE UPDATE ON calendar_events
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Step 5: Enable RLS
ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

-- Step 6: Policies (allowlist-gated, same pattern as goals/whales)
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

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check table exists and RLS is on
SELECT tablename, rowsecurity FROM pg_tables
WHERE tablename = 'calendar_events' AND schemaname = 'public';

-- Check policies (should return 4 rows)
SELECT tablename, policyname FROM pg_policies
WHERE tablename = 'calendar_events'
ORDER BY policyname;

-- ============================================================================
-- DONE! Calendar events can now be tracked per-user with RLS.
-- ============================================================================
