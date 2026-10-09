# Phase 2C: transactional manual assignment creation

Implemented in the repository; migration deployment and live writes are separate
verification steps. The desktop makes assignment writes exclusively through
`admin_apply_assignments`. Removal, replacement and published-revision creation
remain disabled. Existing mobile/core code and existing RLS permissions are not
changed. No service-role key is used or embedded in desktop/shared services.

## Forward migration and RPC

`supabase/migrations/202610080001_admin_assignment_rpc.sql` adds:

- `rosters.content_version bigint not null default 1`, constrained positive.
  Existing rows receive a real server stamp without deleting/recreating any data.
- A roster trigger that sets inserts to version 1 and makes every update advance
  the old version, ignoring client attempts to reset the stamp.
- Statement triggers on assignments, days, slots, physicians, roles and absences
  that advance all roster versions. This deliberately broad invalidation covers
  cross-month overlaps and shared eligibility/absence changes, including legacy
  mobile DML. It changes metadata only, not legacy assignment permissions/rules.
  Transition tables suppress invalidation for zero-row statements, so a viewer's
  RLS-filtered UPDATE/DELETE cannot change version metadata.
- Private, RLS-protected `admin_assignment_requests` durable success receipts.
- A restricted overlap-policy helper and the public authenticated RPC below.

```text
admin_apply_assignments(
  p_roster_id uuid,
  p_expected_version bigint,
  p_physician_id uuid,
  p_role_id uuid,
  p_dates date[],             -- 1..31 distinct non-null calendar dates
  p_request_id uuid,
  p_reason text default null
) -> jsonb
```

Success includes `ok`, `requestId`, `rosterId`, `contentVersion`, per-date `results`
and `addedAssignments` (assignment ID, exact slot ID, confirmed state). Rejection
includes `ok:false`, an operation `code` and per-date `{date,slotId,errors:[codes]}`.
Authorization/invalid-envelope/internal failures return no roster details.

The security-definer function uses an empty search path and schema-qualified table
references. It requires a real `auth.uid()`, `profiles.role='admin'`, and JWT `aal2`.
Role is checked again after acquiring locks. It does not trust client eligibility,
phase, role mapping, occupant counts or advisory preview results.

Validation checks explicit roster identity and current version; date membership;
physician existence/activity; role activity, allowed ranks and capabilities; exact
role-ID slot resolution; missing/ambiguous slots; full-day absences; duplicates;
capacity including all assignment states; existing overlaps and mutual proposed
overlaps. No occupant is ever removed. Codes include `unauthorized`, `mfaRequired`,
`staleVersion`, `rosterNotEditable`, `missingSlot`, `ambiguousSlot`,
`physicianInactive`, `physicianNotFound`, `physicianNotEligible`, `missingCapability`,
`roleInactive`, `blockingAbsence`, `duplicateAssignment`, `slotFull`,
`overlappingAssignment`, `invalidDate`, `idempotencyConflict`, `internalError`.
The shared adapter maps `physicianInactive` to the existing `inactivePhysician` enum.

Draft/open permit additions. Locked requires a nonblank correction reason.
Published rejects direct additions and requires a future explicit new-revision
workflow. Successful admin additions are **confirmed**, including in a draft;
this does not publish the roster or change its phase.

## Atomicity and concurrency

All targets validate before the single multi-row INSERT. Any hard error means no
assignments, audits or version changes. Audit and idempotency receipt are in the
same transaction. An exception rolls back the function's subtransaction and returns
`internalError`, never SQLERRM. A tested audit failure also rolls back assignments
and the version increment.

The first implementation uses SHARE ROW EXCLUSIVE table locks on profiles,
physicians, roles, absences, rosters, days, slots, assignments and request receipts.
These conflict with other writers, including mobile statements that do not use
an advisory lock or the new RPC, while allowing ordinary SELECTs. This is a
deliberate small-installation safety tradeoff, not a throughput optimization.
See [PostgreSQL lock modes](https://www.postgresql.org/docs/current/explicit-locking.html)
and [security-definer guidance](https://www.postgresql.org/docs/current/sql-createfunction.html).

One successful addition statement advances the roster version. Competing requests
with the same expected stamp cannot both pass; the later request receives
`staleVersion`. Other legacy writers may deadlock when they already hold locks in
a different order; PostgreSQL aborts a participant. The RPC returns a sanitized
failure after rollback, and the UI can retry. Lock contention and global version
invalidation must be measured before large-scale deployment. Narrower locking
requires coordinating every legacy write path, not just changing this RPC.

Existing mobile direct-table policies are intentionally retained. Therefore this
RPC enforces authoritative validation for the new desktop path; it is **not** a
retroactive database-wide prohibition on legacy invalid writes. Legacy admins
still have their existing direct assignment privileges. Closing those paths needs
a coordinated mobile service migration, rather than an unreviewed mobile break.

The reader fetches a version before and after loading its multi-query snapshot;
a changed stamp rejects the snapshot. An absent migration keeps the version null
and Apply disabled. No client fabricates version zero.

## Idempotency and audit

The UI generates a UUID v4 for each confirmed operation. The server scopes it by
actor and binds it to canonical sorted dates, roster/version, physician, role and
trimmed reason. A successful retry returns the original receipt **before** stale
version validation, with no additional writes/audits. Reusing the key with different
inputs returns `idempotencyConflict`. Failed validation creates no receipt.

Each created assignment gets an `audit_log` row with actor, server timestamp,
roster, physician, role, slot, date, null old state, confirmed new state, request ID,
correction reason and expected/resulting versions. No password, MFA code, JWT,
service key or raw SQL error is logged by the new code. Receipts have no client
table policies or authenticated write grants; only the RPC accesses them.

## Time and shared services

Server dates are PostgreSQL DATE values. Intervals use existing stored timestamptz
values; no wall-clock timestamp is created or historical timestamp rewritten.
Blocking absences check the stored date and every occupied Europe/Vienna date,
with the end instant excluded. `available` and `duty_24` markers retain core
nonblocking semantics; stored post-duty and other absences block full days.
Same-day SON/NVB, SON/OFO, SUL/NVB and SUL/OFO exceptions mirror the existing
`DefaultOverlapRules`. Other dynamic role pairs get ordinary interval checks.
Existing timestamp provenance and 24h/rest consistency still need review.

`SupabaseAssignmentMutationService` implements `AssignmentMutationService` behind
the optional infrastructure entry point. Widgets have no direct Supabase mutation
calls. `AssignmentCommitRequest.atomicApply` carries a versioned advisory preview
as input to authoritative atomic validation; it does not fabricate a backend
confirmation token or promote local validation to authority. The older separate
backend-preview constructor remains reserved for that future protocol.

## Desktop Apply behavior

Apply requires a finished all-valid preview, actual version, editable phase and
a server-verified admin/MFA session. Locked requests collect a mandatory reason
in confirmation. The dialog lists physician, role, count and every date.
The RPC is called only after confirmation and a fresh access check. Apply is
disabled in flight and background mouse interaction is blocked.

Success reloads roster/workload, keeps selected dates and clears the role/preview.
Stale version also reloads and requires a new role selection/preview. Per-date
server errors replace advisory results and disable Apply when any date is blocked.
Transport/response uncertainty retains the exact confirmed request and UUID;
“Retry same request” safely checks its outcome. It never blindly retries with a
new ID. This pending UI state is in memory, not durable across app restarts;
after restart a fresh load shows any committed assignment and prevents duplicates.
A failed reload after success says the assignments were saved but data must reload.

## Tests and deployment status

Baseline `764b480`: formatting/analysis, 34 desktop tests, Windows build,
33 shared tests and 10 core tests passed. The unrelated mobile build-number
change is excluded from this work.

Isolated backend tests:

```powershell
node supabase/tests/admin_assignments.mjs "$env:TEMP\neurodienst-viewer-test-tools"
node supabase/tests/viewer_access.mjs "$env:TEMP\neurodienst-viewer-test-tools"
```

The external tools directory contains `@electric-sql/pglite`; no live backend is
used. These tests execute the migrations and PL/pgSQL, covering authorization,
MFA, single/multi-date writes, atomic rejection, eligibility, absences/overnights,
capacity, overlaps/exceptions, stale versions, phases, retry/audit and rollback.
PGlite queues concurrent calls, so its contender test proves stale-stamp behavior
but **does not verify independent PostgreSQL connections or lock waits**.

For a real lock race, the runner also supports `--postgres` using the `pg` package
in that external tools directory and `NEURO_ADMIN_TEST_DATABASE_URL`. It refuses
non-local hosts, databases not named `neuro_admin_test_*`, and nonempty databases.
Use a disposable empty database and a local test owner allowed to create the test
role/schema. The test leaves fixtures there; it never cleans a live database.

Native verification completed on 2026-10-09 using portable PostgreSQL **18.4**
on Windows x64, installed only in the external temporary tools directory
(`@embedded-postgres/windows-x64@18.4.0-beta.17`, `pg@8.23.1`). A disposable
cluster listened only on `127.0.0.1:55439`; no Windows service was installed.
All **31 tests passed**, including two independent connections submitting the
same expected version: exactly one committed and the other returned `staleVersion`.
The cluster was stopped after verification. This checks functional concurrency,
not production throughput or every possible legacy-client lock ordering.

For an already running disposable local cluster, reproduce with:

```powershell
$env:NEURO_ADMIN_TEST_DATABASE_URL = 'postgresql://neuro_test@127.0.0.1:55439/neuro_admin_test_phase2c'
node supabase/tests/admin_assignments.mjs "$env:TEMP\neurodienst-viewer-test-tools" --postgres
```

The database must be newly created and empty for each run; an existing test
database containing fixtures is deliberately rejected.

A zero-row, read-only REST probe of `rosters.content_version` against the locally
configured Supabase backend on 2026-10-09 returned HTTP 400 / PostgreSQL `42703`
(undefined column). The migration is therefore still absent on that backend.
This public-key schema probe does not verify authenticated login, MFA or data
loading. No safe disposable live target was supplied, so no live assignment,
mobile visibility check, live audit check or live cleanup was performed.
Do not interpret fixture tests as live verification.

### Deployment and controlled live verification still required

1. Apply `supabase/migrations/202610080001_admin_assignment_rpc.sql` using the
   project's authenticated migration/deployment process. It is a forward-only,
   one-time migration; do not reset the database or replay all migrations over
   existing data. Public application credentials cannot deploy this SQL.
2. Reload the desktop roster with an administrator session at MFA assurance
   level `aal2`. Confirm a real content version loads and a valid preview can
   enable Apply; doctor/viewer sessions must still be denied.
3. Identify a disposable roster/date, exact database role and physician before
   any live write. Confirm one assignment, then verify the same slot/physician
   in desktop and mobile and the corresponding audit record/request UUID.
4. Removal is not implemented in this phase. Use only an explicitly approved
   existing removal path if cleanup is required; do not invent a desktop delete
   route or use direct SQL to bypass the intended workflow.

## Remaining scope

- Remove/replace: separate versioned RPCs, audit and explicit replacement review;
  no removal path is shipped in this phase (Phase 2C.1).
- Published revisions: publication visibility and revision creation remain absent.
- Roster creation/regeneration: extract existing generation, audit timestamps/DST,
  preserve historical data and publish only through reviewed lifecycle services.
- Full administrator parity: shared account/physician/role/template/report services
  extracted from existing mobile workflows, then coordinated migration of legacy
  direct writes and policies. No duplicate desktop implementations.
- Automatic allocation: reliable workload targets, classification/rest policy and
  validated planning services; retain this transactional path for final changes.

Final verification (2026-10-08):

- Desktop formatting clean; `flutter analyze` reports no issues; **43 widget/unit
  tests passed**; Windows release build succeeded.
- Shared formatting clean; `dart analyze` reports no issues; **38 tests passed**.
- Core: **10 tests passed**, with no source changes.
- Backend: **30 isolated PostgreSQL/PGlite tests passed**; existing viewer suite
  passed all 33 table-write denial paths while preserving doctor/admin permissions.
- `git diff --check` passed. No direct assignment table mutations exist in the
  desktop/shared adapters.

Follow-up verification (2026-10-09): **31 native PostgreSQL tests passed**, including
the independent-connection race. Only this verification documentation changed;
the prior Flutter/Dart checks and build above were not rerun. Live write
verification remains outstanding, and the read-only probe confirms the configured
backend still lacks `content_version`.
