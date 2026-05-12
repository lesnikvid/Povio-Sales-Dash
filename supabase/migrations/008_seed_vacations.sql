-- =============================================================================
-- Migration 008: Seed team vacations from Slack thread
-- =============================================================================
-- Vid pasted a Slack screenshot of summer vacations on 2026-05-12.
-- This migration inserts the 9 vacation events into calendar_events,
-- attributed to Vid (the admin). Idempotent — re-running won't duplicate
-- because each row is gated by NOT EXISTS on the (member_name, start_date,
-- end_date) tuple.
--
-- Names normalized to ASCII per the diacritic policy (Daša → Dasa,
-- Petrič → Petric, Težak → Tezak).
--
-- member_ids:
--   AMs that are in allowed_users get a stable id matching their povio_id
--   (m_vl, m_zt, m_dr, m_el, m_gs, m_sp, m_dsk).
--   Non-AMs (Alja, Eva) get synthetic ids (m_alja, m_eva).
-- =============================================================================


-- Use a CTE to resolve Vid's auth uid once. allowed_users has no
-- auth_user_id column (RLS uses email-based lookup), so we resolve via
-- auth.users with team_data as fallback in case the email doesn't match.
WITH vid AS (
    SELECT COALESCE(
        (SELECT id::text   FROM auth.users WHERE email = 'lesnik.vid@gmail.com' LIMIT 1),
        (SELECT user_id    FROM team_data LIMIT 1),
        (SELECT user_id    FROM goals     LIMIT 1)
    ) AS user_id
),
events(member_id, member_name, start_date, end_date) AS (
    VALUES
        ('m_dr',    'Dasa Ravter',    DATE '2026-06-26', DATE '2026-07-10'),
        ('m_zt',    'Ziga Triller',   DATE '2026-06-08', DATE '2026-06-25'),
        ('m_el',    'Edvin Lovic',    DATE '2026-08-03', DATE '2026-08-17'),
        ('m_gs',    'Gregor Span',    DATE '2026-07-08', DATE '2026-07-15'),
        ('m_sp',    'Sara Petric',    DATE '2026-06-06', DATE '2026-06-11'),
        ('m_sp',    'Sara Petric',    DATE '2026-08-14', DATE '2026-08-24'),
        ('m_alja',  'Alja Drovenik',  DATE '2026-07-30', DATE '2026-07-31'),
        ('m_alja',  'Alja Drovenik',  DATE '2026-09-03', DATE '2026-09-11'),
        ('m_eva',   'Eva Tezak',      DATE '2026-06-26', DATE '2026-07-03')
)
INSERT INTO calendar_events (user_id, member_id, member_name, event_type, start_date, end_date, title)
SELECT vid.user_id, e.member_id, e.member_name, 'vacation', e.start_date, e.end_date, 'Vacation'
FROM events e CROSS JOIN vid
WHERE vid.user_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM calendar_events ce
      WHERE ce.member_name = e.member_name
        AND ce.start_date  = e.start_date
        AND ce.end_date    = e.end_date
        AND ce.event_type  = 'vacation'
  );


-- =============================================================================
-- Verification
-- =============================================================================
-- SELECT member_name, start_date, end_date, event_type
-- FROM calendar_events
-- WHERE event_type = 'vacation' AND start_date >= '2026-06-01'
-- ORDER BY start_date;
--
-- Should return 9 rows.
