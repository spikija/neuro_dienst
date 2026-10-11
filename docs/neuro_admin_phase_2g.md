# Phase 2G: configuration administration, account deletion and monthly printing

## Deployment and boundaries

Apply these forward migrations, in order, after Phase 2F:

1. `supabase/migrations/202610110001_admin_configuration.sql`
2. `supabase/migrations/202610110002_admin_delete_account.sql`

No Edge Function redeployment or client service-role secret is needed for these
commands. No live account deletion, role/template mutation or roster regeneration
was performed during this task. Verification uses isolated databases and synthetic
reports. Supabase's full managed Auth schema must still be checked in a staging
project before exercising permanent deletion on live test accounts.

The desktop remains admin+AAL2 only. No automatic allocation, ranking, publishing
or department tenancy was implemented. Mobile/core source is unchanged.

## Physician and viewer UX

The directory retains search and active filters. Rows are bounded-width cards
instead of stretching names/actions across the entire window. Selection has a
filled background, primary border and checked radio icon. Identity, rank and
status stay together; only the selected card exposes compact action buttons.

Delete permanently requires an explicit acknowledgement. A dependency refusal
shows Archive/Deactivate for physicians or Revoke access for viewers. Unknown
network outcomes retry the original UUID and expected version, not a new command.

## Permanent account deletion

`admin_delete_account` is a security-definer PostgreSQL RPC with a pinned search
path and admin+AAL2 checks before and after the workspace lock. It removes the
unused doctor, linked profile and `auth.users` record in one server transaction;
Auth identities/sessions follow their internal cascades. It does not expose an
Auth admin key to the desktop. A minimal audit tombstone and actor-scoped receipt
are written in that same transaction. Audit failure rolls back the entire delete.

The command rejects administrators, self-deletion, stale versions and missing
acknowledgement. It checks doctor/profile/Auth foreign-key dependants outside Auth,
including cascade relationships, audit entity/details/actor references, stored
assignment/workspace request references and Storage object ownership where
`owner_id` exists. Composite references are conservatively blocked. No historical
assignments/absences are cascaded away. Existing doctor-history triggers remain.

Audit/history checks are intentionally conservative: even an earlier directory
edit can make an otherwise unused account ineligible for permanent deletion.
Archive/revoke remains available. This is not a general history-erasure tool.
A physician without a linked account can be safely removed under the same checks.
A legacy viewer linked to a doctor must pass the doctor checks too.

The shared RLS access guard now requires an existing non-revoked profile, so a
deleted account's unexpired JWT cannot continue reading protected tables. This
cannot retract previously cached/downloaded information.

## Shared role/template administration

`ConfigurationAdministrationService` and immutable configuration read/command
models live in the Flutter-free shared package. Its Supabase adapter uses only
`admin_configuration` and `admin_save_configuration`. Both clients can use this
service later; desktop forms do not copy the mobile persistence workflow.

Roles support arbitrary code/name, activation, allowed ranks, required capabilities,
default capacity (`roles.max_doctors`), report visibility and ordering. Exact role
IDs remain distinct (including AMB, ICB and custom codes). Optimistic timestamps,
idempotent commands, audit records and unique codes are checked on the server.
Roles referenced by templates, historical slots or factual audit records cannot
be deleted. Configuration-change audit records alone do not prevent deleting an
otherwise unused role; those audit records remain. Other FK restrictions still apply.

Templates support any weekday subset (ISO 1-7), a monthly day, Vienna wall-clock
start/end, activation and capacity. New columns are `weekdays`, `is_active`,
`capacity`, `updated_at`. Legacy rows keep their old `weekday_rule` behavior and
inherit role capacity until explicitly edited. Editing converts weekday rules to
an explicit set. Current schema still requires end time after start time on the
same day; overnight/24-hour templates would need a separate end-day-offset design.

The desktop generator is configuration-driven: only active roles and templates
contribute, template capacity overrides the role default, and arbitrary codes
need no code change. Monthly dates that do not exist are skipped. Existing Vienna
DST gap/fold validation, preview tokens, audit, idempotency, preserved slot IDs,
assignment-loss blockers and draft-only regeneration remain in force. Template
CRUD never mutates existing roster days, slots or assignments.

## Remaining hardcoded assumptions and mobile compatibility

Desktop/server generation has no neurology role-name/code dispatch. Seed migrations
still define the initial neurology configuration. Legacy workload categories still
recognize SUL/SU1/SU2, AMB and SCI; custom categories remain unclassified rather than
inventing fairness mappings. Existing overlap exceptions use SON/NVB/OFO/SUL in the
shared validator/backend. Per-physician report text retains its established seeded
role-priority ordering. Core/mobile enum adapters remain legacy compatibility code.

The mobile template/generation screens have not yet adopted the shared commands;
their legacy generator does not understand the new activation, weekday-set and
capacity overrides. Use desktop/server generation for these configurations until
mobile generation is migrated to the same preview/apply service. Mobile can still
read existing rosters. Configurable overlap/workload policies and historical role
metadata snapshots are separate follow-up work; role metadata edits can affect
how past assignments are labelled, without altering stored assignments.

## Print-specific monthly layout

`ReportPrintLayout` uses PDF points and actual A4 dimensions, independently of
on-screen widths. Margins are 18 pt, date/day column 78 pt, notes column 68 pt.
For a monthly role report:

`role width = (page width - 36 - 78 - 68) / visible role count`

Each visible role gets equal width; no columns are dropped or horizontally grouped.
Nine roles get about 45.92 pt in portrait and 73.32 pt in landscape. Body text is
8 pt (7 pt for narrower columns), horizontal padding 1 pt. Headers wrap. The minimum
legible role width is 30 pt: beyond that the UI explicitly recommends landscape or
fewer configured report columns. Excessively tall content also raises a clear
warning instead of silently exporting clipped/multiple-page monthly output.

Weekdays have an 18 pt minimum height with 2 pt vertical padding; weekends use
10 pt and 0.5 pt. Content can increase either height, preserving weekend duties.
Headers use muted blue-grey, weekends neutral grey, national holidays a pale muted
tint, weekdays white. Borders and text retain grayscale distinction. Holiday names
remain printed. Dates are dd.MM.yyyy in both languages; weekday abbreviations are
bold Mo/Di/Mi/Do/Fr/Sa/So in German and Mon/Tue/... in English. Screen dates also use
European formatting, while its column widths and scroll layout remain unchanged.

The previous fixed 120 pt print-column rule required three horizontal groups for
8 roles plus notes (four for 9 roles plus notes). The populated 9-role October test,
with realistic neurology names, all 31 dates and a weekend duty, now produces exactly
one portrait page and one landscape page. Physician report column pagination is
retained; the one-page policy applies specifically to monthly role rosters.

## Future departments (proposal only)

Introduce `departments(id, name, active)` and backfill one existing department.
Use physician memberships `(department_id, doctor_id, active, ...)` rather than
assuming each physician belongs to exactly one department. Add department_id to
roles, templates, rosters and report configuration. Replace global role-code and
year/month uniqueness with department-scoped constraints. Composite foreign keys
must ensure template/role and roster-slot/role department consistency.

Add explicit administrator department memberships and enforce them in RLS and
all RPCs; bind command receipts/preview hashes to department. Scope configuration,
reports and locks explicitly, while keeping physician overlap/absence validation
cross-department where clinicians work in multiple units. Backfill, validate and
make keys non-null before permitting a second department. Do not use role-code
prefixes or UI filtering as tenancy/security boundaries. Profiles/Auth identities
remain global; removal must continue checking dependencies across departments.

## Verification

Automated: full desktop suite 83 tests; shared services 50 tests; core 10 tests.
Backend: assignment 33 tests, workspace 17, directory and configuration/account
lifecycle suites, viewer write-policy 33 paths and mocked invitation handler.
New SQL tested on PGlite, native PostgreSQL 17 and PostgreSQL 14 with safeupdate.
PyMuPDF verifies one-page portrait/landscape, all role headers/rightmost column,
text bounds, bold weekday spans, European dates, compact weekend row geometry,
holiday annotation and four distinct restrained fill treatments.
Final Windows release build passed (82.8 seconds), producing
`neuro_admin/build/windows/x64/runner/Release/neuro_admin.exe`.
The final confirmation/label changes also passed seven targeted administrator
widget tests and clean analysis. The portrait PDF was rendered and visually
inspected. Both isolated PostgreSQL servers were stopped after verification.
No live deletion or new migration deployment is claimed. Physical printers/macOS
remain unverified.
