# Supabase Architecture

NeuroDienst should use Supabase as the shared source of truth for doctors,
roles, monthly rosters, assignments, absences, and future calendar sync state.
The current Flutter demo data can remain as an offline/mock implementation while
the app is migrated to repository interfaces.

## Roles

- `admin`: manages doctors, role templates, roster generation, assignments, and
  doctor invitation/enrollment codes.
- `doctor`: manages personal absence/vacation requests and sees the current
  roster.

Admin actions should require a Supabase Auth session with MFA assurance level
`aal2`. Doctor read/write access can initially use a normal authenticated
session, with MFA optional unless hospital policy requires it.

## Login Model

Each doctor should have a real Supabase Auth user. The admin-created
verification code is best used as an enrollment or invitation code, not as the
long-term login secret.

Recommended flow:

1. Admin creates a doctor profile and optional invitation code.
2. Doctor signs in with Supabase Auth.
3. Doctor enters the invitation code once to link their auth user to the doctor
   profile.
4. Future access is controlled by the linked auth user and Row Level Security.

## First Tables

- `profiles`: app-level user metadata linked to `auth.users`.
- `doctors`: clinical doctor records used by rosters.
- `doctor_enrollment_codes`: temporary codes for linking a login to a doctor.
- `roles`: dynamic duty role definitions.
- `role_templates`: default weekday/template rules for role generation.
- `rosters`: one row per month.
- `roster_days`: one row per day in a roster.
- `roster_slots`: concrete role slots generated for a day.
- `assignments`: doctor assignments to concrete slots.
- `absences`: vacation, sick leave, conference, and external rotation periods.
- `audit_log`: append-only operational history for important changes.

## Migration Strategy

Keep `neuro_core` as the domain layer. Add repository interfaces for loading
and saving doctors, absences, and rosters. Then provide two implementations:

- `DemoRosterRepository`: current local/demo data.
- `SupabaseRosterRepository`: database-backed implementation.

This keeps the UI stable while replacing storage in small steps.
