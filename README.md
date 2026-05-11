# Povio Sales Dash

Internal sales dashboard. Single-page React app served from GitHub Pages, backed by Supabase.

## Stack

- React 18 + Babel (loaded from CDN, no build step — everything lives in `index.html`)
- Supabase for auth (GitHub OAuth) and data (Postgres with row-level security)
- GitHub Pages for hosting (workflow in `.github/workflows/deploy.yml`)

## Views

- **Goals** — yearly sales targets with milestones, expand/collapse cards
- **Roadmap** — timeline view of goals grouped by bucket
- **Team** — org chart tree + directory, editable departments and people
- **Calendar** — team vacation, sick leave, and work-trip planner (1 / 3 / 6 month views)
- **Whales** — key-account tracker with health badges, contacts, referrals, and timestamped notes

## Local development

Open `index.html` in a browser, or serve the directory with any static server (`python3 -m http.server`). Supabase calls hit the live project — see `.private-docs/GITHUB_AUTH_SETUP.md` for credentials and OAuth setup.

## Database

`supabase-schema.sql` is the single source of truth for tables, indexes, and RLS policies. Apply it once to a fresh Supabase project to bootstrap everything.

## Data

All data shown is dummy/demo content. Real customer information should never be committed to this repo.
