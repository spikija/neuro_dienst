-- Forward-only diagnostic change for an unexpected live internalError.
-- No changes to assignment rules, admin/AAL2 gates, locking or atomic rollback.
-- Existing desktop clients can ignore the additional diagnostic response fields.
-- Supabase Postgres logs: search for "admin_apply_assignments failure".

create or replace function public.admin_apply_assignments(
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
  diagnostic_stage text := 'authorization';
  diagnostic_state text;
  diagnostic_schema text;
  diagnostic_table text;
  diagnostic_column text;
  diagnostic_constraint text;
begin
  if actor is null or not exists(select 1 from public.profiles where id=actor and role::text='admin') then
    return jsonb_build_object('ok',false,'code','unauthorized','results','[]'::jsonb);
  end if;
  if coalesce(auth.jwt()->>'aal','') <> 'aal2' then
    return jsonb_build_object('ok',false,'code','mfaRequired','results','[]'::jsonb);
  end if;
  diagnostic_stage := 'request_validation';
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
  diagnostic_stage := 'lock_inputs';
  lock table public.profiles, public.doctors, public.roles, public.absences,
    public.rosters, public.roster_days, public.roster_slots, public.assignments,
    public.admin_assignment_requests in share row exclusive mode;
  if not exists(select 1 from public.profiles where id=actor and role::text='admin') then
    return jsonb_build_object('ok',false,'code','unauthorized','results','[]'::jsonb);
  end if;
  diagnostic_stage := 'idempotency_lookup';
  select * into prior from public.admin_assignment_requests
    where actor_id=actor and request_id=p_request_id;
  if found then
    if prior.payload <> payload then
      return jsonb_build_object('ok',false,'code','idempotencyConflict','results','[]'::jsonb);
    end if;
    return prior.response;
  end if;
  diagnostic_stage := 'roster_lookup';
  select * into roster from public.rosters where id=p_roster_id for update;
  if not found then global_errors := global_errors || '"invalidDate"'::jsonb;
  elsif roster.content_version <> p_expected_version then global_errors := global_errors || '"staleVersion"'::jsonb;
  end if;
  if roster.phase = 'published' or (roster.phase = 'locked' and reason is null) then
    global_errors := global_errors || '"rosterNotEditable"'::jsonb;
  end if;
  diagnostic_stage := 'physician_lookup';
  select * into physician from public.doctors where id=p_physician_id;
  if not found then global_errors := global_errors || '"physicianNotFound"'::jsonb;
  elsif not physician.is_active then global_errors := global_errors || '"physicianInactive"'::jsonb; end if;
  diagnostic_stage := 'role_lookup';
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
  diagnostic_stage := 'date_validation';
  foreach target_date in array dates loop
    errs := global_errors;
    slot := null;
    if extract(year from target_date) <> roster.year or extract(month from target_date) <> roster.month then
      errs := errs || '"invalidDate"'::jsonb;
    end if;
    diagnostic_stage := 'slot_lookup';
    select count(*) into slot_count from public.roster_slots s
      join public.roster_days d on d.id=s.roster_day_id
      where d.roster_id=p_roster_id and d.date=target_date and s.role_id=p_role_id;
    if slot_count=0 then errs := errs || '"missingSlot"'::jsonb;
    elsif slot_count>1 then errs := errs || '"ambiguousSlot"'::jsonb;
    else
      select s.* into slot from public.roster_slots s join public.roster_days d on d.id=s.roster_day_id
        where d.roster_id=p_roster_id and d.date=target_date and s.role_id=p_role_id;
      slot_ids := array_append(slot_ids, slot.id);
      diagnostic_stage := 'duplicate_check';
      if exists(select 1 from public.assignments where roster_slot_id=slot.id and doctor_id=p_physician_id) then
        errs := errs || '"duplicateAssignment"'::jsonb;
      end if;
      diagnostic_stage := 'capacity_check';
      if (select count(*) from public.assignments where roster_slot_id=slot.id) >= slot.max_doctors then
        errs := errs || '"slotFull"'::jsonb;
      end if;
      diagnostic_stage := 'absence_check';
      if exists(select 1 from public.absences a where a.doctor_id=p_physician_id
        and a.type::text not in ('available','duty_24')
        and ((a.starts_on <= target_date and a.ends_on >= target_date)
          or (a.starts_on <= ((slot.ends_at - interval '1 microsecond') at time zone 'Europe/Vienna')::date
            and a.ends_on >= (slot.starts_at at time zone 'Europe/Vienna')::date))) then
        errs := errs || '"blockingAbsence"'::jsonb;
      end if;
      diagnostic_stage := 'existing_overlap_check';
      if exists(select 1 from public.assignments a
        join public.roster_slots s on s.id=a.roster_slot_id
        join public.roster_days d on d.id=s.roster_day_id join public.roles r on r.id=s.role_id
        where a.doctor_id=p_physician_id and s.id<>slot.id
        and s.starts_at<slot.ends_at and s.ends_at>slot.starts_at
        and not (d.date=target_date and public.admin_overlap_allowed(duty_role.code,r.code))) then
        errs := errs || '"overlappingAssignment"'::jsonb;
      end if;
      -- Compare against every other selected date, not just already-looped dates.
      diagnostic_stage := 'proposed_overlap_check';
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
  diagnostic_stage := 'assignment_insert';
  with inserted as (
    insert into public.assignments(roster_slot_id,doctor_id,state,created_by)
      select id,p_physician_id,'confirmed',actor from unnest(slot_ids) id
    returning id,roster_slot_id,state
  ) select jsonb_agg(jsonb_build_object('id',id,'slotId',roster_slot_id,'state',state)) into added from inserted;
  diagnostic_stage := 'version_read';
  select content_version into new_version from public.rosters where id=p_roster_id;
  diagnostic_stage := 'audit_insert';
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
  diagnostic_stage := 'receipt_insert';
  insert into public.admin_assignment_requests values(actor,p_request_id,payload,response,now());
  return response;
exception when others then
  -- The failed block has already rolled back assignments/audit/version/receipt.
  -- Keep SQLERRM, exception detail/context and all business inputs out of logs
  -- and responses. Catalog object names help identify a failing constraint.
  get stacked diagnostics diagnostic_state = returned_sqlstate,
    diagnostic_schema = schema_name, diagnostic_table = table_name,
    diagnostic_column = column_name, diagnostic_constraint = constraint_name;
  raise log 'admin_apply_assignments failure: %', jsonb_build_object(
    'requestId',p_request_id,'sqlstate',diagnostic_state,'stage',diagnostic_stage,
    'schema',diagnostic_schema,'table',diagnostic_table,
    'column',diagnostic_column,'constraint',diagnostic_constraint);
  return jsonb_build_object('ok',false,'code','internalError','results','[]'::jsonb,
    'diagnosticCode',diagnostic_state,'diagnosticStage',diagnostic_stage);
end $$;
revoke all on function public.admin_apply_assignments(uuid,bigint,uuid,uuid,date[],uuid,text) from public;
grant execute on function public.admin_apply_assignments(uuid,bigint,uuid,uuid,date[],uuid,text) to authenticated;
