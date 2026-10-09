# Phase 2D: month assignability and administrator parity contracts

The existing administrator/MFA gate and transactional assignment service remain
the write boundary. This phase changes desktop selection and adds Flutter-free
reporting/generation contracts. It does not implement allocation, report UI,
generation UI, new backend endpoints, or changes to mobile/core behavior.

## Month validity and selection

`MonthAssignability` in `neuro_admin_services` projects the existing shared
validator's results into immutable `assignableDates`, `warningDates`,
`blockedDates`, and `missingSlotDates`. Warning dates are a subset of assignable
dates. Ambiguous slots are blocked; missing slots remain neutral. A missing slot
stays neutral even when an additional physician/phase error also applies.

`CalendarSelection` owns mutable selected dates separately. Without a role and
physician pair, its original single-click/rectangular selection and Monday-Friday
button remain available. A role can now be chosen with no dates selected.
Candidate previews cover every in-month date, including dates without generated
days/slots. With both inputs present, selection is disabled while validation is
pending; successful validation replaces selection with all valid/warning-valid
dates. No fairness classification or recommendation/ranking is added.

Clicking a valid date toggles it; Clear selection leaves the month validity
visible, and Select all assignable days restores the valid set. In assignment
mode a drag adds the valid dates in the anchor/current rectangle to the selection
that existed at pointer-down. It does not restore deselected dates outside that
rectangle or add blocked/missing dates. A stationary mouse click toggles instead
of becoming a one-cell rectangle. Keyboard/semantic activation obeys the same
selection restrictions. Generic drag behavior is unchanged.

Role/physician/month/reload changes discard previous validity and preselection.
Role and physician remain selected across months if they still exist, and a new
month validation runs. Re-clicking the same physician does not erase manual
deselections. Panel generations reject late async results. An explicit reload
generation also remounts validation when a reader reuses the same snapshot
instance. Failed validation leaves all assignment dates unselectable and shows
a retry-by-reload message.

`CalendarColors` centralizes light/dark theme colors. Assignable days have a
primary blue outline and soft tint; selection has a stronger border and check.
Warnings add an amber icon. Blocked dates have a muted background and error icon;
missing slots keep the neutral calendar appearance. Occupants have a person
indicator and names in the tooltip, independently of validity/selection. Status
labels, counts and icons supplement color. Transitions last 140 ms.

Apply derives an advisory preview from `selectedDates intersect assignableDates`.
An empty intersection disables Apply. Confirmation lists physician, exact role,
selected dates and warning-date count; locked corrections still require a reason.
Subsetting never reuses a backend confirmation token. The existing atomic RPC
revalidates every target, retains idempotent retries and remains authoritative.
Server per-date failures update the month validity and remove blocked dates from
selection without reselecting previously deselected dates. A successful/stale
write reload recomputes validity and preselects the newly available set.

## Existing mobile reporting: parity audit

Sources inspected:

- `neuro_app/lib/screens/month_report_picker_screen.dart`
- `neuro_app/lib/screens/month_report_screen.dart`
- `neuro_app/lib/services/supabase_roster_service.dart`
- `neuro_app/lib/services/supabase_doctor_service.dart`
- `neuro_app/lib/screens/admin_report_settings_screen.dart`
- `neuro_app/lib/screens/admin_doctors_screen.dart`
- `neuro_app/lib/screens/personal_roster_report_screen.dart`
- `neuro_app/lib/services/personal_roster_report.dart`

The picker lists stored rosters in reverse year/month order across all phases.
The roster service reads `rosters`, `roster_days`, `roster_slots`, associated
`roles`, and `assignments`. Physicians/absences arrive through a supplied doctor
list, normally the active-doctor service (`doctors` plus `absences`). Both
provisional and confirmed assignments are included without a report-level state
filter. Existing settings are live settings, not a historical configuration
snapshot tied to publication.

| Mobile view | Current behavior to characterize before extraction |
|---|---|
| Role report | Printable active roles ordered by `display_order`, then code. One column per role; first matching slot by exact role ID, then legacy SlotKind/code fallback. Surnames sorted alphabetically, `-` for an empty existing slot, blank for no slot. Absence initials and holiday/weekend notes are separate columns. |
| Physician report | Columns sorted by `print_order`, rank (head to resident), surname, then first name. Cells show absence first; otherwise codes of assignments in the report-role set, using fixed code priority. Other-absence labels are localized; other blocking absences use the vacation abbreviation. |
| Personal PDF | Resolves the signed-in active doctor, never an arbitrarily selected physician. Every assigned role is included, even if hidden from department reports. Per-date duty names are deduplicated and sorted; absences do not replace assignments. |

`roles.print_in_report` and `roles.display_order` are changed directly by the
mobile report settings service. Doctor print ordering lives in
`doctors.print_order`; moving doctors currently performs separate updates.
These mutation workflows should later move into shared audited services, not be
copied into desktop widgets.

The department report is currently a Flutter A4-like fixed 1120x1584 preview;
its print/export button is disabled. It has frozen date columns, weighted
weekend/holiday row heights, truncation, embedded styles and mobile localization.
The personal report uses `pdf` and `printing` (`PdfPreview`), bundled Roboto font
assets via `rootBundle`, A4 portrait defaults, and mobile localization. Existing
ICS/share/save workflows additionally use `share_plus` and `path_provider`.
Those packages/assets/platform dialogs are not added to the shared data layer.
Windows printing/file dialogs and later macOS entitlements/plugin behavior need
separate desktop qualification before offering export. No desktop PDF parity is
claimed by these contracts.

Important parity ambiguities/defects to resolve explicitly:

- Active-only doctor loading can omit historical/inactive assignees; the mobile
  roster decoder skips assignments with no doctor mapping. The shared reader
  retains historical people, so literal reproduction of that omission would be
  a regression. Characterization fixtures must separate intended parity from it.
- Multiple slots for one role/day are reduced to the first by the role report.
  Empty printable-role lists fall back to a fixed legacy role list. AMB/ICB and
  unknown role fallbacks can collapse identities. The new contract retains exact
  IDs and flags unresolved parity issues rather than duplicating these guesses.
- Physician-report absence precedence differs from the personal report's duty
  precedence; extract both deliberate policies and test each.
- Mobile slot decoding uses workstation `.toLocal()` time and derives a slot date
  from its start. Desktop uses stored hospital dates and Europe/Vienna instants.
  Historical timestamps must not be rewritten to achieve visual parity.

`reporting.dart` defines `ReportingService.load`, a pure
`ReportProjectionService.project`, and typed request/configuration/document,
column, row and cell models. Exact database IDs, phase, assignment states,
calendar metadata, absences and settings provenance survive projection. The
personal request requires a physician identity. Cells keep assignments and
absences separately; renderers/localization implement the established precedence
after shared projection is extracted. Configuration has an optional authoritative
version because no current shared settings stamp exists.

Before reporting UI: extract and characterize mobile projections once, implement
a consistent settings/data reader, decide the documented parity differences,
add shared localization/presentation adapters, and qualify PDF/font/print export.
Neither interface currently has a production implementation. Future report
configuration writes require their own versioned admin service.

## Existing month generation: parity and safe workflow

`neuro_app/lib/screens/admin_rosters_screen.dart::_RosterGenerator` accepts year
(2000-2100), month (1-12), and replace-existing. It queries the month identity,
rejects an existing month unless replacement is requested, then **deletes that
roster without checking phase**, inserts a draft, loads active roles and their
templates, inserts every calendar day and finally inserts template-derived slots.
These are separate direct Supabase requests, not one transaction.

Deletion cascades from roster to days to slots to assignments. A partial failure
after deletion/insertion can leave data lost or a partly generated month. The
current mobile path can therefore delete a published historical schedule; this
is a documented existing defect, not behavior to reproduce in desktop. It is
unchanged in this task and should be addressed separately through a coordinated
backend/mobile generation-service migration.

Inputs are role ID/active flag/capacity and template ID/role ID/weekday rule/
monthly day/start/end time. Rules are Monday-Friday, one specified weekday, or
monthly calendar day; a monthly day absent from a short month produces no slot.
Templates for inactive roles are excluded. Multiple matching templates can
produce ambiguous role/day slots. Weekend flags are calculated, but every holiday
flag is written false. Templates are concatenated with `Z` as though wall times
were UTC, without Vienna/DST conversion. Existing template constraints require
end time after start time; overnight support must be designed explicitly.

The refined `RosterGenerationService` exposes `preview` then `apply`, with a
`RosterGenerationPlan` of days/slots, exact role/template IDs, removals, impacted
assignments, blockers, warnings, holiday provenance, backend review token and
expiry. `RosterGenerationCommitRequest` rejects expired/unreviewed/blocked plans,
assignment loss, mismatched months, missing existing versions and any existing
phase except draft. This is a design contract, not a client authorization bypass
and not an implemented generator.

Safe desktop workflow, when implemented:

1. Load an authoritative configuration stamp including roles **and templates**,
   plus a roster/revision stamp or proof that the month is absent. Current roster
   versions do not stamp template changes; a real configuration stamp is a blocker.
2. Preview exact recurrence, capacities, duplicates, hospital-date/instant
   conversion and verified holiday provenance. Show retained/added/removed slots
   and assignment impacts. Do not allocate physicians automatically.
3. Block published/open/locked regeneration. Published corrections need a new
   revision and a publication lifecycle, not deletion. Existing `(year, month)`
   uniqueness means revision support requires a deliberate backend migration.
4. Confirm a non-destructive draft delta. Retain assignment/slot identities where
   unchanged; reject loss until a separately reviewed reconciliation workflow
   exists. The contract currently blocks any impacted-assignment plan.
5. Commit in one admin+MFA transaction with idempotency, configuration/version
   rechecks, explicit qualified writes compatible with safeupdate, audit and
   rollback. Reload the snapshot/workload only after the authoritative receipt.

Before generation UI: extract recurrence/planning from mobile, decide timezone
and holiday policy, implement configuration stamping and transactional endpoints,
test competing create/regenerate operations and assignment preservation, then
route both clients through the shared service. No `_RosterGenerator` copy or
generation write path is added to desktop here.

## Verification

Unit/widget tests cover role-only and physician-only behavior, all
calendar dates, valid/warning/blocked/neutral states, preselection, toggle and drag,
role/physician/month/reload changes, stale responses, failed validation, and exact
selected-date submission. Existing auth/MFA, idempotency and assignment tests remain.

An optional native read-only integration check is available:

```powershell
cd neuro_admin
flutter test integration_test/read_only_assignability_test.dart -d windows --dart-define-from-file=../neuro_app/.env.supabase.json
```

It uses only a saved, server-verified admin session at AAL2; otherwise it explicitly
skips with `LIVE_NOT_VERIFIED`. It loads live data, verifies month selection and
cell states, and supplies no mutation adapter (Apply disabled). It never signs in
with embedded credentials or creates backend records. Successful output contains
only aggregate counts. This does not retest an interactive login/MFA challenge.

Verified on Windows for this change:

- `dart format lib test integration_test` in desktop and `dart format lib test`
  in services completed; `flutter analyze` and services `dart analyze` were clean.
- Desktop: 52 unit/widget tests passed; services: 42 tests passed; core: 10 tests
  passed.
- `flutter build windows` produced the release executable successfully.
- The native read-only integration test passed against the existing Supabase
  backend using a saved, server-verified administrator AAL2 session. It checked
  31 dates: 6 assignable (all 6 warning-valid), 15 blocked, and 10 neutral/missing
  dates. Selection, borders, warning/blocked icons and disabled Apply matched
  validation. No backend data was created, edited or deleted.
- macOS and interactive login/MFA challenge were not retested in this phase.
