-- Initial Supabase schema for NeuroDienst.
-- This migration defines the shared data model before the Flutter app is wired
-- to Supabase. Row Level Security is enabled on every exposed table.

create extension if not exists pgcrypto;

create type public.app_role as enum ('admin', 'doctor');
create type public.doctor_rank as enum (
  'resident',
  'specialist',
  'senior_specialist',
  'consultant',
  'head'
);
create type public.capability as enum (
  'can_lead',
  'can_work_outpatient_clinic',
  'can_do_neurosonography',
  'can_do_night_duty',
  'can_supervise'
);
create type public.availability_type as enum (
  'available',
  'vacation',
  'sick_leave',
  'conference',
  'external_rotation'
);
create type public.roster_phase as enum (
  'draft',
  'open_for_selection',
  'locked',
  'published'
);
create type public.assignment_state as enum ('provisional', 'confirmed');
create type public.weekday_rule as enum (
  'every_weekday',
  'monday_only',
  'tuesday_only',
  'wednesday_only',
  'thursday_only',
  'friday_only'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.app_role not null default 'doctor',
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.doctors (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  first_name text not null,
  last_name text not null,
  rank public.doctor_rank not null,
  capabilities public.capability[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.doctor_enrollment_codes (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors (id) on delete cascade,
  code_hash text not null,
  expires_at timestamptz,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  unique (doctor_id)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  area text not null default '',
  display_order integer not null default 0,
  max_doctors integer not null default 1 check (max_doctors > 0),
  required_capabilities public.capability[] not null default '{}',
  allowed_ranks public.doctor_rank[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.role_templates (
  id uuid primary key default gen_random_uuid(),
  role_id uuid not null references public.roles (id) on delete cascade,
  weekday_rule public.weekday_rule not null default 'every_weekday',
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  check (end_time > start_time)
);

create table public.rosters (
  id uuid primary key default gen_random_uuid(),
  year integer not null check (year between 2000 and 2100),
  month integer not null check (month between 1 and 12),
  phase public.roster_phase not null default 'draft',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (year, month)
);

create table public.roster_days (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null references public.rosters (id) on delete cascade,
  date date not null,
  is_weekend boolean not null default false,
  is_public_holiday boolean not null default false,
  public_holiday_name text,
  unique (roster_id, date)
);

create table public.roster_slots (
  id uuid primary key default gen_random_uuid(),
  roster_day_id uuid not null references public.roster_days (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  max_doctors integer not null default 1 check (max_doctors > 0),
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  roster_slot_id uuid not null references public.roster_slots (id) on delete cascade,
  doctor_id uuid not null references public.doctors (id) on delete restrict,
  state public.assignment_state not null default 'provisional',
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (roster_slot_id, doctor_id)
);

create table public.absences (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors (id) on delete cascade,
  starts_on date not null,
  ends_on date not null,
  type public.availability_type not null,
  note text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users (id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index doctors_auth_user_id_idx on public.doctors (auth_user_id);
create index roster_days_roster_id_date_idx on public.roster_days (roster_id, date);
create index roster_slots_day_id_idx on public.roster_slots (roster_day_id);
create index assignments_slot_id_idx on public.assignments (roster_slot_id);
create index assignments_doctor_id_idx on public.assignments (doctor_id);
create index absences_doctor_id_dates_idx on public.absences (doctor_id, starts_on, ends_on);

insert into public.roles (
  code,
  name,
  area,
  display_order,
  max_doctors,
  required_capabilities,
  allowed_ranks
)
values
  (
    'SCI',
    'Science Slot',
    'Science',
    10,
    99,
    '{}',
    array[
      'resident',
      'specialist',
      'senior_specialist',
      'consultant',
      'head'
    ]::public.doctor_rank[]
  ),
  (
    'SUL',
    'Stroke Unit Leader',
    'Stroke Unit',
    20,
    1,
    array['can_lead']::public.capability[],
    array['senior_specialist', 'consultant', 'head']::public.doctor_rank[]
  ),
  (
    'SU1',
    'Stroke Unit Team 1',
    'Stroke Unit',
    30,
    1,
    '{}',
    array[
      'resident',
      'specialist',
      'senior_specialist',
      'consultant',
      'head'
    ]::public.doctor_rank[]
  ),
  (
    'SU2',
    'Stroke Unit Team 2',
    'Stroke Unit',
    40,
    1,
    '{}',
    array[
      'resident',
      'specialist',
      'senior_specialist',
      'consultant',
      'head'
    ]::public.doctor_rank[]
  ),
  (
    'AMB',
    'Ambulance',
    'Outpatient Clinic',
    50,
    1,
    '{}',
    array[
      'resident',
      'specialist',
      'senior_specialist',
      'consultant',
      'head'
    ]::public.doctor_rank[]
  ),
  (
    'SON',
    'Neurosonology',
    'Neurosonology',
    60,
    1,
    array['can_do_neurosonography']::public.capability[],
    array['senior_specialist', 'consultant', 'head']::public.doctor_rank[]
  ),
  (
    'NVB',
    'Neurovascular Interdisciplinary Board',
    'Board',
    70,
    1,
    '{}',
    array['senior_specialist', 'consultant', 'head']::public.doctor_rank[]
  ),
  (
    'OFO',
    'OFO Board',
    'Board',
    80,
    1,
    '{}',
    array['senior_specialist', 'consultant', 'head']::public.doctor_rank[]
  );

insert into public.role_templates (role_id, weekday_rule, start_time, end_time)
select id, 'every_weekday', time '08:00', time '16:00'
from public.roles
where code = 'SCI';

insert into public.role_templates (role_id, weekday_rule, start_time, end_time)
select id, 'every_weekday', time '07:30', time '15:30'
from public.roles
where code in ('SUL', 'SU1', 'SU2');

insert into public.role_templates (role_id, weekday_rule, start_time, end_time)
select id, 'every_weekday', time '09:00', time '13:00'
from public.roles
where code = 'AMB';

insert into public.role_templates (role_id, weekday_rule, start_time, end_time)
select id, 'every_weekday', time '08:00', time '15:30'
from public.roles
where code = 'SON';

insert into public.role_templates (role_id, weekday_rule, start_time, end_time)
select id, 'thursday_only', time '12:30', time '13:00'
from public.roles
where code = 'NVB';

insert into public.role_templates (role_id, weekday_rule, start_time, end_time)
select id, 'wednesday_only', time '13:00', time '14:00'
from public.roles
where code = 'OFO';

alter table public.profiles enable row level security;
alter table public.doctors enable row level security;
alter table public.doctor_enrollment_codes enable row level security;
alter table public.roles enable row level security;
alter table public.role_templates enable row level security;
alter table public.rosters enable row level security;
alter table public.roster_days enable row level security;
alter table public.roster_slots enable row level security;
alter table public.assignments enable row level security;
alter table public.absences enable row level security;
alter table public.audit_log enable row level security;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

create function public.is_aal2()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

create function public.is_own_doctor_record(target_doctor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.doctors
    where id = target_doctor_id
      and auth_user_id = auth.uid()
  );
$$;

create policy "profiles select own or admin"
on public.profiles
for select
to authenticated
using (id = auth.uid() or public.is_admin());

create policy "admins manage profiles with mfa"
on public.profiles
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read active doctors"
on public.doctors
for select
to authenticated
using (is_active or public.is_admin());

create policy "admins manage doctors with mfa"
on public.doctors
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "admins manage enrollment codes with mfa"
on public.doctor_enrollment_codes
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read roles"
on public.roles
for select
to authenticated
using (is_active or public.is_admin());

create policy "admins manage roles with mfa"
on public.roles
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read role templates"
on public.role_templates
for select
to authenticated
using (true);

create policy "admins manage role templates with mfa"
on public.role_templates
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read rosters"
on public.rosters
for select
to authenticated
using (true);

create policy "admins manage rosters with mfa"
on public.rosters
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read roster days"
on public.roster_days
for select
to authenticated
using (true);

create policy "admins manage roster days with mfa"
on public.roster_days
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read roster slots"
on public.roster_slots
for select
to authenticated
using (true);

create policy "admins manage roster slots with mfa"
on public.roster_slots
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "authenticated users read assignments"
on public.assignments
for select
to authenticated
using (true);

create policy "admins manage assignments with mfa"
on public.assignments
for all
to authenticated
using (public.is_admin() and public.is_aal2())
with check (public.is_admin() and public.is_aal2());

create policy "doctors read own absences"
on public.absences
for select
to authenticated
using (public.is_own_doctor_record(doctor_id) or public.is_admin());

create policy "doctors manage own absences"
on public.absences
for insert
to authenticated
with check (public.is_own_doctor_record(doctor_id) or public.is_admin());

create policy "doctors update own absences"
on public.absences
for update
to authenticated
using (public.is_own_doctor_record(doctor_id) or public.is_admin())
with check (public.is_own_doctor_record(doctor_id) or public.is_admin());

create policy "admins delete absences with mfa"
on public.absences
for delete
to authenticated
using (public.is_admin() and public.is_aal2());

create policy "admins read audit log with mfa"
on public.audit_log
for select
to authenticated
using (public.is_admin() and public.is_aal2());

create policy "admins append audit log with mfa"
on public.audit_log
for insert
to authenticated
with check (public.is_admin() and public.is_aal2());
