-- 038_trips_seeding_details.sql
--
-- Adds optional seeding_details JSONB column to public.trips.
--
-- Context:
--   - Used when trip_function = 'seeding' (built-in TripFunction).
--   - All fields are OPTIONAL. The column is nullable, has no default,
--     and existing rows are not backfilled.
--   - Older clients that do not know about seeding_details will still
--     read/write trips safely; they will simply ignore this column.
--
-- IMPORTANT — preservation risk:
--   If an older iOS client re-upserts a full trip row WITHOUT including
--   seeding_details, a naive UPSERT could overwrite the existing JSON
--   with NULL. Mitigation is handled at the client layer (BackendTrip
--   upsert preserves seeding_details unless the current client is
--   intentionally writing it). This migration documents the risk only;
--   no DB-level trigger is added at this stage to keep the change small.
--
-- Expected JSON shape (all keys optional):
--   {
--     "front_box": {
--       "mix_name": "",
--       "rate_per_ha": null,
--       "shutter_slide": "3/4" | "Full",
--       "bottom_flap": "1" | "3",
--       "metering_wheel": "N" | "F",
--       "seed_volume_kg": null,
--       "gearbox_setting": null
--     },
--     "back_box": { ...same shape as front_box... },
--     "sowing_depth_cm": null,
--     "mix_lines": [
--       {
--         "name": "",
--         "percent_of_mix": null,
--         "seed_box": "Front" | "Back",
--         "kg_per_ha": null,
--         "supplier_manufacturer": ""
--       }
--     ]
--   }
--
-- No RLS changes: existing trips RLS already governs access to this column.

begin;

-- 1. Add the column (idempotent).
alter table public.trips
  add column if not exists seeding_details jsonb null;

comment on column public.trips.seeding_details is
  'Optional seeding job details. Normally populated only when trip_function = ''seeding''. '
  'Schema: front_box{mix_name,rate_per_ha,shutter_slide,bottom_flap,metering_wheel,seed_volume_kg,gearbox_setting}, '
  'back_box{...same...}, sowing_depth_cm, mix_lines[{name,percent_of_mix,seed_box,kg_per_ha,supplier_manufacturer}]. '
  'All fields optional. Older clients should preserve existing values on upsert.';

-- 2. Optional GIN index for future reporting/filtering on seeding_details.
--    Partial index keeps it small (only seeding trips with details populated).
create index if not exists idx_trips_seeding_details_gin
  on public.trips
  using gin (seeding_details)
  where seeding_details is not null;

commit;

-- ---------------------------------------------------------------------------
-- Smoke-test queries (run manually after migration):
--
-- 1. Confirm column exists:
--   select column_name, data_type, is_nullable
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name = 'trips'
--     and column_name = 'seeding_details';
--
-- 2. Confirm index exists:
--   select indexname, indexdef
--   from pg_indexes
--   where schemaname = 'public'
--     and tablename = 'trips'
--     and indexname = 'idx_trips_seeding_details_gin';
--
-- 3. Confirm no rows were backfilled:
--   select count(*) as total_trips,
--          count(seeding_details) as trips_with_seeding_details
--   from public.trips;
--
-- 4. Sample write (replace <trip_id>):
--   update public.trips
--   set seeding_details = jsonb_build_object(
--     'front_box', jsonb_build_object('mix_name','Test mix','rate_per_ha',25),
--     'sowing_depth_cm', 2.5,
--     'mix_lines', jsonb_build_array(
--       jsonb_build_object('name','Ryegrass','percent_of_mix',60,'seed_box','Front','kg_per_ha',15,'supplier_manufacturer','Acme')
--     )
--   )
--   where id = '<trip_id>';
--
-- 5. Sample read:
--   select id, trip_function, seeding_details->'front_box'->>'mix_name' as front_mix
--   from public.trips
--   where seeding_details is not null
--   limit 10;
-- ---------------------------------------------------------------------------
