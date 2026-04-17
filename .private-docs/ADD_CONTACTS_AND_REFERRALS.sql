-- =============================================
-- ADD CONTACTS AND REFERRAL TRACKING TO WHALES
-- =============================================
-- Run this in Supabase SQL Editor
-- =============================================

-- Add contacts column (JSON array to store multiple contacts)
ALTER TABLE whales
ADD COLUMN IF NOT EXISTS contacts JSONB DEFAULT '[]'::jsonb;

-- Add referral tracking columns
ALTER TABLE whales
ADD COLUMN IF NOT EXISTS referrals_count INTEGER DEFAULT 0;

ALTER TABLE whales
ADD COLUMN IF NOT EXISTS referrals_revenue NUMERIC DEFAULT 0;

-- Add comments for documentation
COMMENT ON COLUMN whales.contacts IS 'Array of contact objects: [{name, role, email, phone, is_decision_maker}]';
COMMENT ON COLUMN whales.referrals_count IS 'Number of referrals this whale has provided';
COMMENT ON COLUMN whales.referrals_revenue IS 'Total revenue generated from referrals (in dollars)';

-- Verify the changes
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'whales'
AND column_name IN ('contacts', 'referrals_count', 'referrals_revenue');
