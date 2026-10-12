-- Optional presentation-only palette token. Old clients may omit it.
alter table public.roles add column color_key text
 check (color_key in ('blue','teal','purple','orange','rose','indigo','green','brown'));
comment on column public.roles.color_key is 'Curated role palette token; null uses deterministic role-ID fallback. No scheduling semantics.';

create or replace function public.admin_save_configuration(p_kind text,p_id uuid,p_expected_updated_at timestamptz,
 p_values jsonb,p_delete boolean,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare access text; actor uuid:=auth.uid(); prior public.admin_workspace_requests%rowtype; payload jsonb;
 r public.roles%rowtype; t public.role_templates%rowtype; result jsonb; stamp timestamptz; k text;
begin
 access:=public.admin_workspace_access(); if access is not null then return jsonb_build_object('error',access); end if;
 perform public.admin_workspace_lock();
 access:=public.admin_workspace_access(); if access is not null then return jsonb_build_object('error',access); end if;
 if p_id is null or p_request_id is null or p_delete is null or p_kind is null or p_kind not in ('roles','templates') or p_values is null or jsonb_typeof(p_values)<>'object' then return jsonb_build_object('error','invalidRequest'); end if;
 payload:=jsonb_build_object('operation','configuration','kind',p_kind,'id',p_id,'version',p_expected_updated_at,'values',p_values,'delete',p_delete);
 select * into prior from public.admin_workspace_requests where actor_id=actor and request_id=p_request_id;
 if found then
  if prior.payload<>payload then return jsonb_build_object('error','idempotencyConflict'); end if;
  return prior.response;
 end if;
 if p_kind='roles' then
  select * into r from public.roles where id=p_id for update;
  if (found and r.updated_at is distinct from p_expected_updated_at) or (not found and p_expected_updated_at is not null) then return jsonb_build_object('error','staleVersion'); end if;
  if p_delete then
   if r.id is null then return jsonb_build_object('error','notFound'); end if;
   if exists(select 1 from public.role_templates where role_id=p_id) or exists(select 1 from public.roster_slots where role_id=p_id)
    or exists(select 1 from public.audit_log where action<>'admin_configuration_change' and (entity_id=p_id or strpos(details::text,p_id::text)>0)) then return jsonb_build_object('error','configurationHasDependencies'); end if;
   delete from public.roles where id=p_id;
  else
   for k in select jsonb_object_keys(p_values) loop
    if k not in ('code','name','is_active','allowed_ranks','required_capabilities','max_doctors','print_in_report','display_order','color_key') then return jsonb_build_object('error','invalidField'); end if;
   end loop;
   r:=jsonb_populate_record(r,p_values);
   if coalesce(btrim(r.code),'')='' or coalesce(btrim(r.name),'')='' or r.max_doctors is null or r.max_doctors<1 or r.allowed_ranks is null or r.required_capabilities is null or r.is_active is null or r.print_in_report is null or r.display_order is null then return jsonb_build_object('error','invalidRequest'); end if;
   insert into public.roles(id,code,name,is_active,allowed_ranks,required_capabilities,max_doctors,print_in_report,display_order,color_key)
   values(p_id,btrim(r.code),btrim(r.name),r.is_active,r.allowed_ranks,r.required_capabilities,r.max_doctors,r.print_in_report,r.display_order,r.color_key)
   on conflict(id) do update set code=excluded.code,name=excluded.name,is_active=excluded.is_active,allowed_ranks=excluded.allowed_ranks,
    required_capabilities=excluded.required_capabilities,max_doctors=excluded.max_doctors,print_in_report=excluded.print_in_report,display_order=excluded.display_order,color_key=excluded.color_key;
  end if;
 else
  select * into t from public.role_templates where id=p_id for update;
  if (found and t.updated_at is distinct from p_expected_updated_at) or (not found and p_expected_updated_at is not null) then return jsonb_build_object('error','staleVersion'); end if;
  if p_delete then
   if t.id is null then return jsonb_build_object('error','notFound'); end if;
   delete from public.role_templates where id=p_id;
  else
   for k in select jsonb_object_keys(p_values) loop
    if k not in ('role_id','weekday_rule','monthly_day','weekdays','start_time','end_time','capacity','is_active') then return jsonb_build_object('error','invalidField'); end if;
   end loop;
   t:=jsonb_populate_record(t,p_values);
   if t.role_id is null or t.weekday_rule is null or t.start_time is null or t.end_time is null or t.end_time<=t.start_time or t.is_active is null or t.capacity is null or t.capacity<1
    or (t.weekday_rule::text='monthly_day' and (t.monthly_day is null or t.monthly_day not between 1 and 31 or t.weekdays is not null))
    or (t.weekday_rule::text<>'monthly_day' and (t.monthly_day is not null or t.weekdays is null or cardinality(t.weekdays)=0)) then return jsonb_build_object('error','invalidRequest'); end if;
   insert into public.role_templates(id,role_id,weekday_rule,monthly_day,weekdays,start_time,end_time,capacity,is_active)
   values(p_id,t.role_id,t.weekday_rule,t.monthly_day,t.weekdays,t.start_time,t.end_time,t.capacity,t.is_active)
   on conflict(id) do update set role_id=excluded.role_id,weekday_rule=excluded.weekday_rule,monthly_day=excluded.monthly_day,weekdays=excluded.weekdays,
    start_time=excluded.start_time,end_time=excluded.end_time,capacity=excluded.capacity,is_active=excluded.is_active;
  end if;
 end if;
 insert into public.audit_log(actor_user_id,action,entity_table,entity_id,details)
 values(actor,'admin_configuration_change',case when p_kind='roles' then 'roles' else 'role_templates' end,p_id,payload);
 result:=jsonb_build_object('success',true,'requestId',p_request_id);
 insert into public.admin_workspace_requests(actor_id,request_id,payload,response) values(actor,p_request_id,payload,result);
 return result;
exception when unique_violation then return jsonb_build_object('error','duplicateCode');
 when foreign_key_violation then return jsonb_build_object('error','configurationHasDependencies');
 when invalid_text_representation or invalid_parameter_value or not_null_violation or check_violation then return jsonb_build_object('error','invalidRequest');
end $$;
revoke all on function public.admin_save_configuration(text,uuid,timestamptz,jsonb,boolean,uuid) from public;
grant execute on function public.admin_save_configuration(text,uuid,timestamptz,jsonb,boolean,uuid) to authenticated;
