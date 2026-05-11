# Supabase migrations

This directory tracks SQL migrations as they're applied to the production Supabase project (`jiufnsnxuvhqwzozhlwm.supabase.co`). The `supabase-schema.sql` at the repo root is the canonical bootstrap for a fresh DB. Migrations here are deltas applied on top.

## How to run a migration

Each `.sql` file in this directory is executed via:

1. Supabase Dashboard → **SQL Editor** (left sidebar)
2. Paste the entire contents of the file
3. Click **Run**
4. Check the verification queries at the bottom of each file (commented out — uncomment to run)

All migrations are idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`, `OR REPLACE`) — safe to re-run.

## Migrations applied

| File | Date | Purpose |
|------|------|---------|
| `supabase-schema.sql` (root) | 2024 | Initial schema: goals, whales, whale_notes, team_data, calendar_events + RLS + allowlist |
| `.private-docs/ADD_CONTACTS_AND_REFERRALS.sql` | 2024 | Adds `contacts` (JSONB), `referrals_count`, `referrals_revenue` to whales |
| `002_merge_b.sql` | 2026-05 | Extends `allowed_users` with role + directory fields. Extends `whales` with App B columns (fte, engagement_type, qbr_history, …). Adds 9 new tables (activities, todos, pipeline_deals, outbound_metrics, weekly_reports, qbr_reviews, process_steps, tools_inventory, budget_items). Rewrites RLS so AMs can read+edit all whales but admin-only for everything else. |

## Before running `002_merge_b.sql`

1. **Replace the placeholder email addresses** in section 1 (lines around `INSERT INTO allowed_users`) with your actual AMs' `@povio.com` Google Workspace addresses. Wrong email = silent login failure for that AM (easy to fix later by `UPDATE allowed_users SET email = '...' WHERE povio_id = 'u_xx'`).

2. **Enable Google OAuth provider** in Supabase first (separate manual step — see "Manual setup" below).

3. **Back up the database** (Supabase Dashboard → Database → Backups → Take backup). The RLS rewrite drops the existing whale/calendar policies before creating new ones, so a transactional rollback is your safety net if something goes wrong.

## Manual setup (one-time, before any AM can log in)

### Google OAuth provider

In Supabase Dashboard:
- **Authentication → Providers → Google** → Enable
- Create a Google Cloud OAuth 2.0 client (https://console.cloud.google.com/apis/credentials)
  - Authorized redirect URI: `https://jiufnsnxuvhqwzozhlwm.supabase.co/auth/v1/callback`
  - Authorized JavaScript origin: `https://lesnikvid.github.io`
  - User type: **Internal** (restricts to your `povio.com` Workspace) — this is the key restriction
- Paste the Client ID + Secret into Supabase

After both Google OAuth and migration 002 are in place, the AM provisioning loop is just: insert their email into `allowed_users` with `role='rep'`, share the dashboard URL.

## After running `002_merge_b.sql`

The 198-account import happens in-app via the **Admin → Import** view (admin-only). The import reads `accounts-seed.js` at the repo root, transforms each record (FTE → ARR in thousands, owner_id → owner_povio_id), and upserts into `whales` with `source='am_board_import'`. Existing whales are matched by case-insensitive name and only have new columns filled in — their `arr`/`contacts`/`notes` stay put.

**Rollback for the import:** `DELETE FROM whales WHERE source = 'am_board_import';` removes only the 192-198 imported rows.
