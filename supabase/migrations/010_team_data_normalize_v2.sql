-- =============================================================================
-- Migration 010: Robust team_data name normalization + name-based event relink
-- =============================================================================
-- Migration 009's first statement (cast JSONB → text → REPLACE → cast back)
-- apparently didn't take effect — the calendar still shows diacritic names
-- (Žiga, Daša, Sara Petrič, Gregor Špan, Durdica Strunjaš Kurt, Eva Težak,
-- Jernej Lešnik, Vid Lešnik). Possible reasons: the cast format escaped chars
-- differently than REPLACE expected, or some part errored silently. Either
-- way: bypass the text-cast hack and rebuild the JSON structurally with
-- jsonb_set + jsonb_object_agg / jsonb_agg.
--
-- Also re-runs the calendar-event relink using normalized-name comparison
-- (works regardless of whether team_data was normalized).
--
-- Idempotent.
-- =============================================================================


-- Helper: nested REPLACE for the 4 pairs of Slovenian diacritics.
-- TEMP function — dropped at end of migration.
CREATE OR REPLACE FUNCTION pg_temp_strip_diacritics(t TEXT) RETURNS TEXT
LANGUAGE SQL IMMUTABLE AS $$
    SELECT replace(replace(replace(replace(replace(replace(replace(replace(
        coalesce(t, ''),
        'Š', 'S'), 'š', 's'),
        'Ž', 'Z'), 'ž', 'z'),
        'Č', 'C'), 'č', 'c'),
        'Ć', 'C'), 'ć', 'c');
$$;


-- 1. Normalize team_data.structure.members — rebuild the members object
-- with each member's `name` and `title` fields scrubbed.
UPDATE team_data SET structure = jsonb_set(
    structure,
    '{members}',
    COALESCE((
        SELECT jsonb_object_agg(
            key,
            val
              || jsonb_build_object('name',  pg_temp_strip_diacritics(val->>'name'))
              || jsonb_build_object('title', pg_temp_strip_diacritics(val->>'title'))
        )
        FROM jsonb_each(structure->'members') AS m(key, val)
    ), '{}'::jsonb)
)
WHERE structure ? 'members'
  AND structure->'members' IS NOT NULL;


-- 2. Normalize team_data.structure.departments — same idea but for the
-- array of departments (each has a `name` field).
UPDATE team_data SET structure = jsonb_set(
    structure,
    '{departments}',
    COALESCE((
        SELECT jsonb_agg(
            d || jsonb_build_object('name', pg_temp_strip_diacritics(d->>'name'))
        )
        FROM jsonb_array_elements(structure->'departments') AS d
    ), '[]'::jsonb)
)
WHERE structure ? 'departments'
  AND jsonb_typeof(structure->'departments') = 'array'
  AND jsonb_array_length(structure->'departments') > 0;


-- 3. Relink calendar_events by normalized name. This works even if the
-- team_data update above somehow didn't take effect — we compare against
-- the normalized form of whatever's in team_data right now.
UPDATE calendar_events ce
SET member_id = sub.real_id
FROM (
    SELECT
        key AS real_id,
        pg_temp_strip_diacritics(val->>'name') AS normalized_name
    FROM team_data,
         jsonb_each(structure->'members') AS m(key, val)
) AS sub
WHERE ce.member_name = sub.normalized_name
  AND ce.member_id LIKE 'm\_%' ESCAPE '\';


-- 4. Drop the helper
DROP FUNCTION pg_temp_strip_diacritics(TEXT);


-- =============================================================================
-- Verification
-- =============================================================================
-- All member names should be ASCII after this migration:
-- SELECT user_id, val->>'name' AS member_name
-- FROM team_data, jsonb_each(structure->'members') AS m(key, val)
-- ORDER BY member_name;
--
-- All 9 vacation events should now have a non-m_-prefixed member_id:
-- SELECT member_name, member_id, start_date, end_date
-- FROM calendar_events
-- WHERE event_type = 'vacation' AND start_date >= '2026-06-01'
-- ORDER BY start_date;
-- Look for: no member_id starts with 'm_'.
