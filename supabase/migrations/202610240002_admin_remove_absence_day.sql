-- Absences and day markers are separate from duty assignments. Remove only the chosen
-- date, atomically splitting multi-day periods and preserving their metadata.
create function public.admin_remove_absence_day(
  p_roster_id uuid, p_expected_version bigint, p_physician_id uuid,
  p_date date, p_type text, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  access text;
  roster public.rosters%rowtype;
  prior public.admin_workspace_requests%rowtype;
  absence public.absences%rowtype;
  payload jsonb;
  response jsonb;
  removed jsonb := '[]'::jsonb;
  retained jsonb := '[]'::jsonb;
  retained_id uuid;
  v bigint;
begin
  access := public.admin_workspace_access();
  if access is not null then
    return jsonb_build_object('ok', false, 'code', access);
  end if;
  if p_roster_id is null or p_expected_version is null or p_expected_version < 1
    or p_physician_id is null or p_date is null or p_request_id is null
    or p_type is null or p_type <> all(enum_range(null::public.availability_type)::text[]) then
    return jsonb_build_object('ok', false, 'code', 'invalidRequest');
  end if;
  payload := jsonb_build_object('operation', 'removeAbsence', 'roster', p_roster_id,
    'version', p_expected_version, 'physician', p_physician_id, 'date', p_date, 'type', p_type);
  perform public.admin_workspace_lock();
  access := public.admin_workspace_access();
  if access is not null then
    return jsonb_build_object('ok', false, 'code', access);
  end if;
  select * into prior from public.admin_workspace_requests
    where actor_id = actor and request_id = p_request_id;
  if found then
    if prior.payload <> payload then
      return jsonb_build_object('ok', false, 'code', 'idempotencyConflict');
    end if;
    return prior.response;
  end if;
  select * into roster from public.rosters where id = p_roster_id;
  if not found or roster.content_version <> p_expected_version then
    return jsonb_build_object('ok', false, 'code', 'staleVersion');
  end if;
  if extract(year from p_date) <> roster.year or extract(month from p_date) <> roster.month then
    return jsonb_build_object('ok', false, 'code', 'invalidRequest');
  end if;
  for absence in select * from public.absences where doctor_id = p_physician_id
    and type::text = p_type and starts_on <= p_date and ends_on >= p_date
    order by id for update
  loop
    removed := removed || jsonb_build_array(jsonb_build_object('id', absence.id,
      'startsOn', absence.starts_on, 'endsOn', absence.ends_on));
    delete from public.absences where id = absence.id;
    if absence.starts_on < p_date then
      insert into public.absences(doctor_id, starts_on, ends_on, type, note, created_by, created_at)
      values (absence.doctor_id, absence.starts_on, p_date - 1, absence.type,
        absence.note, absence.created_by, absence.created_at) returning id into retained_id;
      retained := retained || jsonb_build_array(retained_id);
    end if;
    if absence.ends_on > p_date then
      insert into public.absences(doctor_id, starts_on, ends_on, type, note, created_by, created_at)
      values (absence.doctor_id, p_date + 1, absence.ends_on, absence.type,
        absence.note, absence.created_by, absence.created_at) returning id into retained_id;
      retained := retained || jsonb_build_array(retained_id);
    end if;
  end loop;
  if jsonb_array_length(removed) = 0 then
    return jsonb_build_object('ok', false, 'code', 'noAbsence');
  end if;
  insert into public.audit_log(actor_user_id, action, entity_table, entity_id, details)
  values (actor, 'admin_remove_absence_day', 'absences', (removed->0->>'id')::uuid,
    jsonb_build_object('requestId', p_request_id, 'rosterId', p_roster_id,
      'physicianId', p_physician_id, 'date', p_date, 'type', p_type,
      'removedPeriods', removed, 'retainedPeriodIds', retained));
  select content_version into v from public.rosters where id = p_roster_id;
  response := jsonb_build_object('ok', true, 'requestId', p_request_id,
    'rosterId', p_roster_id, 'physicianId', p_physician_id, 'date', p_date, 'type', p_type, 'contentVersion', v);
  insert into public.admin_workspace_requests(actor_id, request_id, payload, response)
    values (actor, p_request_id, payload, response);
  return response;
end $$;
revoke all on function public.admin_remove_absence_day(uuid,bigint,uuid,date,text,uuid) from public;
grant execute on function public.admin_remove_absence_day(uuid,bigint,uuid,date,text,uuid) to authenticated;
