-- =============================================================================
-- Migration 007: Repair corrupted names from migration 005's translate() bug
-- =============================================================================
-- Migration 005 used translate('ŠšŽž', 'SsZz') which — in this PG config —
-- treated the multi-byte UTF-8 input byte-by-byte instead of character-by-
-- character. Result: byte C5 → 'S', A0 → 's', A1 → 'z', BD/BE deleted.
--
-- Visible corruption:
--   Žiga      → Siga       (should be Ziga)
--   Daša      → DaSza      (should be Dasa)
--   Špan      → Sspan      (should be Span)
--   Lešnik    → LeSznik    (should be Lesnik)
--   Špiler    → Sspiler    (should be Spiler)
--   Šorca     → Ssorca     (etc.)
--
-- This migration uses REPLACE() (which IS UTF-8 character-aware in
-- PostgreSQL) to undo the damage on the known patterns + force-set the
-- canonical team names in allowed_users.
-- =============================================================================


-- 1. allowed_users — force the canonical names + initials.
-- We know exactly what each row should be; hard-coded is safer than
-- pattern-matching for these.
UPDATE allowed_users SET name = 'Vid Lesnik',            initials = 'VL' WHERE povio_id = 'u_vl';
UPDATE allowed_users SET name = 'Ziga Triller',          initials = 'ZT' WHERE povio_id = 'u_zt';
UPDATE allowed_users SET name = 'Dasa Ravter',           initials = 'DR' WHERE povio_id = 'u_dr';
UPDATE allowed_users SET name = 'Edvin Lovic',           initials = 'EL' WHERE povio_id = 'u_el';
UPDATE allowed_users SET name = 'Gregor Span',           initials = 'GS' WHERE povio_id = 'u_gs';
UPDATE allowed_users SET name = 'Sara Petric',           initials = 'SP' WHERE povio_id = 'u_sp';
UPDATE allowed_users SET name = 'Durdica Strunjas Kurt', initials = 'DS' WHERE povio_id = 'u_dsk';


-- 2. For free-text fields elsewhere, sweep the known corrupted patterns
-- using REPLACE (character-aware). Plus catch any remaining raw Š/š/Ž/ž
-- that translate() failed to convert.
CREATE OR REPLACE FUNCTION fix_diacritic_corruption(t TEXT) RETURNS TEXT AS $$
    SELECT replace(replace(replace(replace(replace(replace(replace(replace(replace(
        coalesce(t, ''),
        'LeSznik',  'Lesnik'),
        'Sspiler',  'Spiler'),
        'DaSza',    'Dasa'),
        'Sspan',    'Span'),
        'Siga',     'Ziga'),
        -- now sweep any leftover raw diacritics that translate() missed
        'Š', 'S'),
        'š', 's'),
        'Ž', 'Z'),
        'ž', 'z');
$$ LANGUAGE SQL IMMUTABLE;


UPDATE whales SET
    name               = fix_diacritic_corruption(name),
    account_manager    = fix_diacritic_corruption(account_manager),
    notes              = fix_diacritic_corruption(notes),
    last_note          = fix_diacritic_corruption(last_note),
    project_manager    = fix_diacritic_corruption(project_manager),
    invoicing_note     = fix_diacritic_corruption(invoicing_note),
    account_status_raw = fix_diacritic_corruption(account_status_raw),
    industry           = fix_diacritic_corruption(industry);


-- team_members is JSONB array of strings — fix each element
UPDATE whales SET team_members = (
    SELECT jsonb_agg(to_jsonb(fix_diacritic_corruption(elem)))
    FROM jsonb_array_elements_text(team_members) AS elem
)
WHERE team_members IS NOT NULL
  AND jsonb_typeof(team_members) = 'array'
  AND jsonb_array_length(team_members) > 0;


UPDATE whale_notes SET
    content    = fix_diacritic_corruption(content),
    created_by = fix_diacritic_corruption(created_by);


UPDATE activities SET
    summary = fix_diacritic_corruption(summary);


-- Drop the helper once we're done — it's not needed at runtime
DROP FUNCTION IF EXISTS fix_diacritic_corruption(TEXT);


-- =============================================================================
-- Verification — both should return zero rows
-- =============================================================================
-- SELECT povio_id, name FROM allowed_users WHERE name ~ 'Siga|DaSza|Sspan|LeSznik|Sspiler|[ŠšŽž]';
-- SELECT id, name FROM whales WHERE name ~ 'Siga|DaSza|Sspan|LeSznik|Sspiler|[ŠšŽž]'
--                                  OR account_manager ~ 'Siga|DaSza|Sspan|LeSznik|Sspiler|[ŠšŽž]';
