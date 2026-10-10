# Phase 2E: desktop workspace, Austrian calendar and administrator operations

## Scope and deployment

This milestone adds a three-pane desktop workspace, compact selection/roster
menus, role chips, nationwide Austrian holidays, create/regenerate previews,
transactional unassignment, and screen-only role/physician reports. Automatic
allocation, silent replacement, publishing/revision creation, and PDF/printing
are not implemented. Mobile and core files remain unchanged.

Apply `supabase/migrations/202610100001_admin_workspace.sql` **after** all earlier
migrations, including `202610090002_roster_version_safeupdate.sql`. This is a
forward migration: it creates functions and a private receipt table, without
rewriting existing schedules or changing mobile RLS. No service-role key is used.
The new actions need these RPCs; deploying desktop alone does not deploy SQL.

## Workspace and selection

The calendar, daily roster and physician/validation panel use flexible 10:5:5
proportions. Below a 1180 logical-pixel workspace width the panes remain available
through horizontal scrolling, with independent vertical scrolling. There are no
mobile bottom sheets. Toolbar menus group selection and roster operations;
selection help is a tooltip, not permanent instructional text. The old heading,
standalone selection buttons and permanent selected-day message are removed.

Role chips retain exact database IDs. AMB, ICB and custom roles remain separate.
Clicking a role in the middle pane activates the same chip/validation role. A
single day shows actual stored Vienna times, occupants, assignment state and
capacity. Multi-date selection shows per-date occupancy/missing-slot summaries.

Assignment mode retains month-wide validity, warning/blocked/neutral states,
automatic valid-date preselection, manual toggles and constrained additive drag.
Holiday icons and tooltips remain visible alongside selection/conflict icons.
To remove assignments from occupied days, choose **Select occupied days for
removal** in Selection. This explicitly switches to unrestricted date selection
and hides Apply/assignment validation. It does not make blocked dates assignable.
Turn the mode off to recalculate the normal assignment selection.

## Austrian holidays and scheduling time

`AustrianHolidays` is an offline, Flutter-free Gregorian calculation over the
HospitalDate range (years 1–9999). It includes only Austria's nationwide statutory
holidays: nine fixed dates and Easter Monday, Ascension, Whit Monday and Corpus
Christi. Movable offsets are +1, +39, +50 and +60 days from Gregorian Easter.
Coincident holidays retain both names (e.g. 1 May 2008). Regional, school and
patron-saint holidays are excluded. The provider represents the current national
calendar rules, not a reconstruction of historical legislation for ancient years.

Reference: [Austrian statutory holiday list, RIS](https://www.ris.bka.gv.at/eli/bgbl/1957/153/A1P1/NOR40213432).
The SQL `austrian_holiday(date)` mirrors the algorithm and names; cross-year tests
exercise both implementations. `AT-national-gregorian-v1` is the provenance label.

The shared roster reader derives holiday/weekend metadata from stored DATEs, so
old mobile-generated rows with false holiday flags display correctly without
rewriting them. Reports use the same provider. Working-day selection excludes
weekends and national holidays; it does not infer absence or role eligibility.
Existing assignment validation remains authoritative for assignability: a public
holiday is not a blanket prohibition on hospital duty.

New generation persists correct `roster_days` metadata. For mobile recurrence
parity, an `every_weekday` template still generates Monday–Friday slots on public
holidays. A monthly-day template may generate on a weekend or holiday; impossible
dates (31 April) generate no slot. No new holiday-specific template policy is
invented.

PostgreSQL resolves template times in `Europe/Vienna`, independently of session
timezone. Plans reject DST gaps and folds instead of silently normalizing them.
Dart retains bundled timezone history and extends later years with the current
EU recurrence: transitions at 01:00 UTC on the last Sundays of March/October,
CET/CEST offsets. This removes the former 2037 rejection rather than freezing
future dates to winter time. Reference: [Directive 2000/84/EC](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX%3A32000L0084).
Future legislative changes require updating that policy and qualification against
server tzdata. The existing database month range remains 2000–2100.

## Transactional roster generation

`SupabaseWorkspaceService` implements the shared `RosterGenerationService`.
`admin_preview_generation` reads active roles/templates, computes all month dates,
Vienna instants/capacities, and a deterministic slot delta. UI shows draft phase,
calendar/weekday/holiday counts, role/time summaries, slot additions/removals and
affected assignments. Creation requires Preview followed by Create roster.

`admin_apply_generation` independently recomputes under the same table-lock order
as assignment additions. It enforces authenticated admin + AAL2, rejects an
existing month for creation, and permits regeneration only of an existing draft.
Open, locked and published rosters are never overwritten by this operation.

Exact date/role/start/end/capacity matches retain slot IDs and assignments, with
occurrence numbering for duplicate templates. Obsolete empty slots may be removed;
any obsolete occupied slot blocks the whole operation. A capacity/time/role
change to an occupied slot therefore requires a future reconciliation workflow.
Roster IDs and day IDs are retained; no delete-and-recreate roster cascade occurs.

The server hashes the complete plan including configuration, existing roster
version and exact slot delta. This fingerprint is a concurrency token, **not** an
authorization credential. Client plans expire locally after five minutes for
review freshness; the server always recomputes and checks the fingerprint, not
the client's expiry clock. Role/template changes invalidate plans even though
legacy template writes do not advance every roster version. The RPC creates or
updates all days/slots, writes the audit record and durable response in one
transaction. An audit/constraint failure rolls back the entire operation.

Receipts are scoped by actor and UUID; identical retries return the original
response even after a version change. Reusing an ID with a different payload is
rejected. Transport/invalid-response failures retain the exact request for retry.
Private helper functions and receipt tables have no authenticated table access.
Locks are deliberately coarse and block competing legacy writers briefly; this
is a scalability tradeoff inherited from the first assignment RPC.

## Unassignment

`AssignmentRemovalPreview` captures immutable selected dates, explicit role/all
scope, exact affected facts and no-op dates. `AssignmentRemovalService` is distinct
from additions/replacement. `admin_remove_assignments` is the strongly typed RPC
equivalent of separate role/all-role endpoints: `scope=role` requires a role ID;
`scope=all` rejects a role ID. Dates must belong to the reviewed roster month.

Both actions enumerate physician, role, date and assignment state, show no-op
dates, and require a confirmation checkbox. The all-role action has destructive
styling. Locked rosters additionally require a nonempty correction reason.
Draft/open allow admin removal; published blocks it pending revision support.

The backend checks admin/AAL2 again after acquiring writer-conflicting locks,
checks roster version, re-enumerates the exact scope and deletes only assignment
rows. Every removed assignment receives an audit entry with actor/request/roster,
role, slot, physician, date, prior state, scope and reason. Slots, roles, doctors
and absences are never deleted. A failure rolls back deletion, version, audit and
receipt. Success or closing an uncertain operation reloads the desktop snapshot.

## Reporting parity

`SupabaseReportingService` loads the same shared roster facts and actual role
visibility/order settings, rechecking content version after configuration reads.
`FactualReportProjection` builds exact-ID role columns or physician columns sorted
by print order, rank, surname and first name. Both provisional and confirmed facts
survive; historical assigned inactive physicians remain columns. The shared text
adapter preserves the mobile physician-role priority (SUL/SU1/SU2/AMB/ICB/SON/NVB/
OFO/SCI), without using that priority as classification or merging identities.
Absences take precedence in physician cells, with full factual labels. Tooltips
retain the underlying assignment/state even when an absence is displayed.

The screen offers a wide, scrollable table with role/physician switches, names,
holiday/absence notes and reload/error states. PDF/print/personal-report UI is
deferred; existing mobile PDF code is unchanged, not duplicated into desktop.

Deliberate factual corrections relative to legacy mobile presentation: all slots
for a role/day are included, historical physicians are retained, custom roles
never collapse into enum fallback columns, configured empty visibility remains
empty, and configured historical role identities are not removed merely because
a role is now inactive. Absence labels are descriptive rather than using the
mobile's generic vacation abbreviation. Both clients read the same persisted
facts; mobile rendering remains unchanged. Migrating mobile to this projection
and unifying localization/print adapters remains a separate task.

## Verification and remaining deployment work

Automated checks cover the requested desktop sizes; date selection, heatmap and
reload behavior; removal scope/confirmation/retry; generation preview blockers;
report switching/visibility/history; holidays including coincident dates; and
future Vienna transitions. Native backend tests cover authorization, recurrence,
holiday metadata, duplicate months, protected phases, preserved occupied slots,
destructive rejection, audit rollback, no-op dates, scope isolation, versioning,
idempotency and multi-connection races. They pass with the actual `safeupdate`
extension enabled. All mutation tests use isolated disposable databases, not
production data.

Final verification for this milestone:

- Desktop `dart format lib test integration_test`, `flutter analyze` and
  `flutter test`: clean analysis, **59 tests passed**.
- Shared services `dart format lib test`, `dart analyze`, `dart test`: clean
  analysis, **47 tests passed**.
- Core `dart test`: **10 tests passed**; no core files modified.
- `flutter build windows`: release build succeeded. macOS was not tested.
- Workspace SQL: **19 native PostgreSQL tests passed** on Windows PostgreSQL 17
  and again on Linux PostgreSQL 14 with `safeupdate` enabled in both write RPCs.
  Both isolated test clusters were stopped after verification.
- Existing assignment SQL: **33 isolated tests passed**. Viewer access tests
  blocked all **33 table-write paths**; viewer invitation/doctor provisioning
  regressions also passed without sending emails.
- Live Windows integration: refreshed an expired saved session through normal
  Supabase authentication, then required server-verified admin and AAL2. Reports
  matched exact roster assignments and retained historical physician columns.
  The displayed 31-day month contained one national holiday; its calendar marker
  and working-day exclusion passed. Assignability remained 6 valid (all warning
  valid), 15 blocked and 10 neutral dates. No roster/assignment data was changed.
- The new workspace preview RPC was unavailable on the live backend. Therefore
  live creation, regeneration and unassignment are **not verified**. Apply the
  forward migration and designate an unused test month before that verification.
  The production migration was not applied by this task.

Backend tests can be rerun with `node supabase/tests/admin_workspace.mjs <tools>`
(tools contains `@electric-sql/pglite`), or `--postgres` with `pg` installed and
`NEURO_ADMIN_TEST_DATABASE_URL` pointing to an empty loopback-only database whose
name begins `neuro_admin_test_`. `--safeupdate` additionally requires the native
extension. The harness refuses nonlocal databases and nonempty native fixtures.
