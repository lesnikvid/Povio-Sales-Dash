-- =============================================================================
-- Migration 005: Normalize Slovenian diacritics to ASCII
-- =============================================================================
-- Replaces Š → S, š → s, Ž → Z, ž → z everywhere in user-visible string
-- data. Required because Google Fonts' on-demand latin-ext subset loading
-- is flaky in some browsers, producing visible "gibberish" for names like
-- "Žiga Triller" or "Daša Ravter" while the fallback font renders them.
-- Vid's preference: just normalize to ASCII at the data layer so the
-- problem cannot recur.
--
-- Uses translate() instead of nested REPLACE() for clarity. Safe to
-- re-run — translate is idempotent for inputs that are already ASCII.
-- =============================================================================


-- 1. allowed_users — team directory (most visible)
UPDATE allowed_users SET
    name     = translate(name,     'ŠšŽž', 'SsZz'),
    initials = translate(initials, 'ŠšŽž', 'SsZz');


-- 2. whales — main accounts table
UPDATE whales SET
    name               = translate(name,               'ŠšŽž', 'SsZz'),
    account_manager    = translate(account_manager,    'ŠšŽž', 'SsZz'),
    notes              = translate(notes,              'ŠšŽž', 'SsZz'),
    industry           = translate(industry,           'ŠšŽž', 'SsZz')
WHERE name IS NOT NULL;

UPDATE whales SET
    last_note          = translate(last_note,          'ŠšŽž', 'SsZz')
WHERE last_note IS NOT NULL;

UPDATE whales SET
    project_manager    = translate(project_manager,    'ŠšŽž', 'SsZz')
WHERE project_manager IS NOT NULL;

UPDATE whales SET
    invoicing_note     = translate(invoicing_note,     'ŠšŽž', 'SsZz')
WHERE invoicing_note IS NOT NULL;

UPDATE whales SET
    account_status_raw = translate(account_status_raw, 'ŠšŽž', 'SsZz')
WHERE account_status_raw IS NOT NULL;


-- 3. whales.team_members — JSONB array of strings, normalize each element
UPDATE whales SET team_members = (
    SELECT jsonb_agg(to_jsonb(translate(elem, 'ŠšŽž', 'SsZz')))
    FROM jsonb_array_elements_text(team_members) AS elem
)
WHERE team_members IS NOT NULL
  AND jsonb_typeof(team_members) = 'array'
  AND jsonb_array_length(team_members) > 0;


-- 4. whale_notes — historical timestamped notes
UPDATE whale_notes SET
    content    = translate(content,    'ŠšŽž', 'SsZz'),
    created_by = translate(created_by, 'ŠšŽž', 'SsZz');


-- 5. activities — audit-log summaries (contain actor names)
UPDATE activities SET
    summary = translate(summary, 'ŠšŽž', 'SsZz')
WHERE summary IS NOT NULL;


-- =============================================================================
-- Verification — both queries should return zero rows after this migration
-- =============================================================================
-- SELECT name, initials FROM allowed_users WHERE name ~ '[ŠšŽž]' OR initials ~ '[ŠšŽž]';
-- SELECT id, name FROM whales WHERE name ~ '[ŠšŽž]' OR account_manager ~ '[ŠšŽž]'
--                                  OR notes ~ '[ŠšŽž]' OR last_note ~ '[ŠšŽž]';

-- =============================================================================
-- Done. App-side change: any future seed data or hardcoded names in code
-- should use ASCII spellings (Ziga, Dasa, Span, Lesnik) for consistency.
-- =============================================================================
