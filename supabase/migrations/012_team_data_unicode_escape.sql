-- =============================================================================
-- Migration 012: Normalize team_data — using chr() so the SQL is pure ASCII
-- =============================================================================
-- Diagnostic from Vid 2026-05-12 confirms team_data still has the literal
-- diacritics in JSONB:
--   dasa    -> Da[š]a Ravter
--   gregor  -> Gregor [Š]pan
--   ziga    -> [Ž]iga Triller
--   ...
--
-- Previous migrations (005, 007, 009, 010, 011) used literal diacritic
-- chars in their REPLACE arguments. Suspicion: somewhere between writing
-- the SQL file and PostgreSQL receiving it, the chars got normalized
-- (NFC <-> NFD) or otherwise transformed, so REPLACE didn't match the
-- chars stored in team_data.
--
-- This migration eliminates the issue entirely by building the source
-- chars from their Unicode codepoints via chr(). The SQL file is pure
-- ASCII; the chars are constructed at runtime in PostgreSQL.
--
--   Š=U+0160 (352)   š=U+0161 (353)
--   Ž=U+017D (381)   ž=U+017E (382)
--   Č=U+010C (268)   č=U+010D (269)
--   Ć=U+0106 (262)   ć=U+0107 (263)
-- =============================================================================

DO $$
DECLARE
    r RECORD;
    new_name TEXT;
    members_normalized INT := 0;
    events_relinked INT := 0;
    -- All 8 source chars constructed via chr() — no non-ASCII in the SQL itself
    chr_S_caron_upper TEXT := chr(352);
    chr_S_caron_lower TEXT := chr(353);
    chr_Z_caron_upper TEXT := chr(381);
    chr_Z_caron_lower TEXT := chr(382);
    chr_C_caron_upper TEXT := chr(268);
    chr_C_caron_lower TEXT := chr(269);
    chr_C_acute_upper TEXT := chr(262);
    chr_C_acute_lower TEXT := chr(263);
BEGIN

    -- 1. Walk every member in every team_data row
    FOR r IN
        SELECT td.user_id, m.key AS member_id, m.val->>'name' AS current_name
        FROM team_data td, jsonb_each(td.structure->'members') AS m(key, val)
    LOOP
        new_name := replace(replace(replace(replace(replace(replace(replace(replace(
            coalesce(r.current_name, ''),
            chr_S_caron_upper, 'S'),
            chr_S_caron_lower, 's'),
            chr_Z_caron_upper, 'Z'),
            chr_Z_caron_lower, 'z'),
            chr_C_caron_upper, 'C'),
            chr_C_caron_lower, 'c'),
            chr_C_acute_upper, 'C'),
            chr_C_acute_lower, 'c');

        IF new_name <> coalesce(r.current_name, '') THEN
            UPDATE team_data
            SET structure = jsonb_set(
                structure,
                ARRAY['members', r.member_id, 'name'],
                to_jsonb(new_name)
            )
            WHERE user_id = r.user_id;
            members_normalized := members_normalized + 1;
            RAISE NOTICE 'Renamed member key=%: % -> %', r.member_id, r.current_name, new_name;
        END IF;
    END LOOP;

    RAISE NOTICE 'Total member renames: %', members_normalized;


    -- 2. Departments (same idea)
    FOR r IN
        SELECT td.user_id, idx, d->>'name' AS current_name
        FROM team_data td, jsonb_array_elements(td.structure->'departments') WITH ORDINALITY AS arr(d, idx)
        WHERE jsonb_typeof(td.structure->'departments') = 'array'
    LOOP
        new_name := replace(replace(replace(replace(replace(replace(replace(replace(
            coalesce(r.current_name, ''),
            chr_S_caron_upper, 'S'),
            chr_S_caron_lower, 's'),
            chr_Z_caron_upper, 'Z'),
            chr_Z_caron_lower, 'z'),
            chr_C_caron_upper, 'C'),
            chr_C_caron_lower, 'c'),
            chr_C_acute_upper, 'C'),
            chr_C_acute_lower, 'c');

        IF new_name <> coalesce(r.current_name, '') THEN
            UPDATE team_data
            SET structure = jsonb_set(
                structure,
                ARRAY['departments', (r.idx - 1)::text, 'name'],
                to_jsonb(new_name)
            )
            WHERE user_id = r.user_id;
            RAISE NOTICE 'Renamed department [%]: % -> %', r.idx - 1, r.current_name, new_name;
        END IF;
    END LOOP;


    -- 3. Relink calendar_events: now that team_data is ASCII, our ASCII
    -- event member_names should match directly.
    FOR r IN
        SELECT ce.id AS event_id, ce.member_name, m.key AS real_id
        FROM calendar_events ce, team_data td, jsonb_each(td.structure->'members') AS m(key, val)
        WHERE ce.member_name = (val->>'name')
          AND ce.member_id LIKE 'm_%'
    LOOP
        UPDATE calendar_events SET member_id = r.real_id WHERE id = r.event_id;
        events_relinked := events_relinked + 1;
        RAISE NOTICE 'Relinked event id=%, name=%, -> member_id=%', r.event_id, r.member_name, r.real_id;
    END LOOP;

    RAISE NOTICE 'Total events relinked: %', events_relinked;


    -- Final state report
    RAISE NOTICE '---- POST-MIGRATION STATE ----';
    FOR r IN
        SELECT key, val->>'name' AS name
        FROM team_data, jsonb_each(structure->'members') AS m(key, val)
        ORDER BY key
    LOOP
        RAISE NOTICE '  member %: %', r.key, r.name;
    END LOOP;

END $$;
