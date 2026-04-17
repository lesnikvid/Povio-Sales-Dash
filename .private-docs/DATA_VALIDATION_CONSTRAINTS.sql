-- ============================================================================
-- DATA VALIDATION CONSTRAINTS
-- Copy and paste this into Supabase SQL Editor
-- ============================================================================

-- Add length limits to prevent data bombs
ALTER TABLE goals
    ADD CONSTRAINT goals_title_length CHECK (length(title) <= 200),
    ADD CONSTRAINT goals_target_length CHECK (length(target) <= 500),
    ADD CONSTRAINT goals_category_length CHECK (length(category) <= 100),
    ADD CONSTRAINT goals_milestones_size CHECK (pg_column_size(milestones) <= 50000); -- ~50KB limit on JSON

ALTER TABLE whales
    ADD CONSTRAINT whales_name_length CHECK (length(name) <= 200),
    ADD CONSTRAINT whales_industry_length CHECK (length(industry) <= 100),
    ADD CONSTRAINT whales_notes_length CHECK (length(notes) <= 10000),
    ADD CONSTRAINT whales_contract_end_length CHECK (length(contract_end) <= 50),
    ADD CONSTRAINT whales_account_manager_length CHECK (length(account_manager) <= 100),
    ADD CONSTRAINT whales_last_qbr_length CHECK (length(last_qbr) <= 50),
    ADD CONSTRAINT whales_next_qbr_length CHECK (length(next_qbr) <= 50);

ALTER TABLE whale_notes
    ADD CONSTRAINT whale_notes_content_length CHECK (length(content) <= 10000),
    ADD CONSTRAINT whale_notes_created_by_length CHECK (length(created_by) <= 200);

-- Add enum constraints for categorical fields
ALTER TABLE whales
    ADD CONSTRAINT whales_health_valid CHECK (
        health IN ('healthy', 'warning', 'critical', 'Healthy', 'Warning', 'Critical')
    ),
    ADD CONSTRAINT whales_expansion_valid CHECK (
        expansion IN ('high', 'medium', 'low', 'none', 'High', 'Medium', 'Low', 'None', '') OR expansion IS NULL
    ),
    ADD CONSTRAINT whales_churn_risk_valid CHECK (
        churn_risk IN ('high', 'medium', 'low', 'none', 'High', 'Medium', 'Low', 'None', '') OR churn_risk IS NULL
    );

ALTER TABLE whale_notes
    ADD CONSTRAINT whale_notes_type_valid CHECK (
        note_type IN ('general', 'meeting', 'update', 'qbr', 'escalation', 'renewal', 'expansion')
    );

-- Add numeric constraints
ALTER TABLE whales
    ADD CONSTRAINT whales_arr_positive CHECK (arr >= 0),
    ADD CONSTRAINT whales_ltv_positive CHECK (ltv >= 0),
    ADD CONSTRAINT whales_arr_reasonable CHECK (arr <= 1000000), -- Max $1B ARR
    ADD CONSTRAINT whales_ltv_reasonable CHECK (ltv <= 10000000); -- Max $10B LTV

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check constraints were added
SELECT conname, contype, pg_get_constraintdef(oid) as definition
FROM pg_constraint
WHERE conrelid IN ('goals'::regclass, 'whales'::regclass, 'whale_notes'::regclass)
AND contype = 'c' -- CHECK constraints
ORDER BY conrelid::regclass::text, conname;

-- ============================================================================
-- DONE! Now the database will reject:
-- - Overly long text fields
-- - Invalid enum values
-- - Negative or unreasonable ARR/LTV values
-- - JSON bombs in milestones
-- ============================================================================
