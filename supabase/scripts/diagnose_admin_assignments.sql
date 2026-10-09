-- Run in the Supabase SQL editor and share the result for diagnosis.
-- Read-only catalog inspection: no assignments, personal data, JWTs or keys.
begin read only;

select jsonb_pretty(jsonb_build_object(
  'postgres_version', current_setting('server_version'),
  'rpc', (
    select jsonb_build_object(
      'owner', pg_get_userbyid(p.proowner),
      'security_definer', p.prosecdef,
      'settings', p.proconfig,
      'body_md5', md5(p.prosrc),
      'owner_can_lock_tables', (
        select jsonb_object_agg(t.relname,
          has_table_privilege(p.proowner,t.oid,'UPDATE'))
        from pg_class t join pg_namespace n on n.oid=t.relnamespace
        where n.nspname='public' and t.relname in
          ('profiles','doctors','roles','absences','rosters','roster_days',
           'roster_slots','assignments','admin_assignment_requests')
      )
    )
    from pg_proc p
    where p.oid=to_regprocedure('public.admin_apply_assignments(uuid,bigint,uuid,uuid,date[],uuid,text)')
  ),
  'columns', (
    select jsonb_agg(jsonb_build_object(
      'table', table_name, 'column', column_name, 'type', udt_name,
      'nullable', is_nullable, 'default', column_default
    ) order by table_name,ordinal_position)
    from information_schema.columns
    where table_schema='public' and table_name in
      ('profiles','doctors','roles','absences','rosters','roster_days',
       'roster_slots','assignments','audit_log','admin_assignment_requests')
  ),
  'triggers', (
    select jsonb_agg(jsonb_build_object(
      'table',c.relname,'name',t.tgname,'enabled',t.tgenabled,
      'definition',pg_get_triggerdef(t.oid),
      'function',t.tgfoid::regprocedure::text,
      'function_body_md5',md5(p.prosrc)
    ) order by c.relname,t.tgname)
    from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace
      join pg_proc p on p.oid=t.tgfoid
    where not t.tgisinternal and n.nspname='public' and c.relname in
      ('profiles','doctors','roles','absences','rosters','roster_days',
       'roster_slots','assignments','audit_log','admin_assignment_requests')
  ),
  'constraints', (
    select jsonb_agg(jsonb_build_object(
      'table',c.relname,'name',k.conname,'definition',pg_get_constraintdef(k.oid)
    ) order by c.relname,k.conname)
    from pg_constraint k join pg_class c on c.oid=k.conrelid
      join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in
      ('assignments','audit_log','admin_assignment_requests','rosters')
  )
)) as assignment_diagnostics;

rollback;
