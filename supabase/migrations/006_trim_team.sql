-- =============================================================================
-- Migration 006: Trim allowed_users to active team only
-- =============================================================================
-- Per Vid 2026-05-12:
--   KEEP:   Vid (admin) + Ziga, Dasa, Edvin, Gregor, Sara, Durdica (reps)
--   REMOVE: Klemen Vute, Lana Spiler, Jakob Cvetko, Jernej Lesnik (no longer
--           on the team), and the Unassigned placeholder.
--   UPDATE: Durdica's email from durdica.inactive@local to her real
--           @povio.com address — she's an active AM, not a directory-only
--           entry.
-- =============================================================================


-- 1. Promote Durdica to a real email so she can actually log in via Google.
UPDATE allowed_users
SET email = 'durdica.strunjas.kurt@povio.com',
    notes = 'AM'
WHERE povio_id = 'u_dsk';


-- 2. Reassign whales currently owned by users we're about to remove.
-- Setting owner_povio_id = NULL ("unassigned" in the UI) instead of giving
-- them all to Vid — that way the unowned state is explicit and AMs (or
-- Vid) can pick them up via the inline-edit dropdown.
-- This typically affects 50-70 accounts (most of which had owner = NULL
-- in the original JSON import already, mapped to u_unassigned at import
-- time).
UPDATE whales
SET owner_povio_id = NULL
WHERE owner_povio_id IN ('u_unassigned', 'u_kv', 'u_ls', 'u_jc', 'u_jl');


-- 3. Delete the 5 rows.
DELETE FROM allowed_users
WHERE povio_id IN ('u_unassigned', 'u_kv', 'u_ls', 'u_jc', 'u_jl');


-- =============================================================================
-- Verification (uncomment to inspect)
-- =============================================================================
-- Should return exactly 7 rows: Vid (admin) + 6 reps (Ziga, Dasa, Edvin,
-- Gregor, Sara, Durdica).
-- SELECT povio_id, name, email, role FROM allowed_users
--   ORDER BY role DESC, name;
--
-- Count of whales that now have no owner (need reassignment):
-- SELECT count(*) FROM whales WHERE owner_povio_id IS NULL;

-- =============================================================================
-- Done. Future seeds in migration 002 are updated in the same commit so
-- re-running 002 won't reintroduce the removed rows.
-- =============================================================================
