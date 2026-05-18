// =============================================================================
// Supabase Edge Function: povio-sync
// =============================================================================
// Read-only sync from Povio's public API (https://app.povio.com/api/public)
// into our `whales` and `povio_clients` tables. The Povio API token never
// reaches the browser — it lives as a Supabase secret accessible only inside
// this function.
//
// Three actions, dispatched via the JSON body's `action` field:
//   - test          → ping the API with a 1-record query. No DB writes.
//   - list-clients  → return the full clients list (paginated, all pages).
//                     Used by the Admin matching UI to compute fuzzy matches.
//   - sync-invoices → for each linked whale, sum the last 365 days of paid
//                     invoices and write to whales.arr_from_povio.
//
// All three require an admin Supabase JWT. Reps get 403.
//
// Local invocation:
//   supabase functions serve povio-sync --env-file ./supabase/functions/.env.local
//   curl -X POST http://localhost:54321/functions/v1/povio-sync \
//     -H "Authorization: Bearer <supabase-anon-jwt>" \
//     -H "Content-Type: application/json" \
//     -d '{"action":"test"}'
//
// Deploy: see README. Token is set via the Supabase Dashboard secrets UI
// (or `supabase secrets set POVIO_API_TOKEN=...`) — never inline.
//
// =============================================================================
// SECURITY — READ BEFORE CHANGING ANYTHING
// =============================================================================
// The POVIO_API_TOKEN secret is the keys to our production billing data.
//   • NEVER console.log it, ever, anywhere — Edge Function logs are
//     visible to all Supabase project members.
//   • NEVER include it in an error message, response body, return value,
//     or DB column (povio_sync_runs.errors and .summary included).
//   • NEVER copy it into the React bundle — the token MUST stay server-side.
//   • NEVER echo upstream Povio response bodies in errors that reach the
//     browser. Their error body could theoretically contain the token.
//     The 502 path below returns only status-class messages to the client.
//   • If you need to debug, work locally with a throwaway test token.
//   • Token rotation: regenerate at app.povio.com, then update the Supabase
//     secret via Dashboard → Settings → Edge Functions → Secrets.
// =============================================================================

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// -----------------------------------------------------------------------------
// Config
// -----------------------------------------------------------------------------
const POVIO_BASE = "https://app.povio.com/api/public/v1";
const SYNC_WINDOW_DAYS = 365;             // 12-month rolling window for ARR
const PAGE_SIZE = 50;                     // page size for /clients and /invoices
const INVOICE_DELAY_MS = 150;             // polite delay between per-client invoice calls
const CONCURRENCY_WINDOW_MS = 10 * 60 * 1000;  // refuse new sync if one started < 10min ago

// CORS allowlist — only echo Origin if the request came from one of these.
// Wildcard "*" would let any site preflight our endpoint, which combined
// with an admin's stale JWT could enable cross-site invocation.
const ALLOWED_ORIGINS = new Set<string>([
    "https://lesnikvid.github.io",       // production GitHub Pages
    "http://localhost:8000",             // local python http.server
    "http://localhost:3000",
    "http://localhost:54321",            // `supabase functions serve` local
]);

function corsFor(req: Request): Record<string, string> {
    const origin = req.headers.get("Origin") || "";
    return {
        "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "null",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Vary": "Origin",
    };
}

// -----------------------------------------------------------------------------
// Types (just the fields we consume)
// -----------------------------------------------------------------------------
interface PovioClient {
    id: number;
    company: string;
    country?: string;
    currency?: string;
    archived?: boolean;
}
interface PovioInvoice {
    id: number;
    client_id: number;
    invoice_date: string;
    paid_at?: string | null;
    status: string;
    amount_in_usd?: number;
    amount?: number;
    currency?: string;
}

// -----------------------------------------------------------------------------
// HTTP helpers
// -----------------------------------------------------------------------------
function jsonResponse(body: unknown, status = 200, cors: Record<string, string> = {}) {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...cors, "Content-Type": "application/json" },
    });
}

async function povioGet<T>(path: string, params: Record<string, string | number> = {}): Promise<T> {
    const token = Deno.env.get("POVIO_API_TOKEN");
    if (!token) throw new HttpError(500, "POVIO_API_TOKEN not configured");
    const qs = new URLSearchParams(Object.entries(params).map(([k, v]) => [k, String(v)]));
    const url = `${POVIO_BASE}${path}${qs.toString() ? "?" + qs.toString() : ""}`;
    const r = await fetch(url, {
        headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    });
    if (!r.ok) {
        // SECURITY: We do NOT include the upstream response body in the
        // error we throw, because Povio's body could theoretically contain
        // the token (some APIs echo invalid bearer tokens back, and we
        // can't trust a third-party API not to). Status alone is enough
        // for the user-facing error. If detailed debugging is needed,
        // an operator with Supabase project access can investigate via
        // the function's invocation history.
        if (r.status === 401 || r.status === 403) {
            throw new HttpError(502, "Povio auth failed — check token validity");
        }
        if (r.status === 429) {
            throw new HttpError(502, "Povio rate limit hit — retry shortly");
        }
        if (r.status >= 500) {
            throw new HttpError(502, "Povio API is having trouble — try again later");
        }
        throw new HttpError(502, `Povio API error (status ${r.status})`);
    }
    return r.json() as Promise<T>;
}

// Walk all pages of a Povio list endpoint, accumulating `data[]`.
async function povioGetAll<T>(path: string, baseParams: Record<string, string | number> = {}): Promise<T[]> {
    const all: T[] = [];
    let page = 1;
    while (true) {
        const resp = await povioGet<{ data: T[]; meta?: { total_pages?: number; total_count?: number } }>(
            path,
            { ...baseParams, page, per_page: PAGE_SIZE },
        );
        const batch = resp.data || [];
        all.push(...batch);
        const totalPages = resp.meta?.total_pages;
        if (totalPages != null) {
            if (page >= totalPages) break;
        } else if (batch.length < PAGE_SIZE) {
            // No meta-page indicator and we got a short page → assume last.
            break;
        }
        page += 1;
        if (page > 200) break;   // safety stop
    }
    return all;
}

// -----------------------------------------------------------------------------
// Auth: confirm the caller is an admin (per the same `is_admin()` SQL
// function used by RLS everywhere else in the app).
// -----------------------------------------------------------------------------
async function requireAdmin(req: Request): Promise<{ supa: SupabaseClient; povioId: string }> {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) throw new HttpError(401, "Missing bearer token");
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supa = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error } = await supa.auth.getUser();
    if (error || !user) throw new HttpError(401, "Invalid session");
    // Pull caller's povio_id + role from allowed_users.
    const { data: au, error: auErr } = await supa
        .from("allowed_users")
        .select("povio_id, role")
        .eq("email", user.email)
        .single();
    if (auErr || !au) throw new HttpError(403, "Not on the team allowlist");
    if (au.role !== "admin") throw new HttpError(403, "Admin only");
    return { supa, povioId: au.povio_id };
}

class HttpError extends Error {
    constructor(public status: number, msg: string) { super(msg); }
}

// -----------------------------------------------------------------------------
// Action: test — ping Povio with a 1-record query
// -----------------------------------------------------------------------------
async function actionTest(): Promise<Record<string, unknown>> {
    const t0 = Date.now();
    const resp = await povioGet<{ data: PovioClient[] }>("/clients", { per_page: 1 });
    const sample = resp.data?.[0];
    return {
        ok: true,
        latency_ms: Date.now() - t0,
        sample_client: sample ? { id: sample.id, company: sample.company } : null,
    };
}

// -----------------------------------------------------------------------------
// Action: list-clients — return the full client list
// -----------------------------------------------------------------------------
async function actionListClients(): Promise<Record<string, unknown>> {
    const clients = await povioGetAll<PovioClient>("/clients");
    return {
        ok: true,
        count: clients.length,
        clients: clients.map((c) => ({
            id: c.id,
            company: c.company,
            country: c.country,
            archived: c.archived === true,
        })),
    };
}

// -----------------------------------------------------------------------------
// Action: sync-invoices — the real sync. For each linked whale, sum the
// last 365 days of paid invoices in USD. Write to whales.arr_from_povio
// in $K. Log to povio_sync_runs.
// -----------------------------------------------------------------------------
async function actionSyncInvoices(supa: SupabaseClient, triggeredBy: string): Promise<Record<string, unknown>> {
    // Concurrency guard: if another sync started recently and hasn't
    // finished, refuse this one. Prevents double Povio API quota burn
    // and duplicate writes when two admins click "Sync now" together.
    const cutoff = new Date(Date.now() - CONCURRENCY_WINDOW_MS).toISOString();
    const { data: inFlight } = await supa
        .from("povio_sync_runs")
        .select("id, started_at")
        .is("finished_at", null)
        .gte("started_at", cutoff)
        .limit(1);
    if (inFlight && inFlight.length > 0) {
        throw new HttpError(409, "A sync is already in progress; wait for it to finish.");
    }

    // Open a run row immediately so the Admin UI sees "running…"
    const { data: runRow, error: runErr } = await supa
        .from("povio_sync_runs")
        .insert({ triggered_by: triggeredBy, summary: "in progress" })
        .select()
        .single();
    if (runErr) throw new HttpError(500, "Could not open sync run");
    const runId = runRow.id;
    const errors: string[] = [];
    let invoicesPulled = 0;
    let whalesUpdated = 0;

    try {
        const { data: links, error: linksErr } = await supa
            .from("povio_clients")
            .select("whale_id, povio_client_id");
        if (linksErr) throw new Error("Could not read povio_clients: " + linksErr.message);
        const today = new Date();
        const start = new Date(today.getTime() - SYNC_WINDOW_DAYS * 86400000);
        const startStr = start.toISOString().slice(0, 10);
        const endStr = today.toISOString().slice(0, 10);

        for (const link of links || []) {
            try {
                const invoices = await povioGetAll<PovioInvoice>("/invoices", {
                    "filters[client_id]":         link.povio_client_id,
                    "filters[invoice_status]":    "paid",
                    "filters[daterange_start]":   startStr,
                    "filters[daterange_end]":     endStr,
                });
                invoicesPulled += invoices.length;
                const sumUsd = invoices.reduce((s, inv) => s + (Number(inv.amount_in_usd) || 0), 0);
                const arrK = Math.round(sumUsd / 1000);

                const { error: upErr } = await supa
                    .from("whales")
                    .update({ arr_from_povio: arrK, povio_synced_at: new Date().toISOString() })
                    .eq("id", link.whale_id);
                if (upErr) {
                    errors.push(`whale ${link.whale_id}: ${upErr.message}`);
                } else {
                    whalesUpdated += 1;
                }
                await supa
                    .from("povio_clients")
                    .update({ last_synced_at: new Date().toISOString() })
                    .eq("whale_id", link.whale_id);
                await new Promise((r) => setTimeout(r, INVOICE_DELAY_MS));
            } catch (perClientErr: unknown) {
                const msg = perClientErr instanceof Error ? perClientErr.message : String(perClientErr);
                errors.push(`client ${link.povio_client_id}: ${msg.slice(0, 200)}`);
            }
        }

        const summary = `Pulled ${invoicesPulled} invoices across ${links?.length ?? 0} linked clients; updated ${whalesUpdated} whales` +
                        (errors.length ? ` (${errors.length} errors)` : "");
        await supa.from("povio_sync_runs").update({
            finished_at: new Date().toISOString(),
            invoices_pulled: invoicesPulled,
            whales_updated:  whalesUpdated,
            errors:          errors.length ? errors.slice(0, 50) : null,
            summary,
        }).eq("id", runId);

        return { ok: true, run_id: runId, invoices_pulled: invoicesPulled, whales_updated: whalesUpdated, errors: errors.slice(0, 10) };
    } catch (fatal: unknown) {
        const msg = fatal instanceof Error ? fatal.message : String(fatal);
        await supa.from("povio_sync_runs").update({
            finished_at: new Date().toISOString(),
            invoices_pulled: invoicesPulled,
            whales_updated:  whalesUpdated,
            errors:          [...errors, "FATAL: " + msg].slice(0, 50),
            summary:         "failed: " + msg.slice(0, 200),
        }).eq("id", runId);
        throw fatal;
    }
}

// -----------------------------------------------------------------------------
// Entrypoint
// -----------------------------------------------------------------------------
serve(async (req) => {
    const cors = corsFor(req);
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return jsonResponse({ ok: false, error: "POST only" }, 405, cors);

    try {
        const { supa, povioId } = await requireAdmin(req);
        const body = await req.json().catch(() => ({}));
        const action = String(body?.action || "");

        if (action === "test")           return jsonResponse(await actionTest(), 200, cors);
        if (action === "list-clients")   return jsonResponse(await actionListClients(), 200, cors);
        if (action === "sync-invoices")  return jsonResponse(await actionSyncInvoices(supa, povioId), 200, cors);

        return jsonResponse({ ok: false, error: "unknown action: " + action }, 400, cors);
    } catch (err: unknown) {
        // SECURITY: only HttpError messages reach the client. Any other
        // throwable surfaces as a generic 500 — we don't trust arbitrary
        // Error.message strings not to contain something they shouldn't.
        if (err instanceof HttpError) return jsonResponse({ ok: false, error: err.message }, err.status, cors);
        return jsonResponse({ ok: false, error: "Internal server error" }, 500, cors);
    }
});
