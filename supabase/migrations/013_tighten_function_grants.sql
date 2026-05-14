-- =============================================================================
-- Migration 013: Tighten SECURITY DEFINER function grants
-- =============================================================================
-- Supabase Security Advisor flagged 5 functions as callable by Public and/or
-- Signed-In Users. Categorise + lock down:
--
--   TRIGGER FUNCTIONS (only invoked by triggers, never as RPC):
--     - enforce_whale_audit_stamp()
--     - log_whale_edit()
--   These should not be callable by any user. Revoke ALL. Triggers still
--   fire — PostgreSQL invokes trigger functions through the trigger
--   mechanism, not through user EXECUTE grants.
--
--   RLS HELPER FUNCTIONS (must remain callable by authenticated for RLS
--   policy evaluation):
--     - is_admin()
--     - is_user_allowed()
--     - current_povio_id()
--   Each returns a small scalar about the caller's own identity — no
--   leak risk. But revoke from PUBLIC/anon so unauthenticated users
--   can't probe them.
--
-- Net effect after this migration:
--   • Anon role:          can call zero of these 5 functions.
--   • Authenticated role: can call is_admin / is_user_allowed /
--                         current_povio_id (needed for RLS); cannot call
--                         enforce_whale_audit_stamp / log_whale_edit
--                         (so cannot forge audit rows via RPC).
--
-- The Security Advisor warnings for "Signed-In Users Can Execute" on the
-- three helper functions will remain after this migration — that's by
-- design. The functions are read-only scalars about the caller. Acceptable.
-- =============================================================================


-- 1. Trigger functions — lock down entirely
REVOKE ALL ON FUNCTION public.enforce_whale_audit_stamp() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.log_whale_edit()             FROM PUBLIC, anon, authenticated, service_role;


-- 2. RLS helper functions — revoke from anon/public, keep authenticated
REVOKE ALL ON FUNCTION public.is_admin()          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_user_allowed()   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_povio_id()  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.is_admin()         TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_user_allowed()  TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_povio_id() TO authenticated;


-- =============================================================================
-- Verification (uncomment to inspect)
-- =============================================================================
-- Confirm trigger functions still attached to whales (should return 2 rows):
-- SELECT tgname FROM pg_trigger
-- WHERE tgrelid = 'whales'::regclass AND NOT tgisinternal;
--
-- Confirm grants are tightened (each row shows which roles can execute):
-- SELECT
--   p.proname,
--   pg_get_userbyid(g.grantee) AS role,
--   g.privilege_type
-- FROM pg_proc p
-- JOIN information_schema.role_routine_grants g ON g.routine_name = p.proname
-- WHERE p.proname IN ('is_admin','is_user_allowed','current_povio_id',
--                     'enforce_whale_audit_stamp','log_whale_edit')
-- ORDER BY p.proname, role;
--
-- Smoke test (run via authenticated session in the live app):
--   1. Edit any whale field. Confirm an activities row appears with
--      kind='edit' and your povio_id. (proves trigger still fires)
--   2. In the browser console:
--      const { error } = await supabaseClient.rpc('log_whale_edit');
--      Should return: { error: { code: '42501', message: 'permission denied' } }
--   3. Same for enforce_whale_audit_stamp — should be permission denied.
--
-- =============================================================================
