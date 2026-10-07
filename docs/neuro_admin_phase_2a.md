# Phase 2A: shared administrator services and backend safety design

This is an implemented application boundary and a **proposed backend contract**.
It does not enable desktop writes, deploy RPCs, change migrations, or migrate the
mobile client. The full administrator scope includes accounts, physicians, roles,
templates, reports, rosters, assignments and later recommendations/allocation.
The Phase 1 split-pane UI, admin-only/MFA gate and read-only behavior remain.

## 1. Package boundary and implementation status

`neuro_core` remains unchanged, pure Dart, with its existing domain models/rules.
The new `neuro_admin_services` package contains no Flutter imports. Its public
application library is independent of UI/session singletons; an optional separate
`supabase_admin_reader.dart` entry point exposes the read-only Supabase adapter.
One package with separate application/infrastructure source files is sufficient
for this extraction; no additional package graph or service locator is needed.

Dependency direction:

```text
neuro_admin UI ----> neuro_admin_services ----> neuro_core
                          |
                          +-- optional Supabase Dart read adapter
                          +-- timezone data (Europe/Vienna)
neuro_app UI ------> existing implementation (future incremental adoption)
```

| Interface | Contract | Current implementation |
| --- | --- | --- |
| `RosterReader` | `listMonths`, `loadMonth` | Moved `SupabaseRosterReader`, paginated GET-only queries; all physicians and exact stored role identities retained |
| `PhysicianReadService` | `loadPhysicians(includeInactive: true)` | Same adapter; directory identity/rank/capabilities/activity, not a dated absence query |
| `WorkloadReadService` | `forPhysician(snapshot, physician, window)` | `RecordedWorkloadService`; existing calculations moved without duplication |
| `AssignmentValidationService` | `preview(AssignmentValidationRequest)` | Interface only; no fabricated successful validator |
| `AssignmentMutationService` | `assign`, `bulkAssign`, `remove`, `replace` | Interface only; no client-side table writes or mutation adapter |
| `RosterLifecycleService` | `openSelection`, `lockSelection`, `publish`, `createDraftRevision` | Interface only |
| `RosterGenerationService` | `create`, `regenerate` | Interface only; mobile generator not copied |
| `InvitationUserAdministrationService` | `invite`, `updateProfile` | Interface only; provisioning remains server-side |

The desktop's old `lib/data` files are compatibility exports, not second
implementations. The dashboard consumes the shared workload interface. The shared
reader still consumes the current one-roster-per-month schema; it must be upgraded
together with versioning, not pointed at a versioned database unchanged.

Do not extract the entire mobile app at once. New role/template/report or physician
write services should wrap operations extracted from existing screens once their
contracts and server validation are ready. Do not add duplicate desktop rules.
Current projections are read models, not editable aggregates. Role IDs/codes remain
dynamic; fixed `SlotKind`/`DutyRole` conversions cannot be a validation authority.

## 2. Intended roster lifecycle

| Phase | Administrator | Ordinary physician | Authority |
| --- | --- | --- | --- |
| `draft` | May edit incomplete assignments | No self-selection; not the ordinary-user authoritative roster | Working revision |
| `openForSelection` | May manage assignments under server policy | Permitted self-selection only, subject to eligibility/capacity/absence rules | Provisional, not final |
| `locked` | Controlled corrections with a nonblank audited reason | No assignment changes | Not yet published |
| `published` | No in-place assignment editing; explicit create-revision action for corrections | No assignment changes | Final when selected as the current published revision |

`RosterLifecyclePolicy` implements these **intended** predicates; it does not imply
current RLS compliance. Standard transitions: draft -> open or locked; open ->
locked; locked -> published. An explicit audited reopen may move locked -> open.
All transitions require admin+aal2 on the future server operation. Publication
requires locking and a full validation pass. A published row never transitions
back to draft; `createDraftRevision` produces a separate row instead.

Published historical revisions retain their phase. `phase == published` describes
publication history, while `isCurrentPublished` identifies the current authority.
No current-published lookup algorithm is implemented against the legacy schema.

## 3. Minimum versioning proposal (no migration applied)

`202606120001_initial_roster_schema.sql` defines `unique (year, month)` on `rosters`.
That constraint prevents a published October roster and an editable October draft
from coexisting. The proposed minimum extension is:

- Replace that unique constraint with `(year, month, revision_number)` uniqueness;
  add positive `revision_number` (existing records start at 1).
- Add nullable `supersedes_roster_id` referencing the prior revision, with a server
  check that both belong to the same month and that the source is the expected
  current publication. Prevent self-reference/cycles; assign links only at creation.
- Add `is_current_published` boolean and a partial unique index on `(year, month)`
  where true; require `phase = published` when true. Retain old published rows with
  false, rather than deleting or relabeling them as drafts.
- Add nonnegative `content_version` for optimistic concurrency, distinct from the
  immutable revision number, plus publication timestamp/actor metadata. Every
  relevant draft/day/slot/assignment mutation increments content_version server-side.
- Permit at most one working (non-published) revision per month using a second
  partial unique index. Retired publications remain unlimited.

Creation of a revision locks the month, checks the source version/current pointer,
allocates the next revision number, and copies days/slots/assignments under new IDs
in one transaction. Preserve provenance to the source, role/template eligibility
metadata and publication audit records; current editable role definitions alone
cannot reproduce historical meaning. Regeneration is limited to drafts and never
deletes historical publications. A draft containing assignments must reject simple
regeneration and require a separately reviewed reconciliation plan.

Publishing locks the month, verifies the expected draft and current source,
validates the entire plan, clears the old current flag, publishes/promotes the new
revision, and appends its audit event in one transaction. Readers see either the
old or new publication, never a partially published roster. Backfill of current
flags must inspect existing phase data; do not label every existing draft final.
Review existing `published` rows before assigning publication metadata.

All month readers must choose explicitly: administrator working revision, current
published revision, or a particular historical revision. Never use largest ID,
latest creation time, or arbitrary `maybeSingle()` once revisions exist. Ordinary
viewers should resolve the current publication; physician self-selection needs an
explicit open revision with a provisional label. Any additional locked-roster
visibility is a policy decision. This changes existing mobile visibility and must
be coordinated, not silently rolled out with a desktop-only migration.

Historical fairness inputs should choose one authoritative revision per month;
current working-plan counts should use the chosen working revision. Do not sum
draft and published copies. Current read-only totals deliberately retain the
existing all-phase policy until versioning and reporting policy are implemented.

## 4. Current enforcement audit and proposed authorization

Evidence is the checked-in migrations/functions, not a claim that the live project's
policies were introspected. The initial schema uses admin+aal2 for most configuration
writes. Later policies are permissive alternatives, so an older restrictive-looking
policy alone does not establish the effective permission.

| Operation | Current repository evidence | Proposed shared admin rule |
| --- | --- | --- |
| Read roster/physicians/workload | Authenticated reads; inactive physicians/roles and others' absences require admin. No roster-phase read restriction | Authenticated admin; backend reads may use aal1 |
| Preview assignment | No authoritative preview operation | Authenticated admin; read-only aal1 permitted |
| Create/edit/deactivate physicians | Initial admin+aal2 doctors policy | Admin+aal2 |
| Edit another user's profile | Initial admin+aal2; later doctor-own non-privileged update exception | Admin+aal2 for administrator operations |
| Invite doctor/viewer | `invite-doctor/index.ts`: validated user, admin profile, aal2, doctor/viewer-only input | Admin+aal2; privileged key stays on server |
| Create/edit/deactivate roles | Initial admin+aal2 roles policy | Admin+aal2 |
| Create/edit/delete templates | Initial admin+aal2 templates policy | Admin+aal2 |
| Report visibility/order | Writes role and doctor ordering fields under their configuration policies | Admin+aal2 |
| Create/regenerate roster | Initial admin+aal2 roster/day/slot policies; no preservation/phase rule | Admin+aal2; transactional and draft-safe |
| Assignment changes | `202606240002_admin_assignment_policy.sql` replaces admin+MFA with admin-only; `202606240001_doctors_manage_own_assignments.sql` permits doctor-own insert/delete without phase checks | Admin+aal2 plus lifecycle/validation; physician self-selection separately authorized only while open |
| Absence insert/update | Initial own-doctor OR admin policies have no aal2 condition | Admin+aal2 for admin changes; own-doctor policy separately reviewed |
| Absence delete | Initial admin+aal2 plus `202606260002_doctors_delete_own_absences.sql`; an admin linked to that doctor can also satisfy the own-record path | Admin+aal2 for admin changes, with explicit ownership exceptions only for ordinary doctors |
| Phase changes/publish | Roster updates require admin+aal2 but no transition/completeness/atomic-current-publication rule exists | Admin+aal2 and dedicated transactional operation |

`202610040002_viewer_read_only.sql` adds restrictive write policies requiring
admin/doctor roles. It blocks viewer writes, including linked viewers, but does
not add phase or MFA checks for other roles. Authenticated reads of rosters/days/
slots/assignments are currently phase-unrestricted. No active-physician, capacity,
eligibility, full-day absence, or cross-slot overlap enforcement was found in the
assignment policies. SQL uniqueness only prevents the same physician/slot pair.

`requirementFor(AdminOperation)` represents the coherent **proposed** policy:
admin for all admin-service operations, and aal2 for **every administrator write**,
including assignments and absences. The desktop retains its existing stronger
aal2 entrance gate even for reads. This matrix does not alter doctor/viewer access
in the backend/mobile app and must not be used to loosen SessionGate.

Before enabling writes, enforce policies in PostgreSQL and remove direct-table
bypasses, including overlapping permissive and own-doctor paths. Review how legacy
mobile clients continue working during rollout. Future definer RPCs must use a
fixed safe search_path, qualified objects, a trusted owner, explicit actor/profile/
aal checks, and revoked PUBLIC execution with narrowly granted authenticated access.
Caller-supplied actor IDs, role strings, preview flags and dates are never authority.

## 5. Transactional operations proposed

No RPCs are installed in Phase 2A. Names below describe the proposed contract, not
available backend endpoints. Common command inputs are an idempotency `request_id`,
expected `content_version` for existing rosters, and a correction reason where
required. The server derives actor identity and MFA from the validated session.
Use admin+aal2 for these administrator operations. Self-selection requires a
separately scoped doctor endpoint/policy, never an arbitrary physician parameter.

Common transaction protocol: acquire month/roster and affected physician/slot locks
in deterministic order; check expected versions, phase and authorization; validate
against current database state; mutate; advance versions; append audit and store
the idempotent response; commit together. All mutation routes must respect the same
locks, including absence/role changes that can race with assignment validation.
Roster version alone cannot detect changing physician eligibility or absences.
Revalidate dependencies under appropriate locks/serialization. Retry serialization
failures with the same idempotency key, not a new command.

Return structured receipts with request ID, new version, changed IDs and audit
reference (where present). Expected validation failure returns typed per-date
errors with no changed rows; authentication/forbidden/MFA, missing entities, stale
version and idempotency conflicts map to `AdminFailureCode`. Unexpected SQL failures
roll back the entire operation. A response lost after commit is retried idempotently.
An idempotency key reused for a different payload is rejected, not treated as success.

| RPC | Additional inputs | Validation and transaction boundary | Result / failure behavior |
| --- | --- | --- | --- |
| `assign_physician_to_slot` | roster, slot, hospital date, physician, role, backend preview token | Check slot/date/role/roster identity; active physician and eligible ranks/capabilities; whole-day absences; actual UTC interval overlap across adjacent dates; allowed overlap policy; capacity; duplicate; phase/version. Add exactly one assignment with explicit provisional state and audit | `AssignmentMutationReceipt`; stale/invalid target changes nothing |
| `remove_assignment` | roster and assignment ID | Check ownership of assignment by roster, current version, phase and locked correction reason. Remove exact row and audit; no broad physician/date delete | Receipt with removed ID; missing row is not silently successful except replay of the same successful request |
| `bulk_assign_physician` | one roster/role/physician, explicit date+slot targets, preview token | Validate all targets and mutual interactions before inserting any. Default all-or-nothing. Invalid dates cannot be silently skipped. To submit a valid subset, request a new preview for that exact subset | Receipt for all targets, or complete per-date failures with zero assignments applied |
| `replace_assignment` | replaced assignment ID plus one new previewed target | Preview and validation explicitly exclude only the replaced row. Lock old/new physicians and affected slots; validate resulting state; delete+insert+audit in one transaction | Receipt containing old/new IDs. Insert failure rolls back deletion; never clear all occupants or unrelated conflicts automatically |
| `create_roster` | year/month, selected template/configuration version | Check month bounds, absence of conflicting working roster, active role definitions, recurrence rules, hospital dates, DST-safe times and holiday source. Create draft/days/slots atomically. Existing publication is preserved; copying it uses create-revision instead | `RosterRevision` plus generated counts; no partial roster on failure |
| `regenerate_roster` | draft ID/version, expected template/configuration version | Draft only; reject nonempty assignment set until an explicit reconciliation design is approved. Build replacement days/slots and swap within the same transaction, preserve audit and published revisions | Revision with incremented content version and counts; template/DST/conflict failure leaves draft intact |
| `publish_roster` | locked draft ID/version, expected prior current-published ID, publication reason | Verify source/current pointer; validate entire month, eligibility, overlaps, absences, coverage and assignment-state policy; atomically demote old current flag and promote draft, freeze publication and audit | New current `RosterRevision`; old publication remains current on any failure |
| `split_update_absence` | physician, expected absence IDs/versions, selected hospital dates, type, intended retain/remove/add operation | Check all affected ranges, ownership/lifecycle impact and full-day semantics; compute retained ranges without losing note/provenance; split/delete/reinsert and any approved draft-assignment reconciliation together | New/retained/deleted absence IDs and affected roster versions; reject effects requiring published edits or unapproved conflict removal |
| `record_duty24_with_post_duty` | physician, duty date(s), expected absence/affected-roster versions | Record duty marker and linked next **hospital calendar day** post-duty marker together; deduplicate with source linkage; validate blocking consequences. Only this duty workflow adds the next day, not other absence types | Both marker IDs/source links and affected versions; rollback both if either fails. Removal deletes only the generated linked marker, not independent rest records |

Supporting `preview_assignment` is read-only: authenticated admin, no data changes,
consistent snapshot of all relevant facts, per-date results, evaluated policy and
versions, short-lived confirmation token bound to actor, exact payload, replacement
ID/reason and policy version. Token storage/signing is server-controlled; it is not
a client-generated signature or a substitute for commit-time validation. Reads
through the current multi-request roster adapter are not an atomic validation view.

Publication needs an approved minimum-coverage and provisional-state policy.
Current `max_doctors` is capacity, not required coverage (e.g. science capacity 99
must not imply 99 mandatory assignments). Fail closed if required publication
policy/configuration is absent. Holiday handling also needs a real source: the
current mobile generator marks every date `is_public_holiday: false`.

Invitations cross Auth, application tables and email delivery and cannot become a
single ordinary PostgreSQL transaction. Keep a privileged server orchestrator,
idempotent provisioning and a durable delivery/outbox/retry state. Group profile/
physician creation transactionally where possible; reconcile partial Auth creation
and verify compensation failures. The current Edge Function creates Auth user,
profile, optional doctor, then emails via password reset, with best-effort deletes
on failure. Do not copy its multi-request orchestration into either client. Its
mobile reset redirect remains unchanged until desktop recovery support is designed.

## 6. Exact validation and confirmation contract

`AssignmentValidationRequest` carries a roster ID/content version, exact role and
physician IDs, immutable nonempty unique-date `AssignmentTarget`s, optional locked
correction reason, and optional single replacement assignment ID. A null slot ID
requests resolution; zero matches yields `missingSlot`, multiple matches yields
`ambiguousSlot` unless a particular slot is selected. Never select `.first` silently.

Each immutable `AssignmentValidationResult` carries hospital date, slot ID (nullable
on failure), physician ID, role ID, hard errors, and separate advisory warnings.
`isValid` is derived from errors; a missing slot automatically produces an error.
Error codes cover eligibility, absence, overlap, capacity, duplicate, phase/editability,
missing/ambiguous slots, inactivity, stale data and unavailable validation. Warning
codes reserve recent duty burden, weekend imbalance and role over-allocation; no
fairness thresholds, scores or warning calculations are invented in this task.

`AssignmentPreview` verifies that every requested date has exactly one outcome
with matching identities. Partial, duplicated or mismatched responses are rejected.
Advisory previews are never confirmable. Backend previews require an opaque token
and expiry; `AssignmentCommitRequest` rejects expired/invalid/advisory previews at
construction. The backend must verify the token, payload, expiry and latest facts
again: these Dart guards are UX/contract safety, not a security boundary.

The validation service intentionally has no implementation yet. The existing
`neuro_core.AssignmentService` contains eligibility, full-day absence, duplicate,
capacity and configured overlap rules, but uses fixed slot kinds and same-day
time ranges. Mobile bulk replacement additionally clears conflicts/occupants and
performs partial per-day persistence. Do not reproduce either as a supposedly
authoritative dynamic-role validator. Extract/reconcile rules once with regression
fixtures, preserve approved exceptions, and implement equivalent backend checks.
In particular `duty24` is excluded by current `Doctor.absenceOn`, while post-duty
and the added other-absence types block days: do not invent a different clinical
rule based only on the workload category name.

## 7. Europe/Vienna policy and safe incremental refactor

The scheduling timezone is **Europe/Vienna**, independent of device settings.

- `roster_days.date` and absence dates are hospital calendar dates, not instants.
  `HospitalDate` is a validated value type with calendar-day arithmetic. Existing
  DateTime read models/selection use its UTC-midnight compatibility representation;
  never shift that date-only value with `toLocal()`.
- Template start/end are Vienna wall-clock times. Future generation resolves each
  date/time with IANA data into UTC instants before storing `timestamptz`. Never
  append Z to an unconverted template clock. Resolve start/end independently;
  future overnight templates require an explicit end-day offset/schema rule.
- `ViennaSchedulingTime.resolveWallTime` rejects nonexistent spring-forward times.
  Repeated autumn times require an explicit earlier/later choice. Never silently
  normalize a gap or assume 24 elapsed hours equals one calendar day.
- Read timestamps must carry Z or an offset; naive timestamps fail visibly.
  The desktop now renders instants in Europe/Vienna, retaining the stored roster
  date for grouping. Winter/summer/DST and alternative local-zone tests cover this.

Existing violations and required extraction points:

| Source | Problem | Minimum later correction |
| --- | --- | --- |
| `neuro_app/lib/screens/admin_rosters_screen.dart`, `_RosterGenerator.generate` | Builds `${dateKey}T${template.startTime}:00Z`; treats local templates as UTC | Extract generation into shared planning/server operation and use explicit Vienna conversion before new writes |
| `neuro_app/lib/services/supabase_roster_service.dart`, `loadRoster` | `toLocal()` depends on device, then derives slot date from start timestamp; reduces overnight interval to LocalTime | Adopt shared date/instant projections; use stored roster-day DATE and Vienna display, preserve full intervals |
| `neuro_app/lib/screens/month_screen.dart`, duty/post-duty/range helpers | Local-midnight DateTime plus Duration(days:1) can cross DST incorrectly | Extract calendar arithmetic with HospitalDate, keeping clinical absence semantics |
| Prior `neuro_admin/lib/roster_dashboard.dart` | Workstation-local display | Fixed here to shared Vienna conversion; data untouched |

The new package uses the cached `timezone ^0.9.4`, compatible with the existing
mobile transitive dependency, without adding mobile plugins. It bundles IANA data
and needs no runtime zone lookup/network. Keep tzdata versions aligned across
clients and PostgreSQL when writing is introduced. macOS native qualification is
still outstanding, although these helpers contain no OS-specific APIs.

An explicit range probe found that the cached 0.9.4 Vienna table ends at
`2037-10-25T01:00:00Z`; without a guard, its summer 2038/2050/2100 conversions
incorrectly use the final winter offset. Helpers now reject instants at/after that
boundary with a visible FormatException, including during roster decoding, instead
of guessing. This deliberately limits supported duty times despite the schema's
2000–2100 year range. A reviewed tzdata/library upgrade or server conversion must
extend the range before scheduling later years. The library's
[release history](https://pub.dev/packages/timezone/changelog) also records newer
tzdata releases and API changes; Phase 2A does not silently upgrade the mobile
calendar dependency. Current 2026 DST tests and the explicit unsupported-range
test are both required regressions for any later upgrade.

**Do not blanket-shift existing timestamps.** Distinguish incorrectly generated
rows from correctly entered/imported instants using provenance and a read-only
audit first. Review a correction/backfill against clinical expectations and
historical publications. The desktop continues to interpret persisted timestamps
as instants; known bad source data is not silently repaired. Mobile/core/schema
remain unchanged in Phase 2A.

## 8. Full administrator parity extraction plan

| Workflow | Current owner/evidence | Reusable operation to extract next |
| --- | --- | --- |
| Invite doctor/viewer | `admin_invite_doctor_screen.dart` -> `invite-doctor` Edge Function | Typed invitation facade, server idempotency/delivery result; no UI or secret keys in shared layer |
| Physician creation/profile/activation | `admin_doctors_screen.dart` direct doctor CRUD; `SupabaseDoctorService` active-only reader | Physician query + create/edit/activate/deactivate commands, capability/rank validation; preserve inactive history; account creation remains distinct from unlinked physician creation |
| Physician print ordering | `admin_doctors_screen.dart::_swapPrintOrder` | Atomic reorder command (current two updates can partially fail) |
| User profile administration | Profile records and invitation function; no complete standalone viewer-management screen found | Typed non-privileged profile update; separate future activate/disable Auth-account operation with explicit server authorization; never confuse doctor activity with login revocation |
| Role CRUD/deactivation and eligibility | `admin_roles_screen.dart` | Role service preserving ID/code, ranks/capabilities, capacity, display order and historical definitions |
| Recurring templates | `admin_role_templates_screen.dart` form/persistence | Template commands with role identity, weekday rules, monthly-day validation and wall-clock times; preserve existing recurrence behavior before adding new policies |
| Create/regenerate month | `_RosterGenerator` embedded in `admin_rosters_screen.dart` | Generation planning plus transactional create/regenerate service; preserve published versions, define holiday source and explicit DST rules |
| Phase/revision/publish | Phase enum exists; no complete safe publishing service found | Lifecycle/versioning service and RPCs above; coordinate ordinary-user readers |
| Manual assignment/removal | `day_screen.dart::_toggleAssignment`, core `AssignmentService` | Validation contract + single assign/remove command, preserving approved domain rules |
| Bulk/replace/remove | `month_screen.dart::_assignSelectedDatesToSlotKind`, `_removeRoleFromSelectedDates`, `_persistAssignmentChanges` | Exact-role-ID targets, explicit replacement preview, atomic mutation; no silent first-slot choice or partial per-day commit |
| Absence split/block/rest | `month_screen.dart::_setSelectedDatesAsDuty24`, `_setSelectedDatesAsBlockingAvailability`, `_removeAvailabilityFromSupabase` | Shared date/range planning, source-linked duty/rest and transactional split/reconcile; other absences block their whole day, not the following day |
| Report visibility/order | `admin_report_settings_screen.dart`, `SupabaseRosterService` report methods | Shared report configuration query/update and atomic reorder; keep PDF/UI rendering out of application services |

Sequence: establish behavioral fixtures around each existing operation; extract its
application contract/rules without copying UI; implement a safe backend adapter;
switch one mobile call path and desktop consumer to that same service; remove the
old screen persistence only after parity/security tests pass. Phase 2A switches only
desktop reads and workload, not mobile operations. Recommendations and automatic
allocation remain separate future consumers of the same validated command path.

## 9. Remaining gates before Phase 2B writes

1. Approve and migrate versioning, publication/read visibility, metadata snapshots
   and optimistic concurrency; coordinate mobile compatibility and preservation.
2. Install/test authoritative preview and transactional assign/remove/replace/bulk
   endpoints; enforce admin+aal2, phase rules, idempotency and audited corrections.
   Remove direct-table/own-record bypasses without breaking approved self-selection.
3. Extract/reconcile dynamic-role eligibility and overlap rules, absence/rest
   handling and clinical publication completeness; no enum-based role guessing.
4. Audit existing timestamps; deploy Vienna-safe generation and consistent mobile
   reads before relying on time-overlap validation for real scheduling.
5. Test concurrency (capacity and absence races), token expiry/staleness, whole-batch
   rollback, retry after lost response, viewer/doctor/admin authorization and
   publication readers against an isolated backend; then review live read behavior.

The repository is ready for Phase 2B preview/UI integration work against these
contracts. It is **not ready for confirmed production assignment writes** until
these server/data gates are resolved. No placeholder write buttons were added.

## 10. Verification record (2026-10-07)

Started on `feature/neuro-admin-desktop` at `833fcba`. Only the full-administrator
scope note was uncommitted. Baseline formatting, analysis, 19 desktop tests,
Windows release build and 10 core tests passed before checkpoint `5df7b97`.

Final verification:

- `neuro_admin`: `dart format lib test` clean (14 files), `flutter analyze` no
  issues, `flutter test` 19 passing tests, `flutter build windows` successful.
- `neuro_admin_services`: `dart format lib test` clean (15 files), `dart analyze`
  no issues, `dart test` 18 passing tests. This test run needs no Flutter SDK API.
- `neuro_core`: `dart test` 10 passing tests; no source changes.
- `git diff --check` passed. No `neuro_app`, `neuro_core` or `supabase` changes;
  no mutation/RPC calls in desktop/shared production code and no Flutter imports
  in the new package. Desktop authentication/MFA code is unchanged.

Regression coverage includes existing access/GET-only read/calendar/workload
behavior, explicit Vienna UI timestamps, lifecycle matrix, fail-closed authorization,
preview identity/completeness/expiry and replacement binding, hard-error versus
warning separation, inactive directory reads, date normalization, DST gaps/folds,
device-independent display, and timezone-data range rejection.

Tests used local fixtures/loopback HTTP, not authenticated live Supabase or
production writes. No live-backend verification is claimed for this refactor.
The plain release build requires the documented public runtime definitions when
rebuilt for a real Supabase project. macOS build/signing remains unverified here.
