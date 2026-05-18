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
// Deploy:
//   supabase secrets set POVIO_API_TOKEN=<token>
//   supabase functions deploy povio-sync
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

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
function jsonResponse(body: unknown, status = 200) {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

async function povioGet<T>(path: string, params: Record<string, string | number> = {}): Promise<T> {
    const token = Deno.env.get("POVIO_API_TOKEN");
    if (!token) throw new Error("POVIO_API_TOKEN secret not configured");
    const qs = new URLSearchParams(Object.entries(params).map(([k, v]) => [k, String(v)]));
    const url = `${POVIO_BASE}${path}${qs.toString() ? "?" + qs.toString() : ""}`;
    const r = await fetch(url, {
        headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
    });
    if (!r.ok) {
        const body = await r.text().catch(() => "");
        throw new Error(`Povio ${r.status} on ${path}: ${body.slice(0, 200)}`);
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
    // Open a run row immediately so the Admin UI sees "running…"
    const { data: runRow, error: runErr } = await supa
        .from("povio_sync_runs")
        .insert({ triggered_by: triggeredBy, summary: "in progress" })
        .select()
        .single();
    if (runErr) throw new Error("Could not open sync run: " + runErr.message);
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
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    if (req.method !== "POST") return jsonResponse({ ok: false, error: "POST only" }, 405);

    try {
        const { supa, povioId } = await requireAdmin(req);
        const body = await req.json().catch(() => ({}));
        const action = String(body?.action || "");

        if (action === "test")           return jsonResponse(await actionTest());
        if (action === "list-clients")   return jsonResponse(await actionListClients());
        if (action === "sync-invoices")  return jsonResponse(await actionSyncInvoices(supa, povioId));

        return jsonResponse({ ok: false, error: "unknown action: " + action }, 400);
    } catch (err: unknown) {
        if (err instanceof HttpError) return jsonResponse({ ok: false, error: err.message }, err.status);
        const msg = err instanceof Error ? err.message : String(err);
        return jsonResponse({ ok: false, error: msg }, 500);
    }
});
