drop policy if exists "doctors insert own assignments"
on public.assignments;

create policy "doctors insert own assignments"
on public.assignments
for insert
to authenticated
with check (public.is_own_doctor_record(doctor_id));

drop policy if exists "doctors delete own assignments"
on public.assignments;

create policy "doctors delete own assignments"
on public.assignments
for delete
to authenticated
using (public.is_own_doctor_record(doctor_id));
