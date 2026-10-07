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
- Historical roster-date coverage out of 90; missing dates may indicate incomplete
  history. Even 90/90 dates does not prove all duties or markers were entered.

24-hour markers have no confirmed/provisional state and do not prove a completed
24-hour shift. They are never inferred from DutyRole, role names, or slot length.
These are descriptive recorded-data counters, not fairness or recommendation scores.

### Known role definitions from checked-in migrations

| Code | Seeded definition | Classification evidence |
| --- | --- | --- |
| SUL | Stroke Unit Leader | Stroke-unit station role |
| SU1 | Stroke Unit Team 1 | Stroke-unit station role |
| SU2 | Stroke Unit Team 2 | Stroke-unit station role |
| AMB | Ambulance (Outpatient Clinic) | Ambulance role |
| SCI | Science Slot | Science role |
| SON | Neurosonology | Separate role; not inferred as station/ambulance/science |
| NVB | Neurovascular Interdisciplinary Board | Separate board role |
| OFO | OFO Board | Separate board role |
| ICB | Not seeded in repository | Mobile code maps it to ambulance, but no authoritative DB definition is checked in |
| 24-hour duty | No seeded role code | Stored as absence/day marker `duty_24` |

These are seeded definitions, not a verified inventory of live database roles.
Roles are editable and have no explicit station/ambulance/science category.
Custom roles, renamed codes, and ICB require confirmation against actual role
records and clinical intent. Grouped category metrics are therefore deferred;
exact-role totals are displayed without invented classification. A future policy
must also decide how draft/provisional duties contribute to fairness.

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
