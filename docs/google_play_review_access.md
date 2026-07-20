# Google Play review access

NeuroDienst uses a dedicated, ordinary `doctor` account for Google Play review.
It signs in through the same Supabase email/password flow as every other user.
There is no login bypass, embedded credential, invitation dependency, one-time
code, magic link, or MFA requirement for this account.

The provisioning script uses the Supabase Admin and REST APIs from the local
machine. It never writes credentials to a file. Run it only from a trusted
administrator workstation.

## Prerequisites

- Node.js 18 or newer (`node --version`)
- all Supabase migrations applied, including
  `202607200001_doctors_update_own_profile.sql`
- a production Supabase project with Email/Password sign-in enabled
- a strong, durable reviewer password of at least 16 characters
- a fictional roster with at least one unassigned slot if assignment testing is
  required; never use real employee or patient data for Play review

## Required environment variables

Set these only in the current PowerShell process:

```powershell
$env:SUPABASE_URL = 'https://YOUR_PROJECT_REF.supabase.co'
$env:SUPABASE_SERVICE_ROLE_KEY = 'PASTE_SERVICE_ROLE_KEY_HERE'
$env:SUPABASE_PUBLISHABLE_KEY = 'PASTE_PUBLISHABLE_KEY_HERE'
$env:GOOGLE_PLAY_REVIEWER_EMAIL = 'YOUR_DEDICATED_REVIEWER_EMAIL'
$env:GOOGLE_PLAY_REVIEWER_PASSWORD = 'YOUR_STRONG_REVIEWER_PASSWORD'
```

`SUPABASE_PUBLISHABLE_KEY` is recommended for the RLS verification request. The
script can perform that check with the service key as the API key and the
reviewer's access token as authorization if it is omitted.

Never place the service-role key in Flutter source, a `--dart-define`, a checked-in
environment file, Play Console, screenshots, logs, or chat. The Android app must
continue to receive only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.

For `SUPABASE_SERVICE_ROLE_KEY`, copy **Settings → API Keys → Legacy API Keys →
service_role**. Do not use the `anon`, `sb_publishable_...`, or `sb_secret_...`
value in this variable. The legacy service-role value is a JWT whose embedded
role is `service_role`; the script validates this before making any request.

## Create the reviewer account once

From the repository root:

```powershell
Set-Location C:\apps\neuro_dienst
node .\supabase\scripts\google_play_reviewer.mjs create
```

If PowerShell is currently in `C:\apps\neuro_dienst\neuro_app`, either run the
`Set-Location` command above first or use
`node ..\supabase\scripts\google_play_reviewer.mjs create`.

The command:

- creates and immediately confirms the Supabase Auth user;
- sets a password directly, so no invitation or confirmation email is needed;
- creates `profiles` with display name `Google Reviewer` and regular `doctor`
  role;
- creates and links an active `doctors` row;
- assigns the fictional reviewer the `head` rank and all scheduling
  capabilities so role eligibility does not hide essential review flows; and
- rolls back the new Auth/profile data if provisioning fails.

It does not create an admin, enroll MFA, disable RLS, add a login bypass, or
seed/alter a roster. If the email already exists, it stops without modifying the
account.

## Verify password login and RLS

```powershell
Set-Location C:\apps\neuro_dienst
node .\supabase\scripts\google_play_reviewer.mjs verify
```

This command logs in with email and password, reads the linked profile, doctor,
and roster slots through the reviewer's authenticated session, creates one
provisional assignment for `Google Reviewer`, and removes it immediately through
the same RLS permissions. If no free roster slot exists, create a clearly
fictional test roster with the normal admin UI and run the command again.

The command verifies backend Auth/RLS behavior; complete the following UI check
on the release Android build as well:

1. Clear NeuroDienst storage or uninstall and reinstall the release build.
2. Open the app and enter the reviewer email and password.
3. Tap **Sign in / Anmelden**. No email action, OTP, magic link, or MFA prompt
   should appear.
4. Open the monthly view and a day view.
5. Open profile, **My assignments this month**, calendar/report areas, coverage,
   theme, and language navigation.
6. Select a fictional unassigned duty/function for Google Reviewer and remove it
   again.
7. Sign out, close/reopen the app, and sign in again with the same password.

Keep the account active and the password unchanged for the entire Play review.
Re-run `verify` shortly before every submitted review.

## Reset the password

Set `GOOGLE_PLAY_REVIEWER_PASSWORD` to the new strong password, then run:

```powershell
Set-Location C:\apps\neuro_dienst
node .\supabase\scripts\google_play_reviewer.mjs reset-password
node .\supabase\scripts\google_play_reviewer.mjs verify
```

Update the separate credentials stored in Play Console after verification.

## Delete the reviewer account

With `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and
`GOOGLE_PLAY_REVIEWER_EMAIL` set:

```powershell
Set-Location C:\apps\neuro_dienst
node .\supabase\scripts\google_play_reviewer.mjs delete
```

This deletes reviewer assignments and absences, the linked doctor/profile rows,
and the Auth user. It does not delete shared rosters, days, slots, or roles.

## Clear secrets from the shell

After provisioning or maintenance:

```powershell
Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
Remove-Item Env:GOOGLE_PLAY_REVIEWER_PASSWORD -ErrorAction SilentlyContinue
```

The reviewer email and password must be entered separately in Play Console under
**App access** and must never be committed to Git.

## Play Console instructions (English)

> Open the NeuroDienst app. On the login screen, enter the email address and password provided above and tap ‘Anmelden’. No invitation, email confirmation, one-time PIN or two-factor authentication is required. The reviewer account provides access to all essential app features, including the monthly roster, daily assignments and role selection. An internet connection is required.

## Manual production step

This repository contains no production service-role key, so account creation is
not performed as part of the build or tests. Apply the pending Supabase migration,
set the environment variables from values obtained in **Supabase Dashboard →
Settings → API Keys** (the service-role value is under **Legacy API Keys**), then
run `create` and `verify` locally. Finally, place
only the reviewer email and password—not the service-role key—in Play Console.
