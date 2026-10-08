# Phase 2B: manual assignment preview

Phase 2B performs no backend assignment mutations.

The Windows desktop remains administrator-only with its existing Supabase session
and MFA gate. Mobile, core, migrations, functions and authentication are unchanged.
No service-role key, assignment RPC, write adapter, automatic allocation, ranking,
replacement, publication or revision creation is introduced.

## Workflow and state

Select dates with click/drag, choose a database duty role, then select a physician
in the right pane. All physicians, including inactive/ineligible ones, are shown
in existing directory order. Optional All/Eligible/Available filters do not rank
by fairness. Candidates show rank, capabilities, eligibility and raw workload:
previous 90 calendar days before the selected month's first day, including recorded
24h duties/weekends and station/ambulance/science days; current-month assignments,
assigned days and provisional/confirmed counts. These remain the existing
`RecordedWorkloadService` calculations, not new fairness scores or targets.
Station codes are SUL/SU1/SU2, ambulance is AMB, science is SCI. SON/NVB/OFO,
ICB and custom codes remain other/unclassified. Recorded 24h totals come from
`absences.type=duty_24` day markers, not an inferred slot duration or role. All
roster phases are included and provisional/confirmed assignments remain distinct.

The lower right preview is scrollable. It shows each target date's validity,
structured errors and warnings, exact stored duty times in Europe/Vienna, capacity,
current occupants with assignment state, and the proposed physician. It displays
valid / valid-with-warnings / blocked totals and the count of proposed additions.
Apply is always disabled with an explicit preview-only notice.

### Phase 2B.1 calendar selection

Drag uses **rectangular calendar-grid selection based on anchor and current cell**.
It is not pointer painting or a chronological contiguous range. Monday-first
`CalendarGridMonth` converts dates to row/column coordinates. On each pointer move,
the selected set is replaced with valid month dates inside the inclusive minimum/
maximum anchor/current rows and columns. Intermediate pointer positions have no
effect on the final rectangle. Reversing direction shrinks it. Single clicks
replace previous selection with one date; release/cancel ends dragging.

Padding cells have null dates: they can bound a rectangle but are never selected.
Starting on padding does nothing. Moving outside the grid preserves the last
rectangle; no automatic month switching occurs. Persistent selection remains an
immutable view of normalized UTC-midnight calendar dates, not widget indices.

**Select all working days** replaces selection with all Monday-Friday dates in
the displayed month, whether or not roster day/slot records exist. **Clear selection**
empties the dates. Holiday exclusion is not reliable: the current mobile generator
(`admin_rosters_screen.dart`, `_RosterGenerator`) writes `is_public_holiday: false`
for every generated day. Therefore the button deliberately uses weekdays only,
even when some rows have holiday flags; the UI explicitly says public holidays
may be included. For example, October 2026 selects 22 dates including October 26.
There is no new holiday provider or backend change.

All selection actions use the existing preview invalidation/generation protection.
Bulk selection preserves role/physician and recomputes each target (including
`missingSlot` where applicable). Clearing removes the preview and discards pending
results; selecting dates again restores preview using the retained role/physician.
Month changes still reset selections. No Ctrl/Shift behavior is added. No backend
mutation is performed.

Changing dates or role clears cached results immediately and debounces recomputation
by 60ms. Candidates are validated independently for the same input snapshot;
changing physician uses that physician's freshly calculated candidate result.
Generation IDs discard late asynchronous responses. Reload drops the old snapshot
and recomputes while preserving valid selections. Month changes clear dates, role,
physician and preview. Cancel leaves dates selected and restores workload browsing.
Failures show a retry/reload message; previous validation is never used as fallback.

## Shared boundary and identity

`SnapshotAssignmentValidationService` implements `AssignmentValidationService`
in the Flutter-free `neuro_admin_services` package. Desktop widgets only orchestrate
input/selection, asynchronous state, filters and presentation. No mobile scheduling
workflow has been copied into desktop screens.

`StoredRole` now retains allowed ranks, required capabilities and active status.
`RosterSnapshot` exposes the full role directory, unknown physician activity and
whether interval-conflict coverage was loaded. `AssignmentValidationResult` includes
matching slots, current occupants and conflicting assignments. `AssignmentPreview`
exposes separate summary counts; errors and warnings remain separate immutable lists.

Actual database role IDs identify choices; slot IDs identify resolved targets.
AMB and ICB stay distinct despite the mobile enum mapper collapsing them.
Workload still classifies only AMB as ambulance; unseeded ICB remains unclassified.
Unknown/custom roles use their own stored eligibility metadata, never a science
fallback. Missing matches yield `missingSlot`; multiple matches yield `ambiguousSlot`.
The UI does not guess a slot or provide an ambiguity-resolution workflow yet. An
explicit slot ID can be validated through the shared contract.

Current schema rows have no concurrency version: requests use
`RosterVersion.unversioned`, not a fabricated version zero. Advisory previews are
never confirmable. Backend previews and `RosterWriteIntent` reject missing versions.

## Hard errors and domain reuse

| Code | Condition |
| --- | --- |
| `physicianNotFound` | Physician absent from the directory |
| `inactivePhysician` | Physician explicitly inactive |
| `physicianNotEligible` | Rank excluded by stored role metadata |
| `missingCapability` | Missing one or more required capabilities |
| `roleInactive` | Stored duty role inactive |
| `missingSlot` / `ambiguousSlot` | No unique concrete target |
| `invalidSlot` | Incorrect stored date, nonpositive capacity or invalid interval |
| `invalidDate` | Wrong roster ID or calendar month |
| `blockingAbsence` | Core full-day absence on any hospital day touched by the duty |
| `duplicateAssignment` | Physician already occupies the slot |
| `slotFull` | All capacity occupied, counting provisional and confirmed records |
| `overlappingAssignment` | Conflicting actual interval, including other proposed dates |
| `rosterNotEditable` | Published roster requires a new revision |
| `validationUnavailable` | Missing eligibility/activity/overlap data or replacement requested |

Absences reuse `Doctor.absenceOn`: vacation, EF, post-duty rest and all other
absence reasons (including ZAM late shift) block the whole day. These other absence
reasons do not manufacture next-day rest. A `duty24` marker itself follows existing
core semantics and does not block; stored post-duty absence does. Overnight slots
check every occupied Vienna date, excluding the end instant, plus the stored date.

Rank/capability checks use the same membership predicate as
`SlotTemplate.canBeFilledBy`. That API requires fixed enums and wall-time objects,
so dynamic stored roles are checked directly rather than inventing template kinds.
Overlap uses real UTC intervals with half-open endpoints. Approved same-date role
pairs reuse `DefaultOverlapRules` for exact seeded codes SON/NVB/OFO/SUL only.
This narrow exception lookup is not role identity or a default category mapping.
Unrecognized role pairs receive ordinary overlap checks.

The GET-only reader supplements date-based workload loading with all slots whose
actual intervals intersect the selected month's duty envelope, then loads their
days/assignments, including adjacent months. Absence queries cover hospital dates
touched by that envelope. Missing referenced records remain load errors; inactive
physicians remain visible in historical facts. Queries are not an atomic snapshot.

## Warnings, bulk and lifecycle

Only factual warnings are implemented: `correctionReasonRequired` for locked
rosters, `allowedOverlap` for existing duties explicitly permitted by core policy,
and `incompleteWorkloadHistory` when fewer than 90 historical roster dates exist.
No arbitrary burden threshold, imbalance score or allocation target is invented.
The reserved fairness warning codes are not emitted by this implementation.

Each requested date produces its own result. Valid targets do not inherit another
date's absence/missing slot error. Overlapping proposed additions are both blocked;
already blocked dates do not become proposed additions. Warnings leave a target
valid. The proposal count is an advisory count, including valid dates with warnings,
not permission to apply a subset. No current/conflicting occupant is removed.

Draft and open-for-selection allow normal preview. Locked allows conditional
preview with a correction-reason warning (the shared request can supply a reason).
Published is blocked with "Published rosters require a new revision before editing."
No locked correction or published revision is executed.

## Remaining gates before Phase 2C

All Phase 2A server/data gates still apply: authoritative transactional validation,
admin+aal2 enforcement, optimistic concurrency, versioning and publication visibility,
idempotency, audit/reasons, explicit subset/replacement semantics and race/rollback
tests. The existing client-side preview cannot establish server authorization.

Audit existing timestamp provenance and fix generation/conversion before using
overlap checks for production decisions; this phase interprets stored instants and
does not repair them. Current metadata is used for eligibility because historical
role snapshots do not exist yet. Resolve approved dynamic-role overlap policy,
24h marker/rest consistency and clinical completeness through shared services.
The existing bundled Vienna timezone range limit (October 2037) still applies.
macOS build/signing and live cross-platform behavior remain unqualified.

Full administrator parity remains the long-term scope. Accounts, physicians,
roles, templates, generation and reports should be extracted from existing mobile
workflows into shared services rather than independently implemented in this UI.

## Verification

Baseline at `ef6da92` was clean: desktop formatting/analysis, 19 tests, Windows build,
10 core tests, shared formatting/analysis and 18 tests passed before implementation.
New unit/widget coverage exercises structured validation, independent bulk results,
role identities, occupants, allowed overlaps, overnight/month-boundary reads,
unversioned write rejection, selection changes and stale asynchronous results.
Desktop layouts are exercised at 1280x720, 1440x900 and 1920x1080.

Final automated verification (2026-10-08):

- Desktop: `dart format lib test` clean, `flutter analyze` no issues,
  `flutter test` **26 passed**; Windows release build successful using the existing
  ignored public configuration via `--dart-define-from-file`.
- Shared services: formatting clean, `dart analyze` no issues, `dart test`
  **33 passed**, including GET-only cross-month reads.
- Core: `dart test` **10 passed**, no source changes.
- `git diff --check` passed. No mobile/core/backend changes or production
  assignment mutation/RPC calls were introduced.

The configured Windows release application was launched. Authenticated live
preview, workload and occupant verification is pending local sign-in/MFA and
interactive confirmation; automated fixture results do not establish live success.
Automated window inspection did not expose the rendered Flutter UI, and screen
capture was unavailable in this automation session. No live success is claimed.
The user subsequently reported Phase 2B preview working and requested Phase 2B.1
with a commit after clean verification. This is user-reported live behavior, not
an independent automated live-backend check. Nothing has been pushed.

Phase 2B.1 final verification (2026-10-08): desktop formatting clean, analysis
without issues, **34 desktop tests passed**, Windows release build successful,
**33 shared-service tests passed**, and **10 core tests passed**. Tests cover
direction/path-independent rectangles, reversal/shrinking, padding, release/cancel,
new clicks, working-day/holiday policy, clearing, month reset, preview recomputation
without backend reads, and existing stale-response protection. Common desktop
sizes still pass; the smaller 800x500 calendar remains scrollable.

The selection UX is ready for Phase 2C integration. Production writes remain
disabled until the server, concurrency, authorization and timestamp gates above
are resolved. This commit includes the previously uncommitted Phase 2B preview
implementation. An independently changed mobile build number is excluded.
