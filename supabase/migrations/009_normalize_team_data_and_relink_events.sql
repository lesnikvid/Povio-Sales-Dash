-- =============================================================================
-- Migration 009: Normalize team_data diacritics + relink calendar events
-- =============================================================================
-- Two fixes in one migration, both surfaced when 008 ran:
--
-- 1. team_data.structure is JSONB and was not touched by migration 005/007 —
--    those only swept text columns. Calendar's left column reads member
--    names from this JSON, so "Žiga Triller / Daša Ravter / Sara Petrič /
--    Gregor Špan / Durdica Strunjaš Kurt / Eva Težak / Jernej Lešnik"
--    still display with diacritics. Cast → REPLACE → cast back to scrub.
--    Adds Č/č/Ć/ć handling that earlier migrations missed (Petrič needs č).
--
-- 2. Migration 008 inserted calendar_events with synthetic member_ids
--    (m_dr, m_zt, m_alja, etc.) that don't match the real team_data member
--    keys, so the Calendar's row-vs-event matcher finds nothing. Update
--    each event's member_id to the team_data member key whose name matches.
--
-- Idempotent: both steps no-op if already in the desired state.
-- =============================================================================


-- 1. Normalize team_data.structure JSONB — scrub all Slovenian diacritics.
-- Casting JSONB to text and back is safe here because none of the diacritic
-- chars appear in JSON syntax (no quote/escape conflicts).
UPDATE team_data SET structure = (
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        structure::text,
        'Š', 'S'), 'š', 's'),
        'Ž', 'Z'), 'ž', 'z'),
        'Č', 'C'), 'č', 'c'),
        'Ć', 'C'), 'ć', 'c')
)::jsonb
WHERE structure::text ~ '[ŠšŽžČčĆć]';


-- 2. Relink calendar_events.member_id to match team_data's real member keys.
-- Match by member_name (now normalised on both sides). We only touch rows
-- whose current member_id starts with 'm_' (i.e. our synthetic seed IDs);
-- pre-existing events keep their member_id.
UPDATE calendar_events ce
SET member_id = sub.real_id
FROM (
    SELECT
        key AS real_id,
        val->>'name' AS name
    FROM team_data,
         jsonb_each(structure->'members') AS m(key, val)
) AS sub
WHERE ce.member_name = sub.name
  AND ce.member_id LIKE 'm\_%' ESCAPE '\';


-- =============================================================================
-- Verification
-- =============================================================================
-- Should return 0 rows after this migration:
-- SELECT user_id, structure::text FROM team_data WHERE structure::text ~ '[ŠšŽžČčĆć]';
--
-- Should show 9 vacation events with member_ids that look like UUIDs / real
-- team_data keys (not m_dr / m_zt / etc.):
-- SELECT member_name, member_id, start_date, end_date FROM calendar_events
-- WHERE event_type = 'vacation' AND start_date >= '2026-06-01'
-- ORDER BY start_date;
--
-- Diagnostic — events whose member_name doesn't match any team_data member:
-- SELECT ce.member_name, ce.member_id
-- FROM calendar_events ce
-- WHERE ce.event_type = 'vacation'
--   AND NOT EXISTS (
--       SELECT 1 FROM team_data,
--            jsonb_each(structure->'members') AS m(key, val)
--       WHERE val->>'name' = ce.member_name
--   );
