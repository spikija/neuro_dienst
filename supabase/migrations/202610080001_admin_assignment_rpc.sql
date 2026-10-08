-- Forward-only: keep every roster/day/slot/assignment and existing mobile RLS.
-- Version 1 is a real server-initialized concurrency stamp, not a client fallback.
alter table public.rosters add column content_version bigint not null default 1
  check (content_version > 0);

create function public.advance_roster_version() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'INSERT' then NEW.content_version := 1;
  else NEW.content_version := OLD.content_version + 1; end if;
  return NEW;
end $$;
revoke all on function public.advance_roster_version() from public;
create trigger roster_version before insert or update on public.rosters
for each row execute function public.advance_roster_version();

-- Conservative invalidation across months: physicians/absences and overnight
-- conflicts cross roster boundaries. All clients, including legacy mobile DML,
-- advance versions. No business fields or existing RLS policies are changed.
create function public.invalidate_roster_versions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- RLS may make an UPDATE/DELETE affect zero rows. In particular, viewers must
  -- not be able to change version metadata merely by issuing an empty statement.
  if TG_OP = 'DELETE' then
    if not exists(select 1 from old_roster_inputs) then return null; end if;
  else
    if not exists(select 1 from new_roster_inputs) then return null; end if;
  end if;
  update public.rosters set content_version = content_version + 1;
  return null;
end $$;
revoke all on function public.invalidate_roster_versions() from public;
do $$ declare tab text; begin
  foreach tab in array array['doctors','roles','absences','roster_days','roster_slots','assignments'] loop
    execute format('create trigger invalidate_rosters_insert after insert on public.%I referencing new table as new_roster_inputs for each statement execute function public.invalidate_roster_versions()', tab);
    execute format('create trigger invalidate_rosters_update after update on public.%I referencing new table as new_roster_inputs for each statement execute function public.invalidate_roster_versions()', tab);
    execute format('create trigger invalidate_rosters_delete after delete on public.%I referencing old table as old_roster_inputs for each statement execute function public.invalidate_roster_versions()', tab);
  end loop;
end $$;

-- Private durable receipts, not accessible through PostgREST table grants.
create table public.admin_assignment_requests (
  actor_id uuid not null references auth.users(id),
  request_id uuid not null,
  payload jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id, request_id)
);
alter table public.admin_assignment_requests enable row level security;
revoke all on public.admin_assignment_requests from public, authenticated;

-- Matches DefaultOverlapRules in neuro_core; no enum fallback for custom roles.
create function public.admin_overlap_allowed(a text, b text) returns boolean
language sql immutable set search_path = '' as $$
  select (a in ('SON','SUL') and b in ('NVB','OFO'))
      or (b in ('SON','SUL') and a in ('NVB','OFO'));
$$;
revoke all on function public.admin_overlap_allowed(text,text) from public;

create function public.admin_apply_assignments(
  p_roster_id uuid, p_expected_version bigint, p_physician_id uuid,
  p_role_id uuid, p_dates date[], p_request_id uuid, p_reason text default null
) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  reason text := nullif(regexp_replace(p_reason,'^[[:space:]]+|[[:space:]]+$','','g'),'');
  roster public.rosters%rowtype;
  physician public.doctors%rowtype;
  duty_role public.roles%rowtype;
  slot public.roster_slots%rowtype;
  target_date date;
  dates date[];
  slot_ids uuid[] := '{}';
  slot_count integer;
  errs jsonb;
  results jsonb := '[]';
  global_errors jsonb := '[]';
  failed boolean := false;
  payload jsonb;
  prior public.admin_assignment_requests%rowtype;
  response jsonb;
  added jsonb;
  new_version bigint;
begin
  if actor is null or not exists(select 1 from public.profiles where id=actor and role::text='admin') then
    return jsonb_build_object('ok',false,'code','unauthorized','results','[]'::jsonb);
  end if;
  if coalesce(auth.jwt()->>'aal','') <> 'aal2' then
    return jsonb_build_object('ok',false,'code','mfaRequired','results','[]'::jsonb);
  end if;
  if p_request_id is null or p_expected_version is null or p_expected_version < 1
     or p_roster_id is null or p_physician_id is null or p_role_id is null
     or coalesce(cardinality(p_dates),0) not between 1 and 31
     or exists(select 1 from unnest(p_dates) d where d is null)
     or (select count(distinct d) from unnest(p_dates) d) <> cardinality(p_dates) then
    return jsonb_build_object('ok',false,'code','invalidDate','results','[]'::jsonb);
  end if;
  select array_agg(d order by d) into dates from unnest(p_dates) d;
  payload := jsonb_build_object('roster',p_roster_id,'version',p_expected_version,
    'physician',p_physician_id,'role',p_role_id,'dates',dates,'reason',reason);

  -- These table locks conflict with *all* writers, including legacy mobile
  -- statements that do not take advisory/roster row locks. Ordinary reads remain
  -- available. Deliberately coarse first implementation; held through audit/receipt.
  lock table public.profiles, public.doctors, public.roles, public.absences,
    public.rosters, public.roster_days, public.roster_slots, public.assignments,
    public.admin_assignment_requests in share row exclusive mode;
  if not exists(select 1 from public.profiles where id=actor and role::text='admin') then
    return jsonb_build_object('ok',false,'code','unauthorized','results','[]'::jsonb);
  end if;
  select * into prior from public.admin_assignment_requests
    where actor_id=actor and request_id=p_request_id;
  if found then
    if prior.payload <> payload then
      return jsonb_build_object('ok',false,'code','idempotencyConflict','results','[]'::jsonb);
    end if;
    return prior.response;
  end if;
  select * into roster from public.rosters where id=p_roster_id for update;
  if not found then global_errors := global_errors || '"invalidDate"'::jsonb;
  elsif roster.content_version <> p_expected_version then global_errors := global_errors || '"staleVersion"'::jsonb;
  end if;
  if roster.phase = 'published' or (roster.phase = 'locked' and reason is null) then
    global_errors := global_errors || '"rosterNotEditable"'::jsonb;
  end if;
  select * into physician from public.doctors where id=p_physician_id;
  if not found then global_errors := global_errors || '"physicianNotFound"'::jsonb;
  elsif not physician.is_active then global_errors := global_errors || '"physicianInactive"'::jsonb; end if;
  select * into duty_role from public.roles where id=p_role_id;
  if not found or not duty_role.is_active then global_errors := global_errors || '"roleInactive"'::jsonb;
  else
    if not coalesce(physician.rank = any(duty_role.allowed_ranks),false) then
      global_errors := global_errors || '"physicianNotEligible"'::jsonb;
    end if;
    if not coalesce(duty_role.required_capabilities <@ physician.capabilities,false) then
      global_errors := global_errors || '"missingCapability"'::jsonb;
    end if;
  end if;
  foreach target_date in array dates loop
    errs := global_errors;
    slot := null;
    if extract(year from target_date) <> roster.year or extract(month from target_date) <> roster.month then
      errs := errs || '"invalidDate"'::jsonb;
    end if;
    select count(*) into slot_count from public.roster_slots s
      join public.roster_days d on d.id=s.roster_day_id
      where d.roster_id=p_roster_id and d.date=target_date and s.role_id=p_role_id;
    if slot_count=0 then errs := errs || '"missingSlot"'::jsonb;
    elsif slot_count>1 then errs := errs || '"ambiguousSlot"'::jsonb;
    else
      select s.* into slot from public.roster_slots s join public.roster_days d on d.id=s.roster_day_id
        where d.roster_id=p_roster_id and d.date=target_date and s.role_id=p_role_id;
      slot_ids := array_append(slot_ids, slot.id);
      if exists(select 1 from public.assignments where roster_slot_id=slot.id and doctor_id=p_physician_id) then
        errs := errs || '"duplicateAssignment"'::jsonb;
      end if;
      if (select count(*) from public.assignments where roster_slot_id=slot.id) >= slot.max_doctors then
        errs := errs || '"slotFull"'::jsonb;
      end if;
      if exists(select 1 from public.absences a where a.doctor_id=p_physician_id
        and a.type::text not in ('available','duty_24')
        and ((a.starts_on <= target_date and a.ends_on >= target_date)
          or (a.starts_on <= ((slot.ends_at - interval '1 microsecond') at time zone 'Europe/Vienna')::date
            and a.ends_on >= (slot.starts_at at time zone 'Europe/Vienna')::date))) then
        errs := errs || '"blockingAbsence"'::jsonb;
      end if;
      if exists(select 1 from public.assignments a
        join public.roster_slots s on s.id=a.roster_slot_id
        join public.roster_days d on d.id=s.roster_day_id join public.roles r on r.id=s.role_id
        where a.doctor_id=p_physician_id and s.id<>slot.id
        and s.starts_at<slot.ends_at and s.ends_at>slot.starts_at
        and not (d.date=target_date and public.admin_overlap_allowed(duty_role.code,r.code))) then
        errs := errs || '"overlappingAssignment"'::jsonb;
      end if;
      -- Compare against every other selected date, not just already-looped dates.
      if exists(select 1 from public.roster_slots s join public.roster_days d on d.id=s.roster_day_id
        where d.roster_id=p_roster_id and d.date=any(dates) and d.date<>target_date
        and s.role_id=p_role_id and s.starts_at<slot.ends_at and s.ends_at>slot.starts_at) then
        errs := errs || '"overlappingAssignment"'::jsonb;
      end if;
    end if;
    failed := failed or jsonb_array_length(errs)>0;
    results := results || jsonb_build_array(jsonb_build_object('date',target_date,'slotId',slot.id,'errors',errs));
  end loop;
  if failed then
    return jsonb_build_object('ok',false,'code',case when global_errors ? 'staleVersion' then 'staleVersion' else 'validationFailed' end,'results',results);
  end if;

  -- One statement, all rows: triggers advance versions once. Audit and durable
  -- response belong to the same transaction; an exception rolls everything back.
  with inserted as (
    insert into public.assignments(roster_slot_id,doctor_id,state,created_by)
      select id,p_physician_id,'confirmed',actor from unnest(slot_ids) id
    returning id,roster_slot_id,state
  ) select jsonb_agg(jsonb_build_object('id',id,'slotId',roster_slot_id,'state',state)) into added from inserted;
  select content_version into new_version from public.rosters where id=p_roster_id;
  insert into public.audit_log(actor_user_id,action,entity_table,entity_id,details)
    select actor,'admin_apply_assignments','assignments',(a->>'id')::uuid,
      jsonb_build_object('rosterId',p_roster_id,'physicianId',p_physician_id,'roleId',p_role_id,
        'slotId',a->>'slotId','date',d.date,'oldState',null,'newState','confirmed',
        'requestId',p_request_id,'reason',reason,
        'expectedVersion',p_expected_version,'contentVersion',new_version)
    from jsonb_array_elements(added) a join public.roster_slots s on s.id=(a->>'slotId')::uuid
      join public.roster_days d on d.id=s.roster_day_id;
  response := jsonb_build_object('ok',true,'requestId',p_request_id,'rosterId',p_roster_id,
    'contentVersion',new_version,'results',results,'addedAssignments',added);
  insert into public.admin_assignment_requests values(actor,p_request_id,payload,response,now());
  return response;
exception when others then
  -- No SQLERRM: rollback the function subtransaction, including audit/version.
  return jsonb_build_object('ok',false,'code','internalError','results','[]'::jsonb);
end $$;
revoke all on function public.admin_apply_assignments(uuid,bigint,uuid,uuid,date[],uuid,text) from public;
grant execute on function public.admin_apply_assignments(uuid,bigint,uuid,uuid,date[],uuid,text) to authenticated;
