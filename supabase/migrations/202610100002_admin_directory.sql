-- Administrator directory commands. Auth credentials remain server-side.
-- Revocation is checked by RLS on every request, including existing JWTs.
alter table public.profiles add column access_revoked boolean not null default false;

-- Legacy tables had default timestamps but no automatic update stamp.
create function public.stamp_directory_update() returns trigger
language plpgsql set search_path = '' as $$ begin
 new.updated_at:=greatest(clock_timestamp(),old.updated_at+interval '1 microsecond');
 return new;
end $$;
create trigger stamp_directory_update before update on public.doctors for each row execute function public.stamp_directory_update();
create trigger stamp_directory_update before update on public.profiles for each row execute function public.stamp_directory_update();

create function public.has_app_access() returns boolean
language sql stable security definer set search_path = '' as $$
 select not exists(select 1 from public.profiles where id=auth.uid() and access_revoked);
$$;
revoke all on function public.has_app_access() from public;
grant execute on function public.has_app_access() to authenticated;
do $$ declare t record; begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind='r' and c.relrowsecurity loop
   execute format('create policy "revoked accounts denied" on public.%I as restrictive for all to authenticated using ((select public.has_app_access())) with check ((select public.has_app_access()))',t.relname);
 end loop;
end $$;

-- Guards even legacy/mobile deletes, including ON DELETE CASCADE relationships.
-- Future single-column foreign keys are covered automatically.
create function public.protect_physician_history() returns trigger
language plpgsql security definer set search_path = '' as $$
declare ref record; dependent boolean;
begin
 for ref in select c.conrelid::regclass as relation, a.attname
   from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
   where c.contype='f' and c.confrelid='public.doctors'::regclass loop
   execute format('select exists(select 1 from %s where %I=$1)',ref.relation,ref.attname) into dependent using old.id;
   if dependent then raise exception using errcode='23503', message='physicianHasDependencies'; end if;
 end loop;
 if exists(select 1 from public.audit_log where entity_table='doctors' and entity_id=old.id) then
   raise exception using errcode='23503', message='physicianHasDependencies';
 end if;
 return old;
end $$;
revoke all on function public.protect_physician_history() from public;
create trigger protect_physician_history before delete on public.doctors
 for each row execute function public.protect_physician_history();

create function public.admin_directory(p_kind text,p_offset int default 0,p_limit int default 500)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb; begin
 if public.admin_workspace_access() is not null then raise exception using errcode='42501',message='adminAal2Required'; end if;
 if p_offset<0 or p_limit<1 or p_limit>500 then raise exception using errcode='22023',message='invalidPage'; end if;
 if p_kind='physicians' then
   select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from (
     select d.*,u.email,p.role::text as account_role from public.doctors d
     left join auth.users u on u.id=d.auth_user_id left join public.profiles p on p.id=d.auth_user_id
     where p.role is null or p.role::text<>'viewer'
     order by d.id offset p_offset limit p_limit) q;
 elsif p_kind='viewers' then
   select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into result from (
     select p.id,p.display_name,p.preferred_language,p.access_revoked,p.updated_at,u.email
     from public.profiles p left join auth.users u on u.id=p.id where p.role::text='viewer'
     order by p.id offset p_offset limit p_limit) q;
 else raise exception using errcode='22023',message='invalidDirectory'; end if;
 return result;
end $$;
revoke all on function public.admin_directory(text,int,int) from public;
grant execute on function public.admin_directory(text,int,int) to authenticated;

create function public.admin_manage_directory(p_kind text,p_id uuid,p_expected_updated_at timestamptz,
 p_changes jsonb,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); access text; payload jsonb; prior public.admin_workspace_requests%rowtype;
 physician public.doctors%rowtype; profile public.profiles%rowtype; result jsonb; k text;
begin
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('error',access); end if;
 perform public.admin_workspace_lock();
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('error',access); end if;
 if p_id is null or p_request_id is null or p_expected_updated_at is null or jsonb_typeof(p_changes)<>'object' or p_changes is null then
   return jsonb_build_object('error','invalidRequest'); end if;
 payload:=jsonb_build_object('kind',p_kind,'id',p_id,'version',p_expected_updated_at,'changes',p_changes);
 select * into prior from public.admin_workspace_requests where actor_id=actor and request_id=p_request_id;
 if found then
   if prior.payload<>payload then return jsonb_build_object('error','idempotencyConflict'); end if;
   return prior.response;
 end if;
 if p_kind='physicians' then
   select * into physician from public.doctors where id=p_id for update;
   if not found then return jsonb_build_object('error','notFound'); end if;
   if exists(select 1 from public.profiles where id=physician.auth_user_id and role::text='viewer') then return jsonb_build_object('error','viewerNotPhysician'); end if;
   if physician.updated_at<>p_expected_updated_at then return jsonb_build_object('error','staleVersion'); end if;
   for k in select jsonb_object_keys(p_changes) loop
     if k not in ('first_name','last_name','rank','capabilities','is_active','print_order','delete') then return jsonb_build_object('error','invalidField'); end if;
   end loop;
   if p_changes->>'delete'='true' then
     if p_changes<>'{"delete":true}'::jsonb then return jsonb_build_object('error','invalidRequest'); end if;
     -- The trigger inspects all FK dependencies before any cascade can run.
     delete from public.doctors where id=p_id;
   else
     if p_changes ? 'first_name' then physician.first_name:=btrim(p_changes->>'first_name'); end if;
     if p_changes ? 'last_name' then physician.last_name:=btrim(p_changes->>'last_name'); end if;
     if p_changes ? 'rank' then physician.rank:=(p_changes->>'rank')::public.doctor_rank; end if;
     if p_changes ? 'capabilities' then select array_agg(v::public.capability) into physician.capabilities from jsonb_array_elements_text(p_changes->'capabilities') v; physician.capabilities:=coalesce(physician.capabilities,'{}'); end if;
     if p_changes ? 'is_active' then physician.is_active:=(p_changes->>'is_active')::boolean; end if;
     if p_changes ? 'print_order' then physician.print_order:=(p_changes->>'print_order')::int; end if;
     if coalesce(physician.first_name,'')='' or coalesce(physician.last_name,'')='' or physician.is_active is null or physician.rank is null or physician.print_order is null then return jsonb_build_object('error','invalidRequest'); end if;
     update public.doctors set first_name=physician.first_name,last_name=physician.last_name,
       rank=physician.rank,capabilities=physician.capabilities,is_active=physician.is_active,print_order=physician.print_order where id=p_id;
   end if;
 elsif p_kind='viewers' then
   select * into profile from public.profiles where id=p_id and role::text='viewer' for update;
   if not found then return jsonb_build_object('error','notFound'); end if;
   if profile.updated_at<>p_expected_updated_at then return jsonb_build_object('error','staleVersion'); end if;
   for k in select jsonb_object_keys(p_changes) loop
     if k not in ('display_name','preferred_language','access_revoked') then return jsonb_build_object('error','invalidField'); end if;
   end loop;
   if p_changes ? 'display_name' then profile.display_name:=btrim(p_changes->>'display_name'); end if;
   if p_changes ? 'preferred_language' then profile.preferred_language:=p_changes->>'preferred_language'; end if;
   if p_changes ? 'access_revoked' then profile.access_revoked:=(p_changes->>'access_revoked')::boolean; end if;
   if coalesce(profile.display_name,'')='' or profile.preferred_language is null or profile.preferred_language not in ('en','de') or profile.access_revoked is null then return jsonb_build_object('error','invalidRequest'); end if;
   update public.profiles set display_name=profile.display_name,preferred_language=profile.preferred_language,access_revoked=profile.access_revoked where id=p_id;
 else return jsonb_build_object('error','invalidDirectory'); end if;
 insert into public.audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(actor,'admin_directory_change',case p_kind when 'physicians' then 'doctors' else 'profiles' end,p_id,jsonb_build_object('requestId',p_request_id,'changes',p_changes));
 result:=jsonb_build_object('success',true,'requestId',p_request_id);
 insert into public.admin_workspace_requests(actor_id,request_id,payload,response) values(actor,p_request_id,payload,result);
 return result;
exception when foreign_key_violation then return jsonb_build_object('error','physicianHasDependencies');
 when invalid_text_representation or invalid_parameter_value or not_null_violation or check_violation then return jsonb_build_object('error','invalidRequest');
end $$;
revoke all on function public.admin_manage_directory(text,uuid,timestamptz,jsonb,uuid) from public;
grant execute on function public.admin_manage_directory(text,uuid,timestamptz,jsonb,uuid) to authenticated;
