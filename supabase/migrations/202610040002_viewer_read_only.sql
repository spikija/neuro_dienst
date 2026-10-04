  -- Restrictive policies also deny writes if a viewer is linked to a doctor.
  -- Existing permissive policies continue to decide what doctors/admins can do.
  create or replace function public.can_write_app_data()
  returns boolean
  language sql
  stable
  security definer
  set search_path = public
  as $$
    select exists (
      select 1 from public.profiles
      where id = auth.uid() and role::text in ('admin', 'doctor')
    );
  $$;

  revoke all on function public.can_write_app_data() from public;
  grant execute on function public.can_write_app_data() to authenticated;

  do $$
  declare
    target_table text;
  begin
    foreach target_table in array array[
      'profiles', 'doctors', 'doctor_enrollment_codes', 'roles', 'role_templates',
      'rosters', 'roster_days', 'roster_slots', 'assignments', 'absences', 'audit_log'
    ] loop
      execute format(
        'create policy "writers only insert" on public.%I as restrictive '
        'for insert to authenticated with check ((select public.can_write_app_data()))',
        target_table
      );
      execute format(
        'create policy "writers only update" on public.%I as restrictive '
        'for update to authenticated using ((select public.can_write_app_data())) '
        'with check ((select public.can_write_app_data()))', target_table
      );
      execute format(
        'create policy "writers only delete" on public.%I as restrictive '
        'for delete to authenticated using ((select public.can_write_app_data()))',
        target_table
      );
    end loop;
  end;
  $$;
