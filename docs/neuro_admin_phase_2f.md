# Phase 2F: desktop reporting, localization and user administration

## Scope and architecture

The desktop remains administrator-only. Its session gate and every new server
command require administrator access and AAL2. Viewer accounts are managed by
administrators, but cannot enter this application. No automatic allocation,
ranking or publishing was added. `neuro_app` and `neuro_core` source are unchanged.

`DirectoryAdministrationService` extends the existing invitation/profile
contract in the Flutter-free `neuro_admin_services` package. Its Supabase adapter
calls the existing `invite-doctor` Edge Function and new directory RPCs. Forms
contain presentation and validation only. Mobile can adopt these services later;
mobile widgets and their business operations have not been copied into desktop.

## Workspace and report UX

`ReportTable` consumes one `ReportDocument` from `FactualReportProjection`.
The date rail and body share a vertical viewport. Separate header/body horizontal
controllers mirror their offsets, leaving the corner fixed. Persistent desktop
scrollbars expose the full width, including the final absence/holiday column.
Columns retain readable widths; row heights follow measured wrapped content and
text scale. Coverage includes 1280×720, 1440×900 and 1920×1080.

The calendar uses the actual remaining sliver viewport height, divided by its
number of weeks. Its minimum row height remains 68 logical pixels; short windows
scroll instead of crushing day cards. Hit testing and rectangular drag selection
use the same measured row height. Role/selection/report actions use Material icons.

The white flash was caused by `_refresh` clearing `_snapshot` and replacing the
workspace with a full-page spinner. Reload now retains the snapshot, shows a
progress strip, and swaps in the new data only after loading succeeds. Failures
leave the workspace visible with a local retry banner. Assignment loading keeps
its existing disabled button/progress state.

The creation red frame was reproduced as `DropdownButton`'s assertion that its
selected value must match exactly one item. The generated month was selected
before the dropdown's old month list had been refreshed. The requested month is
now separate from the displayed selection until the new list and snapshot are
ready, then all three change together. A deferred-reader regression reproduces
the old assertion and verifies the new transition without masking errors.

## PDF and printing

`ReportPresentation` formats the existing factual projection for screen and PDF.
`buildReportPdf` uses bundled licensed Roboto fonts and performs no network reads.
It creates genuine A4 portrait/landscape pages, divides wide reports into column
groups, repeats date/header rows, and adds a localized title and page numbers.
It preserves configured role visibility/order and assigned inactive physicians.
Existing report semantics include both provisional and confirmed facts; export
does not change assignment state or recalculate staffing rules.

`ReportExportService` separates rendering from platform actions. The production
adapter uses `file_selector` for Save PDF and `printing` for the native print
dialog. No PDF is uploaded to a service. Export failures remain in the dialog.
Windows builds include the native plugins. macOS print and user-selected-file
entitlements are supplied, but macOS compilation and actual printers require
verification on those systems. The printing plugin's Windows build includes
PDFium; clean builds may need to download that native dependency.

## Localization

`AdminStrings`, `AdminText` and a central German catalog provide English/German
presentation with named template parameters. Validation errors/warnings have
exhaustive enum-based German renderers; service/domain messages remain independent
of Flutter. Material controls use Flutter's localization delegates. Language is
user-selectable and stored as a local desktop preference. Doctor names, database
role names and codes remain factual data; they are not translated by role guesses.
Report holidays have English/German presentation and absences use localized labels.

## Directory and history policy

Physicians and viewers have separate searchable/filterable lists. Physician
forms support names, rank, capabilities, active status and print order; invitations
also collect email/language. Viewer invitations create only an Auth user/profile,
without a doctor row. Viewer forms edit display name and language; email is shown
from Auth and is not rewritten by a client-side table update.

The reader explicitly excludes doctors linked to `profiles.role = viewer`,
including legacy linked viewers, before creating assignment facts. Their absences
and assignments cannot leak back into reports or workload. Inactive real
physicians remain loaded for historical facts; new assignment selectors exclude
inactive/unknown-activity entries and server assignment validation remains active.

Archival changes `doctors.is_active` only. It retains assignments, absences and
identities. Safe deletion is a server command guarded by a trigger that checks
every doctor foreign-key dependency before a cascade can run, plus doctor audit
references. Historical/dependent records block deletion and the UI offers
deactivation. An unused physician deletion does not delete the associated Auth
account. No viewer Auth-account deletion is exposed: revocation is the supported
operation and preserves identity/history.

Viewer access is revoked through `profiles.access_revoked`. Restrictive RLS
policies check it for all currently RLS-enabled public tables, so an already
issued JWT cannot continue reading those tables. Restoration re-enables the
existing read-only viewer policies; it does not grant writes. This does not erase
data previously cached by another client. Future exposed tables must carry the
same access guard; future security-definer endpoints must enforce it as needed.

Directory edits use server-maintained monotonic `updated_at` stamps, row/table
locks, admin+AAL2 checks, audit records and actor-scoped idempotent request IDs.
Unknown outcomes retry the same command. Invitations use the existing endpoint,
which is not idempotent: an uncertain invitation response instructs the user to
reload/check the directory before retrying. Service-role credentials remain only
in the existing server function environment, never in desktop code/configuration.

## Deployment

Apply `supabase/migrations/202610100002_admin_directory.sql` after the existing
workspace/assignment migrations. This adds directory RPCs, revocation guards and
history protection; it does not delete existing data. Redeploy `invite-doctor`
to support optional physician `isActive`/`printOrder` fields. Existing mobile
invitation requests keep their current defaults. Do not replace applied older
migrations with edited copies.

## Verification

Baseline: desktop analysis and 59 tests, services 47 tests, core 10 tests,
Windows release build, assignment SQL 33 tests, workspace SQL 17 isolated tests,
viewer write-policy tests and invitation handler tests passed before changes.

New automated coverage includes frozen panes/final columns at all three window
sizes; calendar growth; retained mutation/reload UI; the exact new-month race;
German/English dialogs and translation placeholders; invitation fields, editing,
archive after blocked deletion, viewer revocation retry; PDF orientations and
historical/configured facts; linked-viewer exclusion through the shared reader,
reports and workload; server authorization, concurrent version checks, audit
rollback, dependency guards and immediate revocation with an existing JWT.

Native PostgreSQL 17 directory tests and all 19 workspace tests passed. Directory
tests also passed on PostgreSQL 14 with the actual `safeupdate` extension enabled.
The PDF files generated by tests were independently parsed/rendered with PyMuPDF:
A4 page sizes, repeated date headers/page numbers, all configured columns and text
within page bounds were verified. An 18-role sample spans seven portrait pages
or four landscape pages without dropping its last column.

Final automated results: desktop formatting and analysis clean, 79 desktop tests
passed, shared-service formatting/analysis clean and 49 tests passed, core 10 tests
passed. The final Windows release build passed (133 seconds), producing
`neuro_admin/build/windows/x64/runner/Release/neuro_admin.exe`.
Assignment SQL (33), workspace SQL (17 isolated / 19 native), directory SQL,
viewer write-policy (33 paths) and invitation-handler checks passed. The invitation
adapter also rejects malformed success receipts as unknown outcomes rather than
encouraging a potentially duplicate email. The independent PDF inspection script
is `neuro_admin/tool/verify_report_pdf.py`.

Live Windows verification used the existing public configuration and a validated
administrator AAL2 session. German report UI, horizontal scrolling and both A4
orientations for role/physician reports passed. The explicitly authorized June
2027 roster was created through the desktop dialog without a Flutter error frame.
A single eligible assignment was applied through the desktop confirmation while
the calendar stayed visible. Only that test-created assignment was removed,
with its receipt and scope checked first. The June 2027 roster remains; no existing
roster or historical physician was deleted.

Initial live directory verification returned `PGRST202` for the new directory RPC,
and the older invitation function rejected a viewer with `The selected rank is invalid.`
After the user confirmed deployment of both updates, a second Windows integration
run passed: physician/viewer directory reads, German reports, horizontal scrolling,
and both PDF orientations. Both authorized invitation addresses already existed in
the directory, so invitations were skipped and those accounts retained unchanged.
Fresh invitation delivery remains unverified; no successful email send is claimed.
The repeatable integration test checks for existing directory addresses before
inviting and creates any new test physician inactive. It accepts an optional
`LIVE_TEST_PHYSICIAN_EMAIL` alongside the existing viewer email define.
No test email addresses or credentials are stored in the repository. Viewer
exclusion/revocation and physician archival/dependency protection passed isolated
tests; live edits, archival and revocation still require separate verification.
Actual printer output, the native Save PDF dialog and macOS builds remain unverified.
Both temporary local PostgreSQL servers were stopped after testing.

## Remaining administrator parity

Role/template CRUD and report-configuration editing are not new desktop screens
in this milestone. The shared core repository/domain types and reporting
configuration models remain available; their legacy mobile workflows should be
extracted into shared application services before exposing equivalent desktop
commands. Roster generation/removal already use shared services and transactional
backend RPCs. Publishing/revisions, automatic allocation and recommendation
ranking remain out of scope. Viewer Auth deletion and physician Auth lifecycle
management beyond invitation are deliberately not supplied by unsafe client
shortcuts.
