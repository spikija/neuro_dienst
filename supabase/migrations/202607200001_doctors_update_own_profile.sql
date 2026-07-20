-- A regular doctor can persist non-privileged fields on their own profile.
-- The role must remain doctor, so this policy cannot be used for privilege
-- escalation. Admin profile management remains protected by its existing
-- admin/MFA policy.

drop policy if exists "doctors update own profile"
on public.profiles;

create policy "doctors update own profile"
on public.profiles
for update
to authenticated
using (
  id = auth.uid()
  and role = 'doctor'
)
with check (
  id = auth.uid()
  and role = 'doctor'
);

