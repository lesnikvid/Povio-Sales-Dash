-- =============================================================================
-- Migration 005: Normalize Slovenian diacritics to ASCII
-- =============================================================================
-- Replaces Š → S, š → s, Ž → Z, ž → z everywhere in user-visible string data.
-- Required because Google Fonts' on-demand latin-ext subset loading is flaky
-- in some browsers, producing visible "gibberish" for names like "Žiga
-- Triller" or "Daša Ravter" while a fallback font renders them.
--
-- ⚠️ HISTORICAL NOTE: The original version of this file used translate()
-- which, in this Supabase PG config, treats multi-byte UTF-8 input byte-by-
-- byte and produces wrong results (Žiga → Siga, Daša → DaSza, etc.).
-- Migration 007 cleans up the resulting corruption and this file has been
-- rewritten to use REPLACE() (character-aware) so a re-run is safe.
--
-- Idempotent: re-running on already-normalised data is a no-op.
-- =============================================================================


-- Helper: nested REPLACE for all four diacritic chars. Use this everywhere
-- instead of translate(). PG's REPLACE is UTF-8 character-aware.
-- (Function lives only for the duration of this migration, then dropped.)
CREATE OR REPLACE FUNCTION pg_temp_remove_diacritics(t TEXT) RETURNS TEXT
LANGUAGE SQL IMMUTABLE AS $$
    SELECT replace(replace(replace(replace(coalesce(t, ''),
        'Š', 'S'),
        'š', 's'),
        'Ž', 'Z'),
        'ž', 'z');
$$;


-- 1. allowed_users
UPDATE allowed_users SET
    name     = pg_temp_remove_diacritics(name),
    initials = pg_temp_remove_diacritics(initials);


-- 2. whales — string columns
UPDATE whales SET
    name               = pg_temp_remove_diacritics(name),
    account_manager    = pg_temp_remove_diacritics(account_manager),
    notes              = pg_temp_remove_diacritics(notes),
    industry           = pg_temp_remove_diacritics(industry),
    last_note          = pg_temp_remove_diacritics(last_note),
    project_manager    = pg_temp_remove_diacritics(project_manager),
    invoicing_note     = pg_temp_remove_diacritics(invoicing_note),
    account_status_raw = pg_temp_remove_diacritics(account_status_raw);


-- 3. whales.team_members — JSONB array, normalize each element
UPDATE whales SET team_members = (
    SELECT jsonb_agg(to_jsonb(pg_temp_remove_diacritics(elem)))
    FROM jsonb_array_elements_text(team_members) AS elem
)
WHERE team_members IS NOT NULL
  AND jsonb_typeof(team_members) = 'array'
  AND jsonb_array_length(team_members) > 0;


-- 4. whale_notes — historical timestamped notes
UPDATE whale_notes SET
    content    = pg_temp_remove_diacritics(content),
    created_by = pg_temp_remove_diacritics(created_by);


-- 5. activities — audit-log summaries
UPDATE activities SET
    summary = pg_temp_remove_diacritics(summary);


DROP FUNCTION pg_temp_remove_diacritics(TEXT);


-- =============================================================================
-- Verification (uncomment to check)
-- =============================================================================
-- SELECT name FROM allowed_users WHERE name ~ '[ŠšŽž]';        -- expect 0 rows
-- SELECT id, name FROM whales WHERE name ~ '[ŠšŽž]';            -- expect 0 rows
