# Monthly report print columns

Print / PDF opens one dialog with orientation, ordered role checkboxes, Select all,
Select none, Only roles used this month, Preview, Print and Save PDF. Zero selected
roles disables output; the PDF renderer also rejects an empty effective selection.

The factual projection retains all configured roles as explicit print choices;
configured visibility remains the default and the screen report is unchanged.
Hidden-by-default roles can be explicitly included. Order follows display_order,
then code and exact ID, never checkbox click order. Used roles have a generated
slot or assignment on at least one actual date in the selected roster month.
Physician reports retain their existing column behavior.

SharedPreferences stores checked and unchecked IDs locally for this OS user/app
installation, independently of month. Removed IDs are ignored, and unknown/new IDs
follow current configured visibility. No names, report facts or credentials are
stored in these preferences. Cancel discards changes; Preview/Print/Save remembers
the selection. Corrupt/unavailable reads fall back to configured defaults. A local
save failure is shown separately from export errors.

ReportPresentation and buildReportPdf accept selectedRoleIds and filter only the
print projection. Date/notes columns remain present. Widths use the selected role
count and actual page dimensions in both orientations. Preview uses the same PDF
renderer as printing/saving; no backend writes or schema migration are needed.

Tests cover defaults, persistence, deleted/new roles, custom roles, all/none/used
selection, configured order, screen independence, and both PDF orientations.
The PyMuPDF verifier checks selected columns, absence of the excluded rare role,
column order, bounds and one-page output alongside existing report checks.

Verified: flutter analyze clean; 111 desktop tests and 55 shared-service tests
pass; Windows release build succeeds. PDF/PyMuPDF checks pass for the existing
reports and selected-column portrait/landscape PDFs. No live data changes.
