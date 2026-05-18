# `povio-sync` Edge Function

Read-only sync from Povio's public API (`https://app.povio.com/api/public/v1`)
into our `whales` and `povio_clients` tables. The Povio API bearer token is
stored as a Supabase secret and never reaches the browser.

## Actions

`POST /functions/v1/povio-sync` with a JSON body containing `action`:

| action | What it does | DB writes? |
|---|---|---|
| `test` | Pings `/clients?per_page=1`, returns latency + sample client | No |
| `list-clients` | Returns the full paginated client list | No |
| `sync-invoices` | Sums last 365 days of paid invoices per linked client → updates `whales.arr_from_povio`. Logs run to `povio_sync_runs`. | Yes |

All three require an **admin** Supabase JWT (the function calls
`allowed_users` to confirm `role='admin'`). Reps get 403.

## Setup

### 1. Apply the schema migration

Run `supabase/migrations/018_povio_sync_phase1.sql` in the Supabase SQL Editor.
This creates `povio_clients`, `povio_sync_runs`, and adds two columns to `whales`.

### 2. Provision the Povio API token

Vid generates an API token from `https://app.povio.com/` (account settings).
The token should have read access to: clients, invoices.

Store the token as a Supabase secret (NOT in git, NOT in `.env` files committed
to the repo):

```bash
# Production:
supabase secrets set POVIO_API_TOKEN=<token> --project-ref <ref>

# Local dev:
echo "POVIO_API_TOKEN=<token>" > supabase/functions/.env.local
# (.env.local is gitignored.)
```

### 3. Deploy the function

```bash
# Local dev:
supabase functions serve povio-sync --env-file ./supabase/functions/.env.local

# Production:
supabase functions deploy povio-sync
```

## Invocation from the React app

The Admin "Povio sync" tab in `index.html` invokes via:

```js
const { data, error } = await supabaseClient.functions.invoke('povio-sync', {
    body: { action: 'test' },
});
```

The Supabase JS client automatically forwards the user's session JWT in the
`Authorization` header, which the function uses to verify the caller is an
admin.

## Smoke test via curl

```bash
# Replace <ANON_KEY> with your project's anon key, <ADMIN_JWT> with a logged-in
# admin's access_token (copy from devtools after signing in as Vid).

curl -X POST 'https://<project-ref>.supabase.co/functions/v1/povio-sync' \
    -H "Authorization: Bearer <ADMIN_JWT>" \
    -H "apikey: <ANON_KEY>" \
    -H "Content-Type: application/json" \
    -d '{"action":"test"}'
```

Expected response:
```json
{
    "ok": true,
    "latency_ms": 230,
    "sample_client": { "id": 42, "company": "Acme Corp" }
}
```

## Tuning

- `SYNC_WINDOW_DAYS` (default 365) — the rolling window over which paid
  invoices are summed for ARR. Increase to 730 for a 24-month rolling
  average if Povio prefers smoother numbers.
- `PAGE_SIZE` (default 50) — bumped to 50 to keep per-client round trips
  low. Raise carefully; large pages might 429 on Povio's side.
- `INVOICE_DELAY_MS` (default 150) — polite pause between per-client
  invoice queries. Total runtime for ~200 linked whales ≈ 30-60s.

## Limits

- **Edge Function timeout**: default 60s. If `sync-invoices` over 200+
  linked whales runs long, switch to batched concurrency (`Promise.all`
  groups of 10) — see comment block at the top of `index.ts`.
- **Rate limits**: Povio's docs don't specify. We pace 150ms between
  calls. If we see 429s, add exponential backoff.
- **One token, shared**: Vid's personal API token authenticates every
  sync. If Vid leaves Povio (unlikely!), rotate the token via the
  `supabase secrets set` command.

## Future actions (not yet implemented, see plan file)

- `sync-feedbacks` — pull `/client_feedbacks` into a new `client_feedbacks`
  table. Sidebar surfaces the latest score.
- `sync-projects` — pull `/projects` for status + `last_task_end_date`.
- `sync-project-users` — auto-populate team_members + project_manager.
- `sync-absences` — replace manual vacation seed.
