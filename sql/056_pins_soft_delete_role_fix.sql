-- =====================================================================
-- 056 · pins — align soft-delete RPC roles with RLS
-- =====================================================================
-- The RLS update policy on `public.pins` (sql/004) allows members with
-- role owner / manager / supervisor / operator to UPDATE pin rows.
-- The `soft_delete_pin` RPC, however, only allowed
-- owner / manager / supervisor — operators could create and edit pins
-- but their deletes would silently fail server-side with
-- "Insufficient permissions to delete pin". The iOS client soft-deletes
-- locally first, so the device that issued the delete would lose the
-- pin from its view while the row continued to live on the server and
-- on every other device.
--
-- This migration loosens the RPC role check to match the RLS update
-- policy so any member who can edit a pin can also soft-delete it.
-- Hard DELETE remains denied; deletes still go through this RPC which
-- sets `deleted_at`.
-- =====================================================================

create or replace function public.soft_delete_pin(p_pin_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_vineyard_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select vineyard_id into v_vineyard_id
  from public.pins
  where id = p_pin_id;

  if v_vineyard_id is null then
    raise exception 'Pin not found';
  end if;

  if not public.has_vineyard_role(v_vineyard_id, array['owner', 'manager', 'supervisor', 'operator']) then
    raise exception 'Insufficient permissions to delete pin';
  end if;

  update public.pins
  set deleted_at = now(),
      updated_by = auth.uid()
  where id = p_pin_id;
end;
$function$;

revoke all on function public.soft_delete_pin(uuid) from public;
grant execute on function public.soft_delete_pin(uuid) to authenticated;
