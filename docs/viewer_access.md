# Read-only roster accounts

`viewer` is for nurses and administrative staff who only need to see the duty
roster. It is separate from `admin`, which retains management permissions.

Viewers sign in normally, choose an available month, expand days to see duty
roles, times and assigned physicians, refresh, and sign out. They have no doctor
record and no assignment, absence, profile-editing or administration controls.
Existing roster read policies allow all generated phases, not just published
months. No new access to other physicians' absences is granted.

## Deployment order

1. Apply `202610040001_viewer_role.sql`, then
   `202610040002_viewer_read_only.sql`, after all earlier migrations. Keep the
   enum migration separate so its value is committed first.
2. Deploy the updated `invite-doctor` Edge Function. Its existing name and
   default doctor invitation behavior are retained; `accountRole: "viewer"`
   creates only an Auth user and a viewer profile.
3. Release the updated Flutter client, then use **Admin > Invite viewer**.
   An administrator with MFA enters the person's name, email and language;
   the recipient receives a password-setup link.

Do not use the new invitation UI against the old function: that function does
not understand `accountRole`. Deploy the backend before creating viewer accounts.
No existing users are converted by these migrations.

The restrictive policies deny viewer INSERT, UPDATE and DELETE on all eleven
application tables, even if an existing permissive policy would otherwise
allow a linked physician to write. Doctor/admin permissive policies still
determine their access. Viewers cannot promote themselves or modify profiles.
Service-role operations remain confined to the server-side invitation function.
Password setup/reset uses Supabase Auth, not application-table writes.

## Verification

Flutter widget tests cover read-only browsing, month selection, sign-out,
failed-load recovery, and the viewer invitation form.

The backend tests use an isolated PGlite PostgreSQL instance and mocked Supabase
calls, never the production backend or real emails:

```powershell
$viewerTestTools = Join-Path $env:TEMP 'neurodienst-viewer-test-tools'
npm.cmd install --prefix $viewerTestTools --cache (Join-Path $viewerTestTools 'npm-cache') --no-audit --no-fund @electric-sql/pglite
node supabase/tests/viewer_access.mjs $viewerTestTools
node supabase/tests/viewer_invitation.mjs
```

The database test applies every migration and checks roster reads, all 33 table
write paths, self-promotion, a viewer linked to a doctor with MFA, and preserved
doctor/admin behavior. The invitation test checks account creation without a
doctor, old doctor invitations, rejected roles/callers, MFA, and email-failure
cleanup. After deployment, verify a real invitation/password setup and viewer
login on an installed client.
