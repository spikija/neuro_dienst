-- Forward-only administrator workspace. No existing rows or policies changed.
-- Calendar source: Austrian nationwide statutory holidays, Gregorian Easter.
create function public.austrian_holiday(p_date date) returns text
language plpgsql immutable set search_path = '' as $$
declare y int := extract(year from p_date); a int; b int; c int; d int; e int;
 f int; g int; h int; i int; k int; l int; m int; n int; easter date; fixed text;
begin
 fixed := case to_char(p_date,'MM-DD')
 when '01-01' then 'Neujahr' when '01-06' then 'Heilige Drei Könige'
 when '05-01' then 'Staatsfeiertag' when '08-15' then 'Mariä Himmelfahrt'
 when '10-26' then 'Nationalfeiertag' when '11-01' then 'Allerheiligen'
 when '12-08' then 'Mariä Empfängnis' when '12-25' then 'Christtag'
 when '12-26' then 'Stefanitag' end;
 a:=y%19; b:=y/100; c:=y%100; d:=b/4; e:=b%4; f:=(b+8)/25;
 g:=(b-f+1)/3; h:=(19*a+b-d-g+15)%30; i:=c/4; k:=c%4;
 l:=(32+2*e+2*i-h-k)%7; m:=(a+11*h+22*l)/451; n:=h+l-7*m+114;
 easter:=make_date(y,n/31,n%31+1);
 return nullif(concat_ws('; ',fixed,case p_date-easter when 1 then 'Ostermontag' when 39 then 'Christi Himmelfahrt'
 when 50 then 'Pfingstmontag' when 60 then 'Fronleichnam' end),'');
end $$;

create table public.admin_workspace_requests (
 actor_id uuid not null references auth.users(id), request_id uuid not null,
 payload jsonb not null, response jsonb not null, created_at timestamptz not null default now(),
 primary key(actor_id,request_id)
);
alter table public.admin_workspace_requests enable row level security;
revoke all on public.admin_workspace_requests from public, authenticated;

create function public.admin_workspace_access() returns text
language sql stable security definer set search_path = '' as $$
 select case when auth.uid() is null or not exists(select 1 from public.profiles
 where id=auth.uid() and role::text='admin') then 'unauthorized'
 when coalesce(auth.jwt()->>'aal','')<>'aal2' then 'mfaRequired' end;
$$;
revoke all on function public.admin_workspace_access() from public;

-- Lock order matches the existing assignment RPC, then adds templates/receipts.
create function public.admin_workspace_lock() returns void
language plpgsql security definer set search_path = '' as $$ begin
 lock table public.profiles, public.doctors, public.roles, public.absences,
 public.rosters, public.roster_days, public.roster_slots, public.assignments,
 public.admin_assignment_requests, public.role_templates, public.admin_workspace_requests
 in share row exclusive mode;
end $$;
revoke all on function public.admin_workspace_lock() from public;

create function public.admin_remove_assignments(p_roster_id uuid, p_expected_version bigint,
 p_dates date[], p_scope text, p_role_id uuid, p_request_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); access text; roster public.rosters%rowtype;
 dates date[]; reason text:=nullif(btrim(p_reason),''); payload jsonb; prior public.admin_workspace_requests%rowtype;
 removed jsonb; response jsonb; ids uuid[]; v bigint;
begin
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('ok',false,'code',access); end if;
 if p_request_id is null or p_expected_version is null or p_expected_version<1 or p_roster_id is null
 or p_scope is null or p_scope not in ('role','all') or (p_scope='role' and p_role_id is null)
 or (p_scope='all' and p_role_id is not null) or coalesce(cardinality(p_dates),0) not between 1 and 31
 or exists(select 1 from unnest(p_dates) d where d is null)
 or (select count(distinct d) from unnest(p_dates) d)<>cardinality(p_dates) then
 return jsonb_build_object('ok',false,'code','invalidRequest'); end if;
 select array_agg(d order by d) into dates from unnest(p_dates) d;
 payload:=jsonb_build_object('operation','remove','roster',p_roster_id,'version',p_expected_version,
 'dates',dates,'scope',p_scope,'role',p_role_id,'reason',reason);
 perform public.admin_workspace_lock();
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('ok',false,'code',access); end if;
 select * into prior from public.admin_workspace_requests where actor_id=actor and request_id=p_request_id;
 if found then
 if prior.payload<>payload then return jsonb_build_object('ok',false,'code','idempotencyConflict'); end if;
 return prior.response; end if;
 select * into roster from public.rosters where id=p_roster_id;
 if not found or roster.content_version<>p_expected_version then return jsonb_build_object('ok',false,'code','staleVersion'); end if;
 if roster.phase='published' or (roster.phase='locked' and reason is null) then
 return jsonb_build_object('ok',false,'code','rosterNotEditable'); end if;
 if exists(select 1 from unnest(dates) d where extract(year from d)<>roster.year or extract(month from d)<>roster.month) then
 return jsonb_build_object('ok',false,'code','invalidDate'); end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'slotId',s.id,'roleId',s.role_id,
 'physicianId',a.doctor_id,'date',d.date,'oldState',a.state) order by d.date,a.id),'[]'), array_agg(a.id)
 into removed,ids from public.assignments a join public.roster_slots s on s.id=a.roster_slot_id
 join public.roster_days d on d.id=s.roster_day_id where d.roster_id=p_roster_id and d.date=any(dates)
 and (p_scope='all' or s.role_id=p_role_id);
 delete from public.assignments where id=any(coalesce(ids,'{}'));
 insert into public.audit_log(actor_user_id,action,entity_table,entity_id,details)
 select actor,'admin_remove_assignment','assignments',(item->>'id')::uuid,
 item||jsonb_build_object('requestId',p_request_id,'rosterId',p_roster_id,'reason',reason,'newState',null,'scope',p_scope)
 from jsonb_array_elements(removed) item;
 select content_version into v from public.rosters where id=p_roster_id;
 response:=jsonb_build_object('ok',true,'requestId',p_request_id,'rosterId',p_roster_id,'contentVersion',v,'removedAssignments',removed);
 insert into public.admin_workspace_requests(actor_id,request_id,payload,response) values(actor,p_request_id,payload,response);
 return response;
exception when others then
 raise log 'admin_remove_assignments failure sqlstate=%', SQLSTATE;
 return jsonb_build_object('ok',false,'code','internalError');
end $$;

-- Deterministic server plan. Exact slot matches keep identities/assignments.
-- Recurrence retains mobile semantics: weekdays include holidays; holidays are
-- metadata and working-day selection excludes them. Monthly days may be weekends.
create function public.admin_generation_plan(p_year int,p_month int,p_roster_id uuid default null)
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
 'weekdayRule',t.weekday_rule,'monthlyDay',t.monthly_day,'start',t.start_time,'end',t.end_time,'capacity',r.max_doctors) order by t.id),'[]')
 into cfg from public.role_templates t join public.roles r on r.id=t.role_id where r.is_active;
 config_version:=md5(cfg::text||'AT-national-gregorian-v1');
 if exists(select 1 from public.role_templates t join public.roles r on r.id=t.role_id
 where r.is_active and t.weekday_rule='monthly_day' and t.monthly_day is null) then blockers:=blockers||'"invalidMonthlyDay"'::jsonb; end if;
 select jsonb_agg(jsonb_build_object('date',d,'isWeekend',extract(isodow from d)>5,
 'holidayName',public.austrian_holiday(d)) order by d) into days
 from (select first_date+n as d from generate_series(0,last_date-first_date) n) dates;
 with desired as (
 select d,t.id template_id,t.role_id,(d+t.start_time) at time zone 'Europe/Vienna' starts_at,
 (d+t.end_time) at time zone 'Europe/Vienna' ends_at,r.max_doctors
 from (select first_date+n d from generate_series(0,last_date-first_date) n) dates
 cross join public.role_templates t join public.roles r on r.id=t.role_id and r.is_active
 where case t.weekday_rule::text when 'every_weekday' then extract(isodow from d)<=5
 when 'monday_only' then extract(isodow from d)=1 when 'tuesday_only' then extract(isodow from d)=2
 when 'wednesday_only' then extract(isodow from d)=3 when 'thursday_only' then extract(isodow from d)=4
 when 'friday_only' then extract(isodow from d)=5 when 'monthly_day' then extract(day from d)=t.monthly_day else false end
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

create function public.admin_preview_generation(p_year int,p_month int,p_roster_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare access text; plan jsonb;
begin
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('ok',false,'code',access); end if;
 if p_year is null or p_year not between 2000 and 2100 or p_month is null or p_month not between 1 and 12 then
 return jsonb_build_object('ok',false,'code','invalidMonth'); end if;
 perform public.admin_workspace_lock();
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('ok',false,'code',access); end if;
 plan:=public.admin_generation_plan(p_year,p_month,p_roster_id);
 return jsonb_build_object('ok',true,'plan',plan,'token',md5(plan::text));
end $$;

create function public.admin_apply_generation(p_year int,p_month int,p_roster_id uuid,
 p_expected_version bigint,p_token text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare access text; actor uuid:=auth.uid(); plan jsonb; payload jsonb; prior public.admin_workspace_requests%rowtype;
 rid uuid; v bigint; response jsonb;
begin
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('ok',false,'code',access); end if;
 if p_request_id is null or p_token is null or p_year is null or p_year not between 2000 and 2100 or p_month is null or p_month not between 1 and 12 then
 return jsonb_build_object('ok',false,'code','invalidRequest'); end if;
 payload:=jsonb_build_object('operation','generate','year',p_year,'month',p_month,'roster',p_roster_id,'version',p_expected_version,'token',p_token);
 perform public.admin_workspace_lock();
 access:=public.admin_workspace_access();
 if access is not null then return jsonb_build_object('ok',false,'code',access); end if;
 select * into prior from public.admin_workspace_requests where actor_id=actor and request_id=p_request_id;
 if found then
 if prior.payload<>payload then return jsonb_build_object('ok',false,'code','idempotencyConflict'); end if;
 return prior.response; end if;
 plan:=public.admin_generation_plan(p_year,p_month,p_roster_id);
 if jsonb_array_length(plan->'blockers')>0 then return jsonb_build_object('ok',false,'code','generationBlocked','blockers',plan->'blockers'); end if;
 if md5(plan::text)<>p_token or (p_roster_id is not null and ((plan->>'existingVersion')::bigint is distinct from p_expected_version)) then
 return jsonb_build_object('ok',false,'code','staleVersion'); end if;
 rid:=p_roster_id;
 if rid is null then insert into public.rosters(year,month,phase,created_by) values(p_year,p_month,'draft',actor) returning id into rid; end if;
 insert into public.roster_days(roster_id,date,is_weekend,is_public_holiday,public_holiday_name)
 select rid,(d->>'date')::date,(d->>'isWeekend')::boolean,d->>'holidayName' is not null,d->>'holidayName'
 from jsonb_array_elements(plan->'days') d
 on conflict(roster_id,date) do update set is_weekend=excluded.is_weekend,is_public_holiday=excluded.is_public_holiday,public_holiday_name=excluded.public_holiday_name;
 delete from public.roster_slots where id in(select value::uuid from jsonb_array_elements_text(plan->'removedSlotIds'));
 insert into public.roster_slots(roster_day_id,role_id,starts_at,ends_at,max_doctors)
 select d.id,(s->>'roleId')::uuid,(s->>'startsAt')::timestamptz,(s->>'endsAt')::timestamptz,(s->>'capacity')::int
 from jsonb_array_elements(plan->'slots') s join public.roster_days d on d.roster_id=rid and d.date=(s->>'date')::date
 where s->>'existingSlotId' is null;
 insert into public.audit_log(actor_user_id,action,entity_table,entity_id,details) values
 (actor,case when p_roster_id is null then 'admin_create_roster' else 'admin_regenerate_draft' end,'rosters',rid,
 jsonb_build_object('requestId',p_request_id,'plan',plan));
 select content_version into v from public.rosters where id=rid;
 response:=jsonb_build_object('ok',true,'requestId',p_request_id,'rosterId',rid,'contentVersion',v,'year',p_year,'month',p_month,'phase','draft');
 insert into public.admin_workspace_requests(actor_id,request_id,payload,response) values(actor,p_request_id,payload,response);
 return response;
exception when others then
 raise log 'admin_apply_generation failure sqlstate=%', SQLSTATE;
 return jsonb_build_object('ok',false,'code','internalError');
end $$;

revoke all on function public.admin_remove_assignments(uuid,bigint,date[],text,uuid,uuid,text) from public;
revoke all on function public.admin_preview_generation(int,int,uuid) from public;
revoke all on function public.admin_apply_generation(int,int,uuid,bigint,text,uuid) from public;
grant execute on function public.admin_remove_assignments(uuid,bigint,date[],text,uuid,uuid,text) to authenticated;
grant execute on function public.admin_preview_generation(int,int,uuid) to authenticated;
grant execute on function public.admin_apply_generation(int,int,uuid,bigint,text,uuid) to authenticated;
