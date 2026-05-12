-- =============================================================================
-- Migration 003: Fix RLS helper-function permissions
-- =============================================================================
-- Symptom: "permission denied for function is_user_allowed" on INSERT into
-- whales (and any table that has is_user_allowed() / is_admin() in its policy).
--
-- Cause: SECURITY DEFINER functions in modern Supabase need an explicit
-- search_path. Without it, the planner refuses to invoke them from inside
-- a RLS policy's WITH CHECK clause. Also re-grants EXECUTE on all three
-- helper functions to authenticated + anon roles to remove any doubt.
--
-- Safe to re-run.
-- =============================================================================

ALTER FUNCTION public.is_user_allowed()  SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.is_admin()         SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.current_povio_id() SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_user_allowed()  TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_admin()         TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.current_povio_id() TO authenticated, anon;

-- Verify
SELECT
  proname,
  pg_get_userbyid(proowner)                                AS owner,
  has_function_privilege('authenticated', oid, 'EXECUTE')  AS auth_can_call,
  proconfig                                                AS search_path_config
FROM pg_proc
WHERE proname IN ('is_user_allowed', 'is_admin', 'current_povio_id')
ORDER BY proname;
