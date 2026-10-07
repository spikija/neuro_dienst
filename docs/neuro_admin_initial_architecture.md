# NeuroDienst Admin: Phase 1

## Scope

`neuro_admin` is the Windows-first desktop administrator client. A macOS runner
is included for later qualification. The split layout contains a monthly
calendar on the left and physicians, selected-physician details, and workload
on the right. Month switching, refresh, error/retry, and empty states are present.
No assignment editing, publishing, recommendation ranking, automatic allocation,
or drag/drop assignment is implemented. No production mobile code was moved.

## Access and backend

The client connects to the same Supabase project as `neuro_app` using
`SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` compile-time definitions. Missing
configuration is explicit; there is no demo fallback. Never embed a service-role
or secret key. Obvious secret keys and service-role JWTs are rejected locally.
The backend remains responsible for authorization; no RLS or migration changes
were made. Supabase Auth necessarily performs login/challenge/session operations;
application-table data access is strictly SELECT/GET, with no INSERT/UPDATE/DELETE.

Access requires a server-validated Supabase session, `profiles.role == admin`,
and MFA assurance level aal2. Doctor, viewer, and missing-profile accounts receive
an access-denied screen. The existing backend/mobile viewer role remains unchanged.
Existing verified TOTP factors can be challenged. Enrollment and password recovery
remain in the existing app; callback schemes have not been copied or registered.
Session changes hide the dashboard while access is rechecked. No roster reads
start before the access check succeeds.

## Read model and shared code

`neuro_core` supplies Doctor, rank/capability/availability types, CalendarDayInfo,
RosterPhase, and AssignmentState. Admin-specific immutable database projections
preserve role ID/code/name, assignment ID/state/roster phase, full UTC timestamps,
and the date in `roster_days.date`. They are not assignment-editing models.

The former scaffold reader forced every role through SlotKind and DutyRole and
could not represent overnight shifts. Phase 1 removes that conversion entirely:
unknown/custom role codes remain intact and never become science. Time spans may
cross midnight. Inactive physicians and inactive roles are loaded for history.
Missing physician, role, or slot references fail visibly instead of dropping
assignments and understating totals. Unknown enum values fail visibly too.

Reads are paginated (500 rows) with ID batches of 100. A selected month loads
its dates plus the preceding 90 days, associated duties/assignments, physicians,
roles, and overlapping absence periods. Roster creation timestamps are never used
for workload selection. Multiple requests are not an atomic database snapshot;
refresh is needed if other clients edit the schedule during loading.

## Workload definitions and limits

The history window is **[first day of selected month minus 90 days, first day of
selected month)**. This is previous 90 days relative to the selected month, not
three calendar months and not an implicit rolling window relative to today.
Current-month counts use [month start, next month start). All four roster phases
are included; assignments retain their phase for later explicit policy filtering.

For each physician the client currently displays:

- Current-month assignment count, distinct assigned days, and confirmed/provisional
  counts.
- Current-month and previous-90-day assignment counts and distinct assigned days
  per exact database role ID, displaying its code/name. Multiple slots of the
  same role on one date count as one role-day.
- Previous-90-day recorded 24-hour-duty days from `absences.type = duty_24`, with
  overlapping/duplicate date ranges deduplicated and clipped to the date window.
- Saturday/Sunday 24-hour-duty days separately (not public-holiday classification).
- Previous-90-day station, ambulance, science and other-role days using the explicit
  `WorkloadCategory` policy. Each category counts distinct assignment dates across
  all its roles: SUL + SU1 on one date is one station day, not two. A date with
  different categories contributes once to each; category totals are not additive.
- Historical roster-date coverage out of 90; missing dates may indicate incomplete
  history. Even 90/90 dates does not prove all duties or markers were entered.

24-hour markers have no confirmed/provisional state and do not prove a completed
24-hour shift. They are never inferred from DutyRole, role names, or slot length.
These are descriptive recorded-data counters, not fairness or recommendation scores.

### Known role definitions from checked-in migrations

| Code | Seeded definition | Desktop category |
| --- | --- | --- |
| SUL | Stroke Unit Leader | `station` |
| SU1 | Stroke Unit Team 1 | `station` |
| SU2 | Stroke Unit Team 2 | `station` |
| AMB | Ambulance (Outpatient Clinic) | `ambulance` |
| SCI | Science Slot | `science` |
| SON | Neurosonology | `other`: separate specialty, not inferred as outpatient/station |
| NVB | Neurovascular Interdisciplinary Board | `other`: board |
| OFO | OFO Board | `other`: board |
| ICB | Not seeded in repository | `other`: mobile maps to ambulance without a checked-in database definition |
| All other role codes | Configurable/custom | `other`, including renamed or differently cased codes |
| 24-hour duty | No seeded role code | `duty24h`, sourced only from absence/day marker `duty_24` |

These are seeded definitions, not a verified inventory of live database roles.
Roles are editable and have no explicit station/ambulance/science category.
The mapping in `neuro_admin/lib/data/workload_category.dart` uses exact seeded
codes from `supabase/migrations/202606120001_initial_roster_schema.sql`; it never
uses SlotKind/DutyRole, names, fuzzy matching or duration. `duty_24` is an absence
type from `202606260001_absence_duty_ef_types.sql`, not an assignment-role code.
Custom roles, renamed codes, and ICB require confirmation against actual role
records and clinical intent and remain `other`. Original role IDs/codes/names and
per-role counts remain visible. Roles whose meaning changes while retaining a
seeded code cannot be detected from the current schema; versioned backend category
metadata is needed before these counters become inputs to fairness decisions.
Both provisional and confirmed assignments and all phases currently contribute
to category-day counts, with assignment-state totals shown separately. This is
descriptive planned/recorded workload, not completed work or a fairness score.

## Desktop multi-day selection

`CalendarSelection` owns an explicit, externally immutable `Set<DateTime>` in the
dashboard state. Values use year/month/day at UTC midnight without timezone
conversion, matching the stored roster-day DATE. It has no physician/role/backend
dependency. Future bulk workflows can take a copy of these dates, choose one
role and physician, and preview validation results for each date before submitting
an approved write operation. Selection itself provides no eligibility guarantees.

- A left click replaces the selection; left-button dragging adds every crossed
  day cell, forwards/backwards and across weeks. Crossing the same cell twice
  does not duplicate it. Fast movements use line/cell intersections between
  pointer events. A diagonal path selects spatially crossed cells, not every
  chronological date between the endpoints.
- Highlighting and the selected-day count update live. Details follow the last
  crossed day. Mouse-up or cancellation ends dragging, including release outside
  the grid. Right/middle clicks do not select. No Ctrl/Shift additive mode exists.
- Mouse pans are claimed by the grid, scrolling is disabled during a dashboard
  drag, and text selection is disabled within the day cards. There is no edge
  autoscroll or drag-to-another-month behavior. Keyboard Tab plus Enter/Space and
  accessibility activation select a single date; touch dragging is not implemented.
- Physician selection/filter changes preserve dates. Changing month clears them;
  refreshing the same roster preserves them. Leading/trailing blank cells do not
  represent dates. Clicking blank padding leaves the selection intact.
- Dates without generated roster rows may be selected and are clearly labeled
  `No roster day`; details explain that no generated day exists. Future writes
  must reject these dates or explicitly generate the missing roster data first.
- Selection is local only: no repository or Supabase call occurs. Losing the
  dashboard (for example sign-out) discards its state.

## Roster phases and the future write boundary

The phase chip next to the month selector distinguishes all persisted phases.
`published` is labeled as the authoritative end-user roster; `draft` is an
administrator working plan; `openForSelection` and `locked` identify the selection
period and its closure respectively, neither equivalent to publication. All four
remain inspectable and strictly read-only in this desktop client.

The current backend is not a versioned draft/published workflow. The initial
schema has `unique (year, month)` on `rosters`, so an independent draft working
copy cannot coexist with a published roster for the same month. The phase label
does not create that separation or change what the mobile app can read.

Before Phase 2/3 writes, agree and implement a backend contract (separate task):

1. Define whether editing is draft-only and how open/locked selection relates to
   administrator editing. Enforce that decision on every assignment/slot mutation
   on the server, including mobile and direct API calls. Published data must be
   immutable; a correction should create a new draft/revision.
2. Choose revision/working-copy storage and the authoritative published revision.
   Update uniqueness and reader/mobile visibility deliberately. Avoid counting
   both working and published versions as workload for the same dates.
3. Provide transactional bulk validation/writes with capacity, eligibility, full-day
   absence/rest rules, time overlap and date/role checks. Return per-day preview
   errors, revalidate at commit and detect stale revisions/concurrent editors.
4. Publish through one atomic server operation: validate administrator/MFA, lock
   or check the expected revision, validate the entire draft, atomically select
   the authoritative revision/change phase, and record an audit event. Roll back
   everything on failure; no client-side chain of independent updates.
5. Audit existing permissive policies before relying on this boundary. In particular,
   `202606240002_admin_assignment_policy.sql` permits admin assignment writes
   without an aal2 condition, and `202606240001_doctors_manage_own_assignments.sql`
   permits own insert/delete without a phase condition. The later viewer policy
   blocks viewer writes but does not add phase/MFA enforcement for admins/doctors.
   Keep desktop admin/aal2 checks; backend changes need explicit review across both
   clients. No policies, functions, migrations or mobile files were changed here.

## Timezone semantics

Database timestamps remain UTC instants. Duty times display in the workstation's
local timezone with both start/end dates, including overnight duties. Workload
and calendar grouping use the stored roster-day DATE, represented as UTC midnight
solely for date arithmetic; they are not shifted into the workstation timezone.
The mobile generator currently writes template clock times with a Z suffix. This
existing hospital-timezone ambiguity is not repaired in the desktop reader.
Before Phase 2, define the hospital timezone and reconcile generation/display
semantics consistently across clients, including DST.

## Future phases and extraction candidates

1. Phase 1: authenticated read-only calendar, physician details and descriptive workload.
2. Phase 2: manual administrator assignment (not started).
3. Phase 3: draft/publish lifecycle.
4. Phase 4: candidate recommendation/fairness scoring.
5. Phase 5: automatic allocation.

Later extraction candidates remain SupabaseDoctorService, SupabaseRosterService,
shared authentication/MFA, and roster write operations embedded in the mobile
month/day/admin screens. Extraction must resolve dynamic role metadata, timestamp
semantics, transaction/concurrency behavior, and server-side scheduling validation.
`device_calendar` is mobile-only (Android/iOS) and is not a desktop dependency.
No new state-management package or mobile-app dependency was introduced.

## Platforms and local verification

Windows title/product: NeuroDienst Admin; executable: neuro_admin.exe.
macOS bundle ID: io.neurodienst.neuroAdmin, distinct from neuro_app. Both macOS
entitlement files enable outbound networking. macOS builds, signing, notarization,
plugin integration, and authentication behavior still need testing on a Mac;
no macOS build is attempted on Windows.

From neuro_admin:

```powershell
dart format lib test
flutter analyze
flutter test
flutter build windows
flutter run -d windows --dart-define-from-file=../neuro_app/.env.supabase.json
```

The last command uses the existing local ignored configuration file; never commit
that file or paste keys into source. For other environments pass the two public
configuration definitions explicitly. Run `dart test` in neuro_core as well.
Tests use fake gateways/readers or a loopback HTTP server, not production data.
Live login, MFA and authenticated loading require an actual administrator to sign
in locally; automated test success must not be reported as live verification.

## Verification record (2026-10-06)

- `dart format lib test`: clean.
- `flutter analyze`: no issues.
- `flutter test`: 13 tests passed, including loopback backend contracts and UI.
- `flutter build windows`: release build passed.
- `dart test` in `neuro_core`: 10 tests passed. An initial concurrent invocation
  hit an SDK cache file lock; the sequential rerun passed.
- Local public configuration exists. GET to Supabase Auth settings returned 200.
- Configured Windows debug build initialized Supabase. Flutter's attached run
  lost its device connection; launching the built executable standalone produced
  a responding NeuroDienst Admin window.
- Actual administrator login, real MFA, authenticated data loading, and real
  doctor/viewer rejection remain unverified without a local account sign-in.
  No live database mutations or fabricated verification results were used.

Before Phase 2, also resolve server-side capacity/eligibility/overlap enforcement,
atomic writes and concurrent edits, roster-phase policy, authoritative role
classification, and historical role-definition versioning. Displayed role names
currently come from present-day role records, even for historical assignments.

## Baseline verification (2026-10-07)

The starting tree on `feature/neuro-admin-desktop` was clean at `c2f8d00`
(`19.2`); the Phase 1 implementation, MFA refresh-loop fix and password visibility
button were already committed. Reverification passed: formatting (no changes),
analysis (no issues), all 13 desktop tests, Windows release build, and all 10
`neuro_core` tests. This documentation checkpoint records the verified baseline.

The administrator reports successful live desktop login/MFA and authenticated
read-only roster/workload loading. This supersedes the earlier pending live-login
status above; it is user-reported verification, not a new automated live sign-in.
Real doctor/viewer rejection has not been independently verified against the live
backend; both roles are rejected by the automated access-contract tests.

## Selection and workload verification (2026-10-07)

Phase 1 remains read-only and now includes explicit category-day totals, phase
descriptions and local multi-day selection. Final checks passed:

- `dart format lib test`: 14 files, no remaining formatting changes.
- `flutter analyze`: no issues.
- `flutter test`: 19 tests passed. Coverage includes admin/MFA access and refresh
  behavior, denied doctor/viewer access, GET-only paginated reads, inactive history,
  missing mappings, 90-day boundaries, weekend markers, category-day deduplication,
  assignment states, pointer selection in both directions/across weeks, release
  outside the grid, cancellation, no selection-triggered reads, physician/month
  behavior, and restored scrolling in an 800x500 window.
- `flutter build windows`: release executable built successfully. This plain
  build is unconfigured; run/build with the documented local public definitions
  to connect to Supabase.
- `dart test` in `neuro_core`: 10 tests passed.

The new interaction was verified with Flutter widget tests, not a new manual live
desktop session. Live authentication/loading remains the user-reported result
above. No production backend data, mobile code or shared-core code was changed.
No new packages or platform-specific APIs were introduced; macOS qualification
remains pending. Phase 2 can proceed to design and per-day validation previews,
but assignment writes should wait for the server-side lifecycle, authorization,
validation/concurrency and timezone decisions documented above.
