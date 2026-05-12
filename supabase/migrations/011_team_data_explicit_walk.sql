-- =============================================================================
-- Migration 011: PL/pgSQL walk to normalize team_data (third attempt)
-- =============================================================================
-- Migrations 009 + 010 both tried SQL-only approaches to normalize the
-- JSONB names and apparently both failed silently (Calendar still shows
-- Žiga/Daša/etc.). This migration uses a PL/pgSQL DO block that
-- explicitly:
--
--   1. Loops over every member in every team_data row
--   2. Builds a new ASCII name via REPLACE
--   3. Calls jsonb_set with a precise array path ('members', member_id, 'name')
--   4. RAISE NOTICE for each update so we can see what happened in the
--      SQL Editor "messages" pane
--
-- After that, relinks calendar_events by matching member_name to the
-- now-ASCII team_data names.
--
-- Idempotent: members already ASCII are skipped.
-- =============================================================================

DO $$
DECLARE
    r RECORD;
    new_name TEXT;
    members_normalized INT := 0;
    depts_normalized INT := 0;
    events_relinked INT := 0;
BEGIN

    -- 1. Walk every member in every team_data row
    FOR r IN
        SELECT td.user_id, m.key AS member_id, m.val->>'name' AS current_name
        FROM team_data td, jsonb_each(td.structure->'members') AS m(key, val)
    LOOP
        new_name := replace(replace(replace(replace(replace(replace(replace(replace(
            coalesce(r.current_name, ''),
            'Š', 'S'), 'š', 's'),
            'Ž', 'Z'), 'ž', 'z'),
            'Č', 'C'), 'č', 'c'),
            'Ć', 'C'), 'ć', 'c');

        IF new_name <> coalesce(r.current_name, '') THEN
            UPDATE team_data
            SET structure = jsonb_set(
                structure,
                ARRAY['members', r.member_id, 'name'],
                to_jsonb(new_name)
            )
            WHERE user_id = r.user_id;
            members_normalized := members_normalized + 1;
            RAISE NOTICE 'Renamed member %: "%" -> "%"', r.member_id, r.current_name, new_name;
        END IF;
    END LOOP;

    RAISE NOTICE 'Normalized % member names.', members_normalized;


    -- 2. Walk every department too
    FOR r IN
        SELECT td.user_id, idx, d->>'name' AS current_name
        FROM team_data td, jsonb_array_elements(td.structure->'departments') WITH ORDINALITY AS arr(d, idx)
        WHERE jsonb_typeof(td.structure->'departments') = 'array'
    LOOP
        new_name := replace(replace(replace(replace(replace(replace(replace(replace(
            coalesce(r.current_name, ''),
            'Š', 'S'), 'š', 's'),
            'Ž', 'Z'), 'ž', 'z'),
            'Č', 'C'), 'č', 'c'),
            'Ć', 'C'), 'ć', 'c');

        IF new_name <> coalesce(r.current_name, '') THEN
            UPDATE team_data
            SET structure = jsonb_set(
                structure,
                ARRAY['departments', (r.idx - 1)::text, 'name'],
                to_jsonb(new_name)
            )
            WHERE user_id = r.user_id;
            depts_normalized := depts_normalized + 1;
            RAISE NOTICE 'Renamed department [%]: "%" -> "%"', r.idx - 1, r.current_name, new_name;
        END IF;
    END LOOP;

    RAISE NOTICE 'Normalized % department names.', depts_normalized;


    -- 3. Relink calendar_events by member_name (now matching ASCII team_data names)
    FOR r IN
        SELECT ce.id AS event_id, ce.member_name, m.key AS real_id
        FROM calendar_events ce, team_data td, jsonb_each(td.structure->'members') AS m(key, val)
        WHERE ce.member_name = (val->>'name')
          AND ce.member_id LIKE 'm_%'
    LOOP
        UPDATE calendar_events SET member_id = r.real_id WHERE id = r.event_id;
        events_relinked := events_relinked + 1;
        RAISE NOTICE 'Relinked event % for %: -> %', r.event_id, r.member_name, r.real_id;
    END LOOP;

    RAISE NOTICE 'Relinked % calendar events.', events_relinked;

END $$;


-- =============================================================================
-- After this runs, the Messages pane in the SQL Editor will show exactly
-- which members were renamed and which events were relinked. If "Normalized
-- 0 member names" prints, the data is already ASCII (or there's something
-- much weirder going on — paste me the raw output of:
--
--   SELECT key, val->>'name' FROM team_data, jsonb_each(structure->'members') m(key,val);
-- =============================================================================
