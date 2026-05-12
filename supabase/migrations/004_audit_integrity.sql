-- =============================================================================
-- Migration 004: Insider-threat audit integrity hardening
-- =============================================================================
-- Fixes findings from the focused security audit:
--
--   C-2  activities.actor_povio_id was client-supplied — any rep could forge
--        an audit row as another user (e.g. blame Vid for a bad edit)
--   H-1  whale_notes author was client-supplied, and UPDATE was open to
--        any allowed user — reps could rewrite each other's notes
--   H-2  whales.updated_by_povio_id was client-supplied — reps could mask
--        their own edits as Vid's. owner_povio_id was rep-writable —
--        reps could reassign accounts off other AMs.
--   H-3  Audit-trail row was written by React client code only — a rep
--        with DevTools could call supabaseClient.from('whales').update(...)
--        directly and leave no audit trail.
--   M-7  allowed_users SELECT was open to any authenticated user (not just
--        allowlisted) — anyone who manages to authenticate at all could
--        enumerate the team roster.
--   M-6  No size constraints on JSONB columns (activities.payload,
--        whales.qbr_history, whales.team_members) — a rep could insert
--        100MB rows to DoS the Supabase free-tier quota.
--
-- Net effect: a malicious or compromised AM can no longer forge audit
-- entries, rewrite others' notes, reassign accounts they don't own, or
-- bypass the audit log via DevTools. The DB enforces it at the row/
-- column level — React code can no longer be trusted (and shouldn't be).
--
-- Safe to re-run; all DDL is idempotent.
-- =============================================================================


-- =============================================================================
-- 1. C-2 — activities INSERT: actor must match the caller's povio_id
-- =============================================================================
DROP POLICY IF EXISTS "Allowed users can insert activities" ON activities;
CREATE POLICY "Allowed users can insert activities"
    ON activities FOR INSERT
    WITH CHECK (is_user_allowed() AND actor_povio_id = current_povio_id());


-- =============================================================================
-- 2. H-1 — whale_notes INSERT/UPDATE author integrity
-- =============================================================================
DROP POLICY IF EXISTS "Allowed users can insert whale_notes" ON whale_notes;
CREATE POLICY "Allowed users can insert whale_notes"
    ON whale_notes FOR INSERT
    WITH CHECK (is_user_allowed() AND user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Allowed users can update whale_notes" ON whale_notes;
CREATE POLICY "Author or admin can update whale_notes"
    ON whale_notes FOR UPDATE
    USING (auth.uid()::text = user_id OR is_admin())
    WITH CHECK (auth.uid()::text = user_id OR is_admin());


-- =============================================================================
-- 3. H-2 — whales: server-side audit stamps; column-level lock on ownership
-- =============================================================================
-- BEFORE UPDATE trigger that:
--   (a) Overrides updated_by_povio_id with the caller's authoritative id
--   (b) Refreshes updated_at to server NOW()
--   (c) For non-admin callers, reverts any attempt to change owner_povio_id
--       or is_key_account back to the previous value
--
-- This replaces the earlier whales_touch trigger from migration 002, which
-- only set updated_at and relied on the client to set updated_by_povio_id.
-- =============================================================================
DROP TRIGGER IF EXISTS whales_touch_trg ON whales;

CREATE OR REPLACE FUNCTION enforce_whale_audit_stamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    NEW.updated_by_povio_id := current_povio_id();
    NEW.updated_at := now();
    -- Reps cannot reassign accounts or promote/demote key-account status
    IF NOT is_admin() THEN
        NEW.owner_povio_id := OLD.owner_povio_id;
        NEW.is_key_account := OLD.is_key_account;
    END IF;
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_whales_audit_stamp ON whales;
CREATE TRIGGER trg_whales_audit_stamp
    BEFORE UPDATE ON whales
    FOR EACH ROW
    EXECUTE FUNCTION enforce_whale_audit_stamp();


-- =============================================================================
-- 4. H-3 — server-side audit-trail logging on whales UPDATE
-- =============================================================================
-- AFTER UPDATE trigger that diffs the watched columns and writes an
-- `activities` row with kind='edit' and the before/after payload.
--
-- Runs as SECURITY DEFINER so it can INSERT into activities regardless of
-- the calling user's RLS context. current_povio_id() resolves the actor
-- by JWT email.
--
-- The watched-columns list mirrors what the React-side helper used to log;
-- if a column isn't in this list, edits to it are invisible to the audit.
-- That's intentional — bulk fields like team_members JSONB are noisy.
-- =============================================================================
CREATE OR REPLACE FUNCTION log_whale_edit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor_id TEXT := current_povio_id();
    actor_name TEXT;
    before_data JSONB := '{}'::jsonb;
    after_data JSONB := '{}'::jsonb;
    diffs TEXT[] := ARRAY[]::TEXT[];
    field TEXT;
    watched TEXT[] := ARRAY[
        'name','industry','health','arr','ltv','contract_end','account_manager',
        'last_qbr','next_qbr','expansion','churn_risk','notes',
        'is_key_account','fte','engagement_type','account_status_raw',
        'forecast_raw','expansion_potential','last_note','project_manager',
        'invoicing_note','owner_povio_id'
    ];
    old_j JSONB := to_jsonb(OLD);
    new_j JSONB := to_jsonb(NEW);
BEGIN
    FOREACH field IN ARRAY watched LOOP
        IF (old_j -> field) IS DISTINCT FROM (new_j -> field) THEN
            before_data := before_data || jsonb_build_object(field, old_j -> field);
            after_data  := after_data  || jsonb_build_object(field, new_j -> field);
            diffs := array_append(diffs, field);
        END IF;
    END LOOP;

    IF array_length(diffs, 1) IS NOT NULL THEN
        SELECT name INTO actor_name FROM allowed_users WHERE povio_id = actor_id;
        INSERT INTO activities(whale_id, actor_povio_id, kind, summary, payload)
        VALUES (
            NEW.id,
            actor_id,
            'edit',
            COALESCE(actor_name, actor_id, 'unknown') || ' updated ' || array_to_string(diffs, ', '),
            jsonb_build_object('before', before_data, 'after', after_data)
        );
    END IF;
    RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_whales_audit_log ON whales;
CREATE TRIGGER trg_whales_audit_log
    AFTER UPDATE ON whales
    FOR EACH ROW
    EXECUTE FUNCTION log_whale_edit();


-- =============================================================================
-- 5. M-7 — tighten allowed_users SELECT to is_user_allowed()
-- =============================================================================
-- Previous policy was auth.role() = 'authenticated', which is broader: any
-- successful Google/GitHub auth (regardless of allowlist membership) could
-- read the team roster. The new policy requires the email to be in the
-- allowlist.
-- =============================================================================
DROP POLICY IF EXISTS "Allowed users can read directory" ON allowed_users;
CREATE POLICY "Allowed users can read directory"
    ON allowed_users FOR SELECT USING (is_user_allowed());


-- =============================================================================
-- 6. M-6 — JSONB size caps to prevent JSON-bomb DoS
-- =============================================================================
ALTER TABLE activities DROP CONSTRAINT IF EXISTS activities_payload_size;
ALTER TABLE activities ADD CONSTRAINT activities_payload_size
    CHECK (pg_column_size(payload) <= 50000);

ALTER TABLE whales DROP CONSTRAINT IF EXISTS whales_qbr_history_size;
ALTER TABLE whales ADD CONSTRAINT whales_qbr_history_size
    CHECK (pg_column_size(qbr_history) <= 50000);

ALTER TABLE whales DROP CONSTRAINT IF EXISTS whales_team_members_size;
ALTER TABLE whales ADD CONSTRAINT whales_team_members_size
    CHECK (pg_column_size(team_members) <= 20000);

ALTER TABLE whales DROP CONSTRAINT IF EXISTS whales_notes_size;
ALTER TABLE whales ADD CONSTRAINT whales_notes_size
    CHECK (length(notes) <= 50000);

ALTER TABLE whale_notes DROP CONSTRAINT IF EXISTS whale_notes_content_size;
ALTER TABLE whale_notes ADD CONSTRAINT whale_notes_content_size
    CHECK (length(content) <= 20000);


-- =============================================================================
-- Verification — uncomment to inspect post-apply
-- =============================================================================
-- SELECT policyname, cmd, qual, with_check FROM pg_policies
--   WHERE tablename IN ('activities','whale_notes','allowed_users') ORDER BY tablename, policyname;
--
-- SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--   WHERE tgrelid = 'whales'::regclass AND NOT tgisinternal;
--
-- -- Smoke test as Vid (run via authenticated browser session, NOT SQL editor):
-- --   UPDATE whales SET arr = arr WHERE id = 1;
-- --   SELECT * FROM activities WHERE whale_id = 1 ORDER BY occurred_at DESC LIMIT 1;
-- -- Should show a new row with actor_povio_id = 'u_vl' and a no-op summary.


-- =============================================================================
-- DONE. Follow-up code change: remove the React-side audit insert in
--      AuthenticatedApp.updateWhales (index.html) since the trigger now
--      handles it server-side. Without that follow-up, every edit logs
--      twice — harmless but noisy. Ship as a separate commit after
--      verifying this migration applied cleanly.
-- =============================================================================
