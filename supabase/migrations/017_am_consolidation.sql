-- =============================================================================
-- Migration 017: Consolidate "Owner" + "Account Manager" + open AM permissions
-- =============================================================================
-- Until now, two columns on `whales` represented the same person:
--   * owner_povio_id   — TEXT, references allowed_users.povio_id (canonical)
--   * account_manager  — TEXT, free-text name; populated during the AM-board
--                        import as the *name* of owner_povio_id's record.
-- Nothing kept them in sync. The UI showed both as separately editable, so a
-- typo on the free-text side could silently desync them. Pure cruft.
--
-- This migration drops account_manager (the FK + allowed_users join is now the
-- single source of truth) and relaxes the audit trigger so AMs can reassign
-- ownership and toggle the key-account flag — both previously admin-only.
-- The audit trail still records who made each change.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Diagnostic: report any row where account_manager free-text disagrees
--    with the owner-derived name. We proceed regardless per Vid's call —
--    this is just informational so any drift is visible before drop.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    drift_count INT;
    drift_sample TEXT;
BEGIN
    SELECT count(*),
           string_agg(format('whale=%s am=%L owner=%L',
                             w.id, w.account_manager, u.name),
                      '; ' ORDER BY w.id)
      INTO drift_count, drift_sample
      FROM whales w
      LEFT JOIN allowed_users u ON u.povio_id = w.owner_povio_id
      WHERE w.account_manager IS NOT NULL
        AND trim(w.account_manager) <> ''
        AND COALESCE(u.name, '') <> COALESCE(w.account_manager, '');
    IF drift_count > 0 THEN
        RAISE NOTICE 'account_manager drift on % rows. Sample: %',
                     drift_count, left(drift_sample, 400);
    ELSE
        RAISE NOTICE 'account_manager fully redundant — safe drop.';
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. Drop the redundant column. owner_povio_id + allowed_users is now the
--    single source of truth for "who is the AM on this account".
-- -----------------------------------------------------------------------------
ALTER TABLE whales DROP COLUMN IF EXISTS account_manager;

-- -----------------------------------------------------------------------------
-- 3. Relax the audit trigger. The previous version of
--    enforce_whale_audit_stamp (migration 004) blocked non-admins from
--    changing owner_povio_id or is_key_account by silently reverting them
--    to the OLD value. Vid has explicitly asked for collaborative AM-driven
--    self-management: any AM can reassign accounts and toggle key status.
--
--    The trigger still stamps updated_by_povio_id + updated_at, so the
--    audit trail records exactly who made each change. The companion
--    log_whale_edit trigger (also from migration 004) will pick up the
--    owner_povio_id / is_key_account diff just like any other watched
--    column and insert an activities row with kind='edit'.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enforce_whale_audit_stamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_by_povio_id := current_povio_id();
    NEW.updated_at := now();
    -- (Removed 2026-05-18: previous IF NOT is_admin() block that silently
    --  reverted owner_povio_id and is_key_account changes from reps. AMs
    --  now self-manage assignments and key-account designation; the audit
    --  trail records who changed what.)
    RETURN NEW;
END
$$;

-- -----------------------------------------------------------------------------
-- 4. Verification queries (run manually after the migration lands):
--
--   -- Confirm column gone:
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='whales' AND column_name='account_manager';   -- 0 rows
--
--   -- Confirm trigger body is the relaxed version:
--   SELECT pg_get_functiondef('enforce_whale_audit_stamp'::regproc);
--
--   -- Spot check that updated_by + updated_at are still being stamped:
--   SELECT id, name, owner_povio_id, updated_by_povio_id, updated_at
--     FROM whales ORDER BY updated_at DESC LIMIT 5;
-- -----------------------------------------------------------------------------
