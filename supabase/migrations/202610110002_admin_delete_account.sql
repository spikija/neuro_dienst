-- Atomic server-side Auth lifecycle operation. No service-role key in clients.
-- auth.users deletion and its Auth-internal cascades execute in this transaction.
create function public.admin_delete_account(p_kind text,p_id uuid,p_expected_updated_at timestamptz,
 p_acknowledged boolean,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); access text; uid uuid; did uuid; stamp timestamptz; account_role text;
 ref record; dependent boolean; payload jsonb; result jsonb; prior public.admin_workspace_requests%rowtype;
begin
 access:=public.admin_workspace_access(); if access is not null then return jsonb_build_object('error',access); end if;
 perform public.admin_workspace_lock();
 lock table public.audit_log in share row exclusive mode;
 access:=public.admin_workspace_access(); if access is not null then return jsonb_build_object('error',access); end if;
 if p_acknowledged is distinct from true or p_id is null or p_request_id is null or p_expected_updated_at is null or p_kind is null or p_kind not in ('physicians','viewers') then return jsonb_build_object('error','invalidRequest'); end if;
 payload:=jsonb_build_object('operation','deleteAccount','kind',p_kind,'id',p_id,'version',p_expected_updated_at);
 select * into prior from public.admin_workspace_requests where actor_id=actor and request_id=p_request_id;
 if found then
  if prior.payload<>payload then return jsonb_build_object('error','idempotencyConflict'); end if;
  return prior.response;
 end if;
 if p_kind='physicians' then
  select id,auth_user_id,updated_at into did,uid,stamp from public.doctors where id=p_id for update;
 else
  select id,updated_at into uid,stamp from public.profiles where id=p_id and role::text='viewer' for update;
  select id into did from public.doctors where auth_user_id=uid for update;
 end if;
 if stamp is null then return jsonb_build_object('error','notFound'); end if;
 if stamp<>p_expected_updated_at then return jsonb_build_object('error','staleVersion'); end if;
 if uid is not null then
  perform 1 from auth.users where id=uid for update;
  select role::text into account_role from public.profiles where id=uid for update;
  if uid=actor or account_role is null or account_role='admin' or (p_kind='physicians' and account_role<>'doctor') then return jsonb_build_object('error','protectedAccount'); end if;
 end if;
 -- Every scheduling FK is inspected, including cascades and future references.
 -- Auth internal identities/sessions are part of the account being removed.
 for ref in
  select c.conrelid::regclass relation,a.attname,c.confrelid target,cardinality(c.conkey) columns
  from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=cl.relnamespace
  join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
  where c.contype='f' and n.nspname<>'auth' and c.confrelid in ('public.doctors'::regclass,'public.profiles'::regclass,'auth.users'::regclass)
   and not (c.confrelid='auth.users'::regclass and ((c.conrelid='public.profiles'::regclass and a.attname='id') or (c.conrelid='public.doctors'::regclass and a.attname='auth_user_id')))
 loop
  if ref.columns<>1 then
   return jsonb_build_object('error','accountHasDependencies');
  end if;
  execute format('select exists(select 1 from %s where %I=$1)',ref.relation,ref.attname)
   into dependent using case when ref.target='public.doctors'::regclass then did else uid end;
  if dependent then return jsonb_build_object('error','accountHasDependencies'); end if;
 end loop;
 -- UUIDs in factual audit/receipt JSON are not represented by foreign keys.
 if exists(select 1 from public.audit_log where entity_id in (did,uid) or actor_user_id=uid
   or (did is not null and strpos(details::text,did::text)>0) or (uid is not null and strpos(details::text,uid::text)>0))
  or exists(select 1 from public.admin_assignment_requests where (did is not null and strpos(to_jsonb(admin_assignment_requests)::text,did::text)>0) or (uid is not null and strpos(to_jsonb(admin_assignment_requests)::text,uid::text)>0))
  or exists(select 1 from public.admin_workspace_requests where (did is not null and strpos(admin_workspace_requests.payload::text,did::text)>0) or (uid is not null and strpos(admin_workspace_requests.payload::text,uid::text)>0)) then
  return jsonb_build_object('error','accountHasDependencies'); end if;
 -- Storage ownership may not have an FK in newer Supabase projects.
 if uid is not null and exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner_id') then
  execute 'select exists(select 1 from storage.objects where owner_id=$1)' into dependent using uid::text;
  if dependent then return jsonb_build_object('error','accountHasDependencies'); end if;
 end if;
 delete from public.doctors where id=did;
 delete from public.profiles where id=uid;
 delete from auth.users where id=uid;
 -- Minimal tombstone, no credentials or email. Audit failure rolls back Auth too.
 insert into public.audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(actor,'admin_delete_account',case when p_kind='physicians' then 'doctors' else 'profiles' end,p_id,
  jsonb_build_object('requestId',p_request_id,'physicianId',did,'userId',uid));
 result:=jsonb_build_object('success',true,'requestId',p_request_id);
 insert into public.admin_workspace_requests(actor_id,request_id,payload,response) values(actor,p_request_id,payload,result);
 return result;
exception when foreign_key_violation then return jsonb_build_object('error','accountHasDependencies');
end $$;
revoke all on function public.admin_delete_account(text,uuid,timestamptz,boolean,uuid) from public;
grant execute on function public.admin_delete_account(text,uuid,timestamptz,boolean,uuid) to authenticated;
