-- Supabase can load pg-safeupdate for API sessions. It rejects UPDATE without
-- WHERE with SQLSTATE 21000, including statements executed inside triggers.
-- Preserve intentional cross-roster version invalidation and every existing
-- assignment/security rule; do not disable safeupdate or rewrite business data.
create or replace function public.invalidate_roster_versions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'DELETE' then
    if not exists(select 1 from old_roster_inputs) then return null; end if;
  else
    if not exists(select 1 from new_roster_inputs) then return null; end if;
  end if;

  -- Every initialized roster must be invalidated: absences, physician/role
  -- changes and overnight conflicts can affect other months. The schema makes
  -- content_version NOT NULL and positive, so this explicitly targets the same
  -- roster set as before while satisfying safeupdate's required WHERE clause.
  update public.rosters as r
    set content_version = r.content_version + 1
    where r.content_version > 0;
  return null;
end $$;
revoke all on function public.invalidate_roster_versions() from public;
