drop policy if exists "admins manage assignments with mfa"
on public.assignments;

create policy "admins manage assignments"
on public.assignments
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());
