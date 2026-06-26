create policy "doctors delete own absences"
on public.absences
for delete
to authenticated
using (public.is_own_doctor_record(doctor_id));
