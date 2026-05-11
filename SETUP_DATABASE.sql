-- ============================================================================
-- SUPABASE DATABASE SETUP FOR WHALE PROTECTION PROGRAM
-- ============================================================================
-- Run this in Supabase SQL Editor:
-- https://supabase.com/dashboard/project/jiufnsnxuvhqwzozhlwm/sql
-- ============================================================================

-- Step 1: Create whale_notes table for timestamped note history
-- This enables the "Add Note" and "View History" features

CREATE TABLE IF NOT EXISTS whale_notes (
    id SERIAL PRIMARY KEY,
    whale_id INTEGER NOT NULL REFERENCES whales(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    note_type TEXT NOT NULL DEFAULT 'general',
    content TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by TEXT NOT NULL
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_whale_notes_whale_id ON whale_notes(whale_id);
CREATE INDEX IF NOT EXISTS idx_whale_notes_created_at ON whale_notes(created_at DESC);

-- ============================================================================
-- Step 2: Migrate ARR and LTV from TEXT to NUMERIC format
-- This fixes the double dollar sign issue ($$380KK becomes $380K)
-- ONLY run this if your whales table currently has TEXT values like "$500K"
-- ============================================================================

-- Check current data type (should show 'text' before migration)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'whales' AND column_name IN ('arr', 'ltv');

-- Migrate ARR to NUMERIC
ALTER TABLE whales ALTER COLUMN arr TYPE NUMERIC USING (
    CASE
        WHEN arr::text ~ '\$[0-9.]+M' THEN CAST(REPLACE(REPLACE(arr::text, '$', ''), 'M', '') AS NUMERIC) * 1000
        WHEN arr::text ~ '\$[0-9.]+K' THEN CAST(REPLACE(REPLACE(arr::text, '$', ''), 'K', '') AS NUMERIC)
        WHEN arr::text ~ '^\$' THEN CAST(REPLACE(arr::text, '$', '') AS NUMERIC)
        ELSE CAST(arr AS NUMERIC)
    END
);

-- Migrate LTV to NUMERIC
ALTER TABLE whales ALTER COLUMN ltv TYPE NUMERIC USING (
    CASE
        WHEN ltv::text ~ '\$[0-9.]+M' THEN CAST(REPLACE(REPLACE(ltv::text, '$', ''), 'M', '') AS NUMERIC) * 1000
        WHEN ltv::text ~ '\$[0-9.]+K' THEN CAST(REPLACE(REPLACE(ltv::text, '$', ''), 'K', '') AS NUMERIC)
        WHEN ltv::text ~ '^\$' THEN CAST(REPLACE(ltv::text, '$', '') AS NUMERIC)
        ELSE CAST(ltv AS NUMERIC)
    END
);

-- Verify migration (should show 'numeric' after migration)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'whales' AND column_name IN ('arr', 'ltv');

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check if whale_notes table exists
SELECT EXISTS (
    SELECT FROM information_schema.tables
    WHERE table_name = 'whale_notes'
);

-- Check whale_notes table structure
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'whale_notes'
ORDER BY ordinal_position;

-- View sample whale data to verify ARR/LTV are numeric
SELECT id, name, arr, ltv, pg_typeof(arr) as arr_type, pg_typeof(ltv) as ltv_type
FROM whales
LIMIT 3;

-- ============================================================================
-- DONE! Your database is now set up for the Whale Protection Program
-- Refresh your app and try adding notes - they should work now!
-- ============================================================================
