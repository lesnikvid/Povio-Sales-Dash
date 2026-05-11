# Povio Sales Command Center

Internal sales dashboard. Single-page React app served from GitHub Pages, backed by Supabase. Two roles: **admin** (Vid) sees everything; **rep** (AMs) sees only the Accounts list and the read-only Team Calendar.

## Stack

- React 18 + Babel (CDN, no build step — everything lives in `index.html`)
- Supabase for auth (GitHub OAuth for admin, Google Workspace OAuth for AMs) and Postgres with row-level security
- GitHub Pages for hosting (workflow in `.github/workflows/deploy.yml`)

## Views

### Admin-only (Vid)
- **Dashboard** — KPI tiles (total ARR, revenue at risk, goal progress, coverage by AM)
- **Goals** — yearly sales targets with milestones, expand/collapse cards
- **Roadmap** — timeline view of goals grouped by bucket
- **Team** — org chart tree + directory
- **My Week** — personal todos + auto-generated alerts (stale accounts, etc.)
- **Process** — sales playbook (Outbound / Inbound / Partnership flows)
- **Admin** — 198-account import flow, team allowlist, data status

### Accessible to everyone (admin + AMs)
- **Accounts** — full list (198+) with inline-expand 3-tab detail (Overview / Edit / QBR history). Any AM can read and edit any account; every edit auto-writes an `activities` row with a before/after diff so changes are auditable.
- **Calendar** — team vacation / sick / work-trip view. AMs read; admin writes.

## Local development

```bash
python3 -m http.server 8765   # serve from this directory
open http://localhost:8765    # open in a browser
```

Supabase calls hit the live project. For local development against a separate Supabase test project, change the `createClient(...)` URL + anon key in `index.html` (search for `// SUPABASE CLIENT`). OAuth callback URLs must be configured in the Supabase Dashboard + the Google/GitHub OAuth apps before login works from a new origin.

## Database

- `supabase-schema.sql` — canonical bootstrap for a fresh Supabase project (tables, RLS, allowlist).
- `.private-docs/ADD_CONTACTS_AND_REFERRALS.sql` — earlier migration (already applied to production); adds `contacts` JSONB + referrals columns to `whales`.
- `supabase/migrations/002_merge_b.sql` — the latest migration (additive; idempotent). Extends `allowed_users` with role + directory fields, extends `whales` with App B columns (fte, engagement_type, qbr_history, …), adds 9 new tables (activities, todos, pipeline_deals, outbound_metrics, weekly_reports, qbr_reviews, process_steps, tools_inventory, budget_items), rewrites RLS for the role model. See `supabase/migrations/README.md` for run order.

## Deployment runbook — the merge (one-time)

Order matters. Do not deploy the new `index.html` before the migration runs, because the new login flow queries `allowed_users.role` which doesn't exist until migration 002 lands.

1. **Back up Supabase.** Dashboard → Database → Backups → "Take backup."
2. **Add Google OAuth provider** (one-time):
   - Supabase Dashboard → Authentication → Providers → enable Google.
   - Create a Google Cloud OAuth 2.0 client (https://console.cloud.google.com/apis/credentials).
     - **Authorized redirect URI:** `https://jiufnsnxuvhqwzozhlwm.supabase.co/auth/v1/callback`
     - **Authorized JavaScript origin:** `https://lesnikvid.github.io`
     - **User type: Internal** (this is what restricts logins to the `povio.com` Workspace).
   - Paste the Client ID + Client Secret into Supabase. Save.
3. **Run migration 002.** Open `supabase/migrations/002_merge_b.sql` in your editor → copy → Supabase Dashboard → SQL Editor → paste → Run. Confirms with the verification queries at the bottom of the file.
4. **Sanity-check** in the SQL Editor:
   ```sql
   select povio_id, name, role, email from allowed_users order by role desc, povio_id;
   -- Should list Vid as admin + 5 active AMs (rep) + 5 inactive (rep, *.inactive@local emails) + u_unassigned.
   ```
5. **Push the merge branch to main** (auto-deploys to GitHub Pages):
   ```bash
   cd /path/to/Povio-Sales-Dash
   git push origin merge/b-into-a:main
   # Pages will redeploy within ~60s.
   ```
6. **Test as admin:** open `https://lesnikvid.github.io/Povio-Sales-Dash/` → Sign in with GitHub. You should land on Dashboard. All 9 nav items visible. Original goals/whales/team data intact.
7. **Run the 198-account import:**
   - Navigate to `#admin/import` (or click Admin → Import in the nav).
   - Click **Run dry-run** — verify the match table shows ~5 update bucket (existing key whales) + ~193 insert bucket.
   - Click **Run import (writes to database)** — wait for the log to show "✓ Done."
   - Switch to Accounts (`#whales`) — confirm 198+ rows render.
8. **Provision an AM** (test rep access):
   - Have one AM (e.g. Žiga) sign in with their `@povio.com` Google account. He should land on the Accounts list — no nav for Dashboard / Goals / Team / etc. Try `#dashboard` in the URL bar; should redirect to `#whales`.
   - Edit a whale as the AM. Switch to Vid; check `activities` table — should show a row with `actor_povio_id = 'u_zt'` and a diff.

## Rollback

- **Undo the 198-account import:** `DELETE FROM whales WHERE source = 'am_board_import';` — leaves the original key whales untouched.
- **Undo the role-aware RLS:** re-run `supabase-schema.sql` (it `DROP POLICY IF EXISTS` + `CREATE POLICY` for the old user-scoped policies).
- **Revert the deploy:** `git revert <merge-sha>` on `main`, push. Pages redeploys the previous build.

## Adding a new AM

1. Get their `@povio.com` email.
2. In Supabase SQL Editor:
   ```sql
   insert into allowed_users (email, role, povio_id, name, initials, color)
   values ('newperson@povio.com', 'rep', 'u_newperson', 'New Person', 'NP', '#06B6D4');
   ```
3. They sign in with Google. Done.

## Data

Real customer information IS now in this database (after the import). Do not commit any data exports to this repo. `accounts-seed.js` contains the one-time import payload sourced from the Povio AM board export and stays at the repo root for emergency re-seed.
