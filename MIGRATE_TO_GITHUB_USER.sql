-- =============================================
-- MIGRATE DATA TO GITHUB USER
-- =============================================
-- Your new GitHub user ID: 993c7b2c-dcec-4de1-babf-cdeb39203861
-- Run these queries in Supabase SQL Editor one at a time
-- =============================================

-- STEP 1: Check what user IDs currently exist in your database
-- This will show you all the different user_ids and how many records each has

SELECT 'goals' as table_name, user_id, COUNT(*) as record_count
FROM goals
GROUP BY user_id
UNION ALL
SELECT 'whales' as table_name, user_id, COUNT(*) as record_count
FROM whales
GROUP BY user_id
UNION ALL
SELECT 'whale_notes' as table_name, user_id, COUNT(*) as record_count
FROM whale_notes
GROUP BY user_id
ORDER BY table_name, record_count DESC;

-- =============================================
-- STEP 2: After reviewing Step 1 results, update the OLD_USER_ID below
-- Replace 'OLD_USER_ID_HERE' with the actual old user_id from Step 1
-- Then run these UPDATE statements:
-- =============================================

-- BEFORE RUNNING: Replace 'OLD_USER_ID_HERE' with your old Auth0 user_id
-- It will look something like: auth0|65a1b2c3d4e5f6g7h8i9j0k1

-- Migrate goals to GitHub user
UPDATE goals
SET user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
WHERE user_id = 'OLD_USER_ID_HERE';

-- Migrate whales to GitHub user
UPDATE whales
SET user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
WHERE user_id = 'OLD_USER_ID_HERE';

-- Migrate whale_notes to GitHub user
UPDATE whale_notes
SET user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
WHERE user_id = 'OLD_USER_ID_HERE';

-- =============================================
-- STEP 3: Clean up duplicate goals
-- This will keep the oldest version of each goal and delete duplicates
-- =============================================

-- First, let's see which goals are duplicated
SELECT title, COUNT(*) as duplicate_count
FROM goals
WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
GROUP BY title
HAVING COUNT(*) > 1;

-- Delete duplicate goals (keeps the first one by ID)
DELETE FROM goals
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY title, user_id ORDER BY id ASC) as rn
        FROM goals
        WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
    ) t
    WHERE rn > 1
);

-- =============================================
-- STEP 4: Verify the migration
-- Check that everything looks correct
-- =============================================

-- Count records for your GitHub user
SELECT
    (SELECT COUNT(*) FROM goals WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861') as goals_count,
    (SELECT COUNT(*) FROM whales WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861') as whales_count,
    (SELECT COUNT(*) FROM whale_notes WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861') as notes_count;

-- View your goals
SELECT id, number, title, category, deadline
FROM goals
WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
ORDER BY id;

-- View your whales
SELECT id, name, industry, health, arr, ltv
FROM whales
WHERE user_id = '993c7b2c-dcec-4de1-babf-cdeb39203861'
ORDER BY id;
