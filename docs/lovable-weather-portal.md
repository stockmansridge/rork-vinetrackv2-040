# Lovable Portal — Davis WeatherLink Integration Guide

Hand-off contract for the Lovable head-office portal to manage **vineyard-level**
Davis WeatherLink (and future Wunderground) credentials.

> Everything below is already live in the Supabase project. **No new migrations
> required.** Lovable should call the existing RPCs and the `davis-proxy`
> edge function — nothing else.

---

## 1. Connection

- Same Supabase project as the iOS app.
- Use **`EXPO_PUBLIC_SUPABASE_URL`** + **`EXPO_PUBLIC_SUPABASE_ANON_KEY`** only.
- **Never** embed the service-role key in the browser.
- Authenticate the user with Supabase Auth. RLS + role checks inside each RPC
  enforce who can do what — Lovable does not need to gate calls itself, but
  should hide UI from non-owner/manager users for UX.

## 2. Roles

Read from `get_vineyard_weather_integration(...).caller_role`:

| Role | View status | Edit / save | Test | Delete |
| --- | :-: | :-: | :-: | :-: |
| `owner` | ✅ | ✅ | ✅ | ✅ |
| `manager` | ✅ | ✅ | ✅ | ✅ |
| `supervisor` | ✅ | ❌ | ❌ | ❌ |
| `operator` | ✅ | ❌ | ❌ | ❌ |

There is no `admin` role on `vineyard_members`. Owner + manager are the only
roles permitted to write. The portal must hide credential edit forms from
operators/supervisors; the RPCs will return `42501` if called regardless.

## 3. RPCs to use (already deployed)

All RPCs are `SECURITY DEFINER`, `set search_path = public`, granted to
`authenticated`. They live in `sql/021_vineyard_weather_integrations.sql`.

### 3.1 Read status — any vineyard member

```sql
public.get_vineyard_weather_integration(
  p_vineyard_id uuid,
  p_provider    text default 'davis_weatherlink'
) returns table (
  id, vineyard_id, provider,
  has_api_key boolean,        -- true if a key is stored
  has_api_secret boolean,     -- true if a secret is stored
  station_id, station_name,
  station_latitude, station_longitude,
  has_leaf_wetness, has_rain, has_wind, has_temperature_humidity,
  detected_sensors text[],
  configured_by uuid,
  updated_at, last_tested_at, last_test_status,
  is_active,
  caller_role  -- 'owner' | 'manager' | 'supervisor' | 'operator'
);
```

- **Never returns** `api_key` / `api_secret`. There is no client-callable RPC
  in Lovable that returns them.
- A row missing → no integration configured. Render the empty state, not an
  error.

UI status logic:
```
configured = has_api_key && has_api_secret && is_active
            && (station_id is not null)
```

### 3.2 Save / update — owner / manager only

```sql
public.save_vineyard_weather_integration(
  p_vineyard_id uuid,
  p_provider    text,                          -- 'davis_weatherlink'
  p_api_key     text default null,
  p_api_secret  text default null,
  p_station_id  text default null,
  p_station_name text default null,
  p_station_latitude  double precision default null,
  p_station_longitude double precision default null,
  p_has_leaf_wetness  boolean default null,
  p_has_rain          boolean default null,
  p_has_wind          boolean default null,
  p_has_temperature_humidity boolean default null,
  p_detected_sensors  text[] default null,
  p_last_tested_at    timestamptz default null,
  p_last_test_status  text default null,
  p_is_active         boolean default null
) returns uuid;
```

Behaviour:
- Upsert by unique `(vineyard_id, provider)`.
- Every column uses `coalesce(excluded.x, i.x)` — **passing `NULL` preserves
  the existing value**.
- Returns the integration `id`. **Does not return secrets.**

### Critical — preserving existing secrets

| User input | Send to RPC |
| --- | --- |
| User left API key field blank | `p_api_key: null` |
| User left API secret field blank | `p_api_secret: null` |
| User typed a new value | the new string |
| User wants to clear it | call `delete_vineyard_weather_integration` (do NOT send `""`) |

**Do not send `""` for blank secret fields** — the RPC treats empty string as
a real value and would overwrite the stored secret with empty. Send SQL
`NULL` (in supabase-js: omit the parameter or pass `null`).

Example (supabase-js, owner editing station name only):
```ts
const { data, error } = await supabase.rpc("save_vineyard_weather_integration", {
  p_vineyard_id: vineyardId,
  p_provider: "davis_weatherlink",
  p_station_name: "North block Vantage Pro2",
  // p_api_key / p_api_secret omitted → existing secrets preserved
});
```

### 3.3 Delete / disable — owner / manager only

```sql
public.delete_vineyard_weather_integration(
  p_vineyard_id uuid,
  p_provider    text default 'davis_weatherlink'
) returns void;
```

This is the **only** sanctioned way to clear stored credentials. Treat it as
destructive in the UI — confirm, then call.

If you only want to pause without losing the keys, call
`save_vineyard_weather_integration(..., p_is_active => false)` instead.

### 3.4 Do **not** call from the portal

```
public.reveal_vineyard_weather_integration_credentials(...)
```

This RPC returns the cleartext key + secret and exists only for the iOS
management UI's masked-view / rotate flow. The portal must never call it —
managing credentials does not require reading them. Show "Configured" /
"Not configured" from `has_api_key` + `has_api_secret`.

## 4. Test connection — `davis-proxy` edge function

The connection test is performed server-side by the existing edge function
so credentials never leave the backend. There is no SQL `test_*` RPC.

`POST {SUPABASE_URL}/functions/v1/davis-proxy`
Headers:
```
Authorization: Bearer <user JWT>
apikey: <anon key>
Content-Type: application/json
```

### 4.1 Test before saving — `action: "test"`

Verify a key/secret pair the user just typed, before persisting it.

```json
{
  "vineyardId": "<uuid>",
  "action": "test",
  "apiKey": "...",
  "apiSecret": "..."
}
```

Response (200): `{ "stations": [ { "station_id": ..., "station_name": ..., ... } ] }`
Errors: 401 invalid creds, 403 not owner/manager, 502 upstream.

Use the returned `stations` array to populate the station picker. Then call
`save_vineyard_weather_integration` with the chosen `station_id` /
`station_name`.

### 4.2 Re-test stored credentials — `action: "test_saved"`

```json
{ "vineyardId": "<uuid>", "action": "test_saved" }
```

Updates `last_tested_at` + `last_test_status` server-side and returns:
```json
{
  "success": true,
  "tested_at": "...",
  "status": "ok" | "invalid_credentials" | "http_<n>",
  "message": "Connection successful",
  "station_id": "...",
  "station_name": "...",
  "stations": [...]
}
```

Refresh the status panel by calling `get_vineyard_weather_integration` after
the test.

## 5. Recommended portal flow

1. **Load** — call `get_vineyard_weather_integration(vineyardId, 'davis_weatherlink')`.
   - Empty result → "No Davis integration configured" empty state with a
     "Configure" button (owner/manager only).
   - Otherwise show:
     - Provider, station name + id
     - Configured: `has_api_key && has_api_secret`
     - Sensors: leaf wetness / rain / wind / temp+humidity flags
     - Last tested: `last_tested_at` + `last_test_status`
     - Active toggle from `is_active`
2. **Edit form** (owner/manager): pre-fill station fields. Mask secret fields
   with placeholders like `••••••• (stored)` when `has_api_key` /
   `has_api_secret` are true. Leaving the field blank = keep existing.
3. **Verify** — on submit with new keys, call `davis-proxy` `action: "test"`
   first; only call `save_*` after a successful response.
4. **Save** — call `save_vineyard_weather_integration` with explicit `null`
   for any blank secret field.
5. **Test stored** — show a "Test connection" button that calls
   `davis-proxy` `action: "test_saved"`, then reloads status.
6. **Disable** — toggle `p_is_active`. Don't delete unless the user clicks a
   destructive "Remove credentials" action.
7. **Delete credentials** — separate destructive button →
   `delete_vineyard_weather_integration`.

## 6. What Lovable must NOT do

- ❌ Direct `select` / `insert` / `update` / `delete` on
  `vineyard_weather_integrations`. RLS is locked and grants are revoked —
  these will fail. Use the RPCs.
- ❌ Calling `reveal_vineyard_weather_integration_credentials`.
- ❌ Sending `""` for blank API key / secret fields (it overwrites).
- ❌ Embedding the service-role key.
- ❌ Logging `api_key` / `api_secret` values, even in dev.
- ❌ Showing the credential edit form to operators / supervisors.
- ❌ Proposing schema migrations from the portal. The schema is owned by
  `sql/`.

## 7. Acceptance checklist

Before shipping, the portal must:

- [ ] Read status with `get_vineyard_weather_integration` and surface
      `caller_role` to gate the edit UI.
- [ ] Treat blank secret inputs as `null` (preserve), not `""` (overwrite).
- [ ] Test new credentials with `davis-proxy` `action: "test"` before saving.
- [ ] Test stored credentials with `davis-proxy` `action: "test_saved"` and
      surface `last_test_status`.
- [ ] Use `delete_vineyard_weather_integration` for explicit clear; use
      `p_is_active = false` for soft disable.
- [ ] Never display or transmit raw `api_key` / `api_secret` to the
      browser after save.
- [ ] Hide / disable credential management UI for `operator` and
      `supervisor` roles.

## 8. Duplicate integration audit

The schema should enforce one row per vineyard/provider. This query should
normally return no rows:

```sql
select
  vineyard_id,
  provider,
  count(*) as row_count
from public.vineyard_weather_integrations
group by vineyard_id, provider
having count(*) > 1;
```

Expected result: **No rows.**

If rows are returned, **stop before enabling portal edits** and investigate /
clean duplicates first. The unique constraint on `(vineyard_id, provider)`
should make this impossible — any rows here indicate a schema drift that
needs to be resolved before the portal writes new data.

### Quick status check

Useful read-only snapshot of all configured Davis integrations:

```sql
select
  vineyard_id,
  provider,
  station_id,
  station_name,
  is_active,
  last_tested_at,
  last_test_status,
  updated_at
from public.vineyard_weather_integrations
where provider = 'davis_weatherlink'
order by updated_at desc;
```

> **Important:** never include `api_key` or `api_secret` in audit queries,
> dashboards, or logs. The columns above are the only safe fields to
> surface outside the secure RPC / edge-function path.

---

For the full schema, see [`docs/supabase-schema.md`](./supabase-schema.md)
sections 3.17 and 8.7.
