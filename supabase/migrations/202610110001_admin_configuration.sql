-- Generic configuration, retaining legacy recurrence for old/mobile rows.
alter table public.role_templates add column is_active boolean not null default true,
 add column weekdays integer[], add column capacity integer check(capacity>0),
 add column updated_at timestamptz not null default now();
alter table public.role_templates add constraint template_weekdays_check
 check(weekdays is null or (cardinality(weekdays) between 1 and 7 and weekdays <@ array[1,2,3,4,5,6,7] and array_position(weekdays,null) is null));
create trigger stamp_configuration_update before update on public.roles for each row execute function public.stamp_directory_update();
create trigger stamp_configuration_update before update on public.role_templates for each row execute function public.stamp_directory_update();

-- Deleted/revoked identities cannot keep table access through an unexpired JWT.
create or replace function public.has_app_access() returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where id=auth.uid() and not access_revoked);
$$;

create function public.admin_configuration() returns jsonb
language plpgsql security definer set search_path = '' as $$ begin
 if public.admin_workspace_access() is not null then raise exception using errcode='42501',message='adminAal2Required'; end if;
 return jsonb_build_object('roles',(select coalesce(jsonb_agg(to_jsonb(r) order by r.display_order,r.code),'[]') from public.roles r),
 'templates',(select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]') from public.role_templates t));
end $$;
revoke all on function public.admin_configuration() from public;
grant execute on function public.admin_configuration() to authenticated;

create function public.admin_save_configuration(p_kind text,p_id uuid,p_expected_updated_at timestamptz,
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
    if k not in ('code','name','is_active','allowed_ranks','required_capabilities','max_doctors','print_in_report','display_order') then return jsonb_build_object('error','invalidField'); end if;
   end loop;
   r:=jsonb_populate_record(r,p_values);
   if coalesce(btrim(r.code),'')='' or coalesce(btrim(r.name),'')='' or r.max_doctors is null or r.max_doctors<1 or r.allowed_ranks is null or r.required_capabilities is null or r.is_active is null or r.print_in_report is null or r.display_order is null then return jsonb_build_object('error','invalidRequest'); end if;
   insert into public.roles(id,code,name,is_active,allowed_ranks,required_capabilities,max_doctors,print_in_report,display_order)
   values(p_id,btrim(r.code),btrim(r.name),r.is_active,r.allowed_ranks,r.required_capabilities,r.max_doctors,r.print_in_report,r.display_order)
   on conflict(id) do update set code=excluded.code,name=excluded.name,is_active=excluded.is_active,allowed_ranks=excluded.allowed_ranks,
    required_capabilities=excluded.required_capabilities,max_doctors=excluded.max_doctors,print_in_report=excluded.print_in_report,display_order=excluded.display_order;
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

create or replace function public.admin_generation_plan(p_year int,p_month int,p_roster_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' set timezone = 'UTC' as $$
declare first_date date; last_date date; roster public.rosters%rowtype; days jsonb;
 slots jsonb; removed jsonb; affected jsonb; cfg jsonb; blockers jsonb:='[]'; config_version text;
begin
 first_date:=make_date(p_year,p_month,1); last_date:=(first_date+interval '1 month'-interval '1 day')::date;
 select * into roster from public.rosters where year=p_year and month=p_month;
 if p_roster_id is null and found then blockers:=blockers||'"monthExists"'::jsonb;
 elsif p_roster_id is not null and (roster.id is null or roster.id<>p_roster_id) then blockers:=blockers||'"rosterNotFound"'::jsonb;
 elsif p_roster_id is not null and roster.phase<>'draft' then blockers:=blockers||'"draftRequired"'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object('templateId',t.id,'roleId',r.id,'code',r.code,'name',r.name,
 'weekdayRule',t.weekday_rule,'monthlyDay',t.monthly_day,'start',t.start_time,'end',t.end_time,'capacity',coalesce(t.capacity,r.max_doctors),'weekdays',t.weekdays) order by t.id),'[]')
 into cfg from public.role_templates t join public.roles r on r.id=t.role_id where r.is_active and t.is_active;
 config_version:=md5(cfg::text||'AT-national-gregorian-v1');
 if exists(select 1 from public.role_templates t join public.roles r on r.id=t.role_id
 where r.is_active and t.is_active and t.weekday_rule='monthly_day' and t.monthly_day is null) then blockers:=blockers||'"invalidMonthlyDay"'::jsonb; end if;
 select jsonb_agg(jsonb_build_object('date',d,'isWeekend',extract(isodow from d)>5,
 'holidayName',public.austrian_holiday(d)) order by d) into days
 from (select first_date+n as d from generate_series(0,last_date-first_date) n) dates;
 with desired as (
 select d,t.id template_id,t.role_id,(d+t.start_time) at time zone 'Europe/Vienna' starts_at,
 (d+t.end_time) at time zone 'Europe/Vienna' ends_at,coalesce(t.capacity,r.max_doctors) max_doctors
 from (select first_date+n d from generate_series(0,last_date-first_date) n) dates
 cross join public.role_templates t join public.roles r on r.id=t.role_id and r.is_active
 where t.is_active and case when t.weekday_rule::text='monthly_day' then extract(day from d)=t.monthly_day when t.weekdays is not null then extract(isodow from d)::int=any(t.weekdays) else case t.weekday_rule::text when 'every_weekday' then extract(isodow from d)<=5
 when 'monday_only' then extract(isodow from d)=1 when 'tuesday_only' then extract(isodow from d)=2
 when 'wednesday_only' then extract(isodow from d)=3 when 'thursday_only' then extract(isodow from d)=4
 when 'friday_only' then extract(isodow from d)=5 when 'monthly_day' then extract(day from d)=t.monthly_day else false end end
 ), numbered as (select *,row_number() over(partition by d,role_id,starts_at,ends_at,max_doctors order by template_id) occurrence from desired),
 existing as (select s.*,rd.date,row_number() over(partition by rd.date,s.role_id,s.starts_at,s.ends_at,s.max_doctors order by s.id) occurrence
 from public.roster_slots s join public.roster_days rd on rd.id=s.roster_day_id where rd.roster_id=p_roster_id)
 select coalesce(jsonb_agg(jsonb_build_object('date',n.d,'templateId',n.template_id,'roleId',n.role_id,
 'startsAt',n.starts_at,'endsAt',n.ends_at,'capacity',n.max_doctors,'existingSlotId',e.id) order by n.d,n.template_id),'[]') into slots
 from numbered n left join existing e on e.date=n.d and e.role_id=n.role_id and e.starts_at=n.starts_at and e.ends_at=n.ends_at
 and e.max_doctors=n.max_doctors and e.occurrence=n.occurrence;
 -- A monthly-day template can hit a DST gap/fold. Never normalize it silently.
 if exists(select 1 from jsonb_array_elements(slots) s join public.role_templates t on t.id=(s->>'templateId')::uuid
 cross join lateral (values ((s->>'startsAt')::timestamptz,(s->>'date')::date+t.start_time),
 ((s->>'endsAt')::timestamptz,(s->>'date')::date+t.end_time)) clocks(instant,wall)
 where instant at time zone 'Europe/Vienna'<>wall
 or (instant+interval '1 hour') at time zone 'Europe/Vienna'=wall
 or (instant-interval '1 hour') at time zone 'Europe/Vienna'=wall) then
 blockers:=blockers||'"ambiguousOrMissingWallTime"'::jsonb; end if;
 select coalesce(jsonb_agg(s.id order by s.id),'[]') into removed from public.roster_slots s join public.roster_days d on d.id=s.roster_day_id
 where d.roster_id=p_roster_id and not exists(select 1 from jsonb_array_elements(slots) item where item->>'existingSlotId'=s.id::text);
 select coalesce(jsonb_agg(a.id order by a.id),'[]') into affected from public.assignments a where a.roster_slot_id in
 (select value::uuid from jsonb_array_elements_text(removed));
 if jsonb_array_length(affected)>0 then blockers:=blockers||'"assignmentLoss"'::jsonb; end if;
 return jsonb_build_object('year',p_year,'month',p_month,'rosterId',p_roster_id,'existingVersion',case when p_roster_id is not null then roster.content_version end,
 'configurationVersion',config_version,'templates',cfg,'days',days,'slots',slots,'removedSlotIds',removed,'impactedAssignmentIds',affected,
 'blockers',blockers,'holidaySource','AT-national-gregorian-v1');
end $$;
revoke all on function public.admin_generation_plan(int,int,uuid) from public;
