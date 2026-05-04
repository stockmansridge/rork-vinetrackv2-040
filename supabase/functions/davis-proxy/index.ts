// Supabase Edge Function: davis-proxy
//
// Server-side proxy for Davis WeatherLink v2. Reads vineyard-shared
// credentials from `vineyard_weather_integrations` using the service-role
// key, so operators can fetch rainfall / current conditions for the
// configured station without ever holding the API Secret.
//
// Auth: caller must send the Supabase JWT in the Authorization header.
// We verify the caller is a member of the requested vineyard, then load
// credentials with the service-role client.
//
// Request (POST JSON):
//   {
//     "vineyardId": "<uuid>",
//     "action": "stations" | "current" | "historic" | "test",
//     "stationId"?: string,            // for current / historic
//     "startEpoch"?: number,           // for historic, seconds
//     "endEpoch"?: number,             // for historic, seconds
//     "apiKey"?: string,               // for "test" only (owner/manager)
//     "apiSecret"?: string             // for "test" only (owner/manager)
//   }
//
// 401 if not authenticated, 403 if not a vineyard member, 404 if no
// integration / station configured, 502 on upstream errors.

// deno-lint-ignore-file no-explicit-any

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DAVIS_BASE = "https://api.weatherlink.com/v2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function davisGet(
  path: string,
  apiKey: string,
  apiSecret: string,
  query: Record<string, string> = {},
): Promise<{ status: number; body: any }> {
  const u = new URL(DAVIS_BASE + path);
  u.searchParams.set("api-key", apiKey);
  for (const [k, v] of Object.entries(query)) u.searchParams.set(k, v);
  const res = await fetch(u.toString(), {
    headers: { "X-Api-Secret": apiSecret, Accept: "application/json" },
  });
  let body: any = null;
  try { body = await res.json(); } catch { /* ignore */ }
  return { status: res.status, body };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json({ error: "Server misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }

  // Verify the caller's identity using the user JWT.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userRes, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userRes?.user) {
    return json({ error: "Authentication required" }, 401);
  }
  const userId = userRes.user.id;

  let body: any;
  try { body = await req.json(); } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const vineyardId = typeof body?.vineyardId === "string" ? body.vineyardId : null;
  const action = typeof body?.action === "string" ? body.action : null;
  if (!vineyardId || !action) {
    return json({ error: "vineyardId and action are required" }, 400);
  }

  // Service-role client for privileged reads.
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Membership + role check.
  const { data: memberRow, error: memberErr } = await admin
    .from("vineyard_members")
    .select("role")
    .eq("vineyard_id", vineyardId)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberErr) return json({ error: memberErr.message }, 500);
  if (!memberRow) return json({ error: "Not a vineyard member" }, 403);
  const role = memberRow.role as string;

  // For the "test" action we accept ad-hoc credentials passed in by an
  // owner/manager who is verifying a key before saving.
  if (action === "test") {
    if (role !== "owner" && role !== "manager") {
      return json({ error: "Owner or manager role required" }, 403);
    }
    const apiKey = String(body.apiKey ?? "");
    const apiSecret = String(body.apiSecret ?? "");
    if (!apiKey || !apiSecret) {
      return json({ error: "apiKey and apiSecret are required" }, 400);
    }
    const r = await davisGet("/stations", apiKey, apiSecret);
    if (r.status === 401 || r.status === 403) {
      return json({ error: "Invalid Davis credentials" }, 401);
    }
    if (r.status < 200 || r.status >= 300) {
      return json({ error: `WeatherLink HTTP ${r.status}` }, 502);
    }
    return json({ stations: r.body?.stations ?? [] });
  }

  // For all other actions we read the stored vineyard credentials.
  const { data: integ, error: integErr } = await admin
    .from("vineyard_weather_integrations")
    .select("*")
    .eq("vineyard_id", vineyardId)
    .eq("provider", "davis_weatherlink")
    .eq("is_active", true)
    .maybeSingle();
  if (integErr) return json({ error: integErr.message }, 500);
  if (!integ?.api_key || !integ?.api_secret) {
    return json({ error: "Davis integration not configured for this vineyard" }, 404);
  }
  const apiKey = String(integ.api_key);
  const apiSecret = String(integ.api_secret);

  switch (action) {
    case "stations": {
      const r = await davisGet("/stations", apiKey, apiSecret);
      if (r.status >= 200 && r.status < 300) {
        return json({ stations: r.body?.stations ?? [] });
      }
      return json({ error: `WeatherLink HTTP ${r.status}` }, 502);
    }

    case "current": {
      const stationId = String(body.stationId ?? integ.station_id ?? "");
      if (!stationId) return json({ error: "stationId required" }, 400);
      const r = await davisGet(`/current/${stationId}`, apiKey, apiSecret);
      if (r.status >= 200 && r.status < 300) return json(r.body ?? {});
      return json({ error: `WeatherLink HTTP ${r.status}` }, 502);
    }

    case "historic": {
      const stationId = String(body.stationId ?? integ.station_id ?? "");
      const startEpoch = Number(body.startEpoch);
      const endEpoch = Number(body.endEpoch);
      if (!stationId || !isFinite(startEpoch) || !isFinite(endEpoch)) {
        return json({ error: "stationId, startEpoch, endEpoch required" }, 400);
      }
      const r = await davisGet(
        `/historic/${stationId}`,
        apiKey,
        apiSecret,
        { "start-timestamp": String(startEpoch), "end-timestamp": String(endEpoch) },
      );
      if (r.status === 429) return json({ error: "WeatherLink rate limit reached" }, 429);
      if (r.status >= 200 && r.status < 300) return json(r.body ?? {});
      return json({ error: `WeatherLink HTTP ${r.status}` }, 502);
    }

    default:
      return json({ error: `Unknown action: ${action}` }, 400);
  }
});
