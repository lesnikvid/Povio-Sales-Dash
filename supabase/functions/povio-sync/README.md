# `povio-sync` Edge Function

Read-only sync from Povio's public API (`https://app.povio.com/api/public/v1`)
into our `whales` and `povio_clients` tables. The Povio API bearer token is
stored as a Supabase secret and never reaches the browser.

## SECURITY contract (non-negotiable)

The `POVIO_API_TOKEN` secret protects real production billing data.

- **Never** in source code, commits, logs, response bodies, DB columns,
  error messages, or screenshots.
- **Never** copied into the React bundle. Stays server-side, period.
- **Never** in any chat/email/issue tracker. If you need to share it,
  use a password manager or have the recipient generate their own.
- The Supabase secret store is the single source of truth. Local dev
  reads from `supabase/functions/.env.local` (gitignored).
- Anyone with Supabase project membership can read the secret value.
  Keep project membership minimal.
- The function code below NEVER logs the token and NEVER echoes Povio
  response bodies (they could theoretically contain the token in error
  cases). See FIX-1 in commit history for details.

## Actions

`POST /functions/v1/povio-sync` with a JSON body containing `action`:

| action | What it does | DB writes? |
|---|---|---|
| `test` | Pings `/clients?per_page=1`, returns latency + sample client | No |
| `list-clients` | Returns the full paginated client list | No |
| `sync-invoices` | Sums last 365 days of paid invoices per linked client → updates `whales.arr_from_povio`. Logs run to `povio_sync_runs`. Refuses if another sync started < 10 min ago. | Yes |

All three require an **admin** Supabase JWT. The function checks via
`allowed_users.role='admin'`. Reps get 403. The Supabase functions gateway
*also* validates the JWT (`verify_jwt = true` in `supabase/config.toml`).

CORS is restricted to `https://lesnikvid.github.io` and localhost dev
ports. Other Origins receive `Access-Control-Allow-Origin: null`.

## Setup (production, one-time)

### 1. Apply the schema migration

Run `supabase/migrations/018_povio_sync_phase1.sql` in the Supabase SQL
Editor. (Already done in current production.)

### 2. Provision the Povio API token + store as Supabase secret

**Generate token directly in app.povio.com → account settings → API tokens.**
The token should have read access to clients + invoices only.

**Set the secret via Supabase Dashboard** (preferred — masked UI, no
terminal trace):

1. Navigate to: `Project Settings → Edge Functions → Secrets`
2. Click `+ Add new secret`
3. Name: `POVIO_API_TOKEN`
4. Value: paste the token directly
5. Save

**Or via CLI** (only if you have a clean terminal session — `history`
may otherwise capture the value):

```bash
# Do not run this where command history is recorded or shoulder-surfable.
supabase secrets set POVIO_API_TOKEN=<paste-token-here> --project-ref <ref>
```

### 3. Deploy the function

```bash
# Production via CLI:
supabase functions deploy povio-sync --project-ref <ref>

# Or via Dashboard:
# Functions → povio-sync → paste contents of index.ts → Deploy
```

The function reads the secret at runtime via `Deno.env.get("POVIO_API_TOKEN")`.

## Local dev

```bash
# Create the local env file (gitignored):
echo "POVIO_API_TOKEN=<test-token-only>" > supabase/functions/.env.local

# Run the function locally:
supabase functions serve povio-sync --env-file ./supabase/functions/.env.local
```

Use a **separate throwaway test token** for local dev if possible, so
that even an accidental log of the local token doesn't compromise prod.

## Token rotation procedure

Use this when:
- Vid suspects the token leaked
- A team member with Supabase project access leaves
- Routine rotation (recommend every 90 days)
- The token expires (if Povio enforces an expiry)

Steps:

1. Generate a **new** token in app.povio.com (don't revoke the old one yet).
2. Update the Supabase secret via Dashboard (Settings → Edge Functions →
   Secrets → click `POVIO_API_TOKEN` → paste new value → save).
3. Trigger a `Test connection` from the Admin UI. Expected: green dot.
4. Once verified, **revoke the old token** in app.povio.com.
5. If [Test connection] failed before revocation: the new token is bad.
   Don't revoke the old one. Generate a fresh new one and retry.

No app downtime: the function picks up the new secret on the next cold
start. To force a cold start, redeploy the function.

## Invocation from the React app

The Admin "Povio sync" tab in `index.html` invokes via:

```js
const { data, error } = await supabaseClient.functions.invoke('povio-sync', {
    body: { action: 'test' },
});
```

The Supabase JS client automatically forwards the user's session JWT in
the `Authorization` header.

## Verification checklist (run after deploy)

| # | Test | Pass criteria |
|---|---|---|
| V1 | Admin clicks Test connection | Response has `ok:true`, `latency_ms`, `sample_client`. No token-like strings anywhere. |
| V2 | DevTools → Network → check request/response | Request `Authorization` is the Supabase JWT. Response body has no token. |
| V3 | Rep user clicks Test connection | 403, no token leak. |
| V4 | View Supabase function logs | No POVIO_API_TOKEN value visible. |
| V5 | Temporarily set wrong token + Test connection | Response: `"Povio auth failed — check token validity"`. No token chars in response. |
| V6 | First Sync now → inspect povio_sync_runs row | `errors[]` + `summary` contain no token-like strings. |
| V7 | Two browsers click Sync now within 10 min | Second returns 409. |
| V8 | curl with `Origin: https://evil.com` | OPTIONS preflight returns `Access-Control-Allow-Origin: null`. |
| V9 | View deployed function source via Dashboard | No literal token in code, only `Deno.env.get("POVIO_API_TOKEN")`. |
| V10 | `git log --all -S '<token-value>'` | Returns nothing — token was never committed. |

## Tuning

- `SYNC_WINDOW_DAYS` (default 365) — the rolling window over which paid
  invoices are summed for ARR.
- `PAGE_SIZE` (default 50).
- `INVOICE_DELAY_MS` (default 150) — polite pause between per-client
  invoice queries. ~200 linked whales ≈ 30-60s total runtime.
- `CONCURRENCY_WINDOW_MS` (default 10 min) — how long a sync is
  considered "in progress" before another can start.

## Limits

- **Edge Function timeout**: default 60s. If `sync-invoices` runs long
  with 200+ linked whales, switch to batched concurrency.
- **Rate limits**: Povio's docs don't specify. We pace 150ms. If we see
  429s consistently, add exponential backoff.
- **One token, shared**: rotate per the procedure above.

## Future actions (not yet implemented, see plan file)

- `sync-feedbacks` — pull `/client_feedbacks`.
- `sync-projects` — pull `/projects` for status + `last_task_end_date`.
- `sync-project-users` — auto-populate team_members + project_manager.
- `sync-absences` — replace manual vacation seed.
