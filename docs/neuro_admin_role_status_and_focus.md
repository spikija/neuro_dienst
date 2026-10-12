# Role status, colors and calendar focus

The desktop calendar and Daily Roster use exact database role IDs. Active roles
(including roles hidden from printed reports) stay in the configured `display_order`,
then code, then ID order. Roles referenced by this month remain inspectable even
when inactive. Unused inactive roles are excluded. A role without a slot stays in
its usual position and is shown as not scheduled.

`RoleStaffing` in neuro_admin_services projects actual slot capacities and unique
assignment IDs. Both provisional and confirmed facts count toward staffing.
Empty scheduled slots use an outlined colored circle; partial staffing uses a
half-filled circle; full staffing uses a filled circle; unscheduled roles use a
grey outline. Multiple shifts aggregate per role; overstaffing one shift does not
mask a vacant second shift. Tooltips show the exact assigned/capacity totals.

The same ordered indicator grid appears at the left of each day. When available
space is exhausted, an explicit +N tooltip contains every remaining role and its
status. Daily Roster cards retain configured order with compact, content-sized
scheduled rows and one-line unscheduled rows. Multiple slots and physician names
wrap without nested scrolling. Calendar markers use a tight two-column grid
with explicit tooltip overflow. Markers are 12 px with 2 px gaps in a 26 px
block. Daily rows use 5 px vertical padding, 11-13 px text with a 1.15 line
height, and 2 px card margins. Same-day shifts show times only; overnight
shifts retain dates. All physicians and assignment states remain visible.
Ten single-slot vacant roles fit without scrolling in the tested desktop sizes;
long names, multiple shifts and larger accessibility text can require scrolling.

Colors are presentation only. `roles.color_key` stores an optional curated palette
token, independently of role code or department. Null uses a specified FNV-1a
role-ID hash (not Dart hashCode). Light/dark variants share hue; shape, counts,
role labels and semantic tooltips also convey meaning. Role administration,
calendar dots, role chips, Daily Roster and restrained report header borders use
the same shared palette. New palette tokens require updating the database check
constraint as well as the shared palette.

## Deployment

Apply `supabase/migrations/202610120001_role_colors.sql` before deploying the new
desktop build. It adds the nullable palette column and extends the existing
admin_save_configuration RPC. Admin+AAL2, transaction locking, optimistic version
checks, idempotency and audit behavior are preserved. Older clients that omit
color_key keep existing colors. Configuration reads return the saved token.
No migration or live backend write is applied automatically by this work.

## Focus and selection

The dashboard owns focusedDate separately from CalendarSelection. A mouse click
sets focus immediately; dragging also moves it to the last actual calendar cell.
Left/right move one civil day; up/down move seven. Arrow movement does not alter
selected dates, including when inspecting a blocked day. The focus frame and
corner icon are independent of selection, assignability and holiday styling.
Keyboard navigation scrolls a focused day into view in a short window.

Keyboard month changes load an existing adjacent roster. An ungenerated adjacent
month shows an empty calendar and configured unscheduled rows; it never creates
backend data. Existing bulk selections remain stored across these transitions.
Only selections in the displayed month enter assignment/removal requests, and
normal validation still applies. Month validation after keyboard navigation does
not auto-select or silently remove dates. Explicit role/physician changes retain
the prior workflow's selection-validation behavior. Explicit month-picker changes
retain the prior clear-selection behavior. Enter/Space retain the existing focused
day selection action; all editing restrictions remain in effect.

## Verification

New tests cover exact/custom roles, capacities and split shifts, palette stability,
actual outline/half/full painting, light/dark contrast, overflow disclosure,
configuration persistence and rejection, stable daily role order, mouse focus,
all four arrows, adjacent and missing months, selection preservation, and retained
physician/role choice. Existing assignment, generation, auth, viewer and report
regressions are run alongside these tests. Tests use isolated data, not live rosters.

Verified on 2026-10-12:

- Full desktop suite: 97 passing tests, including compact daily rows at
  1440x900 and 1920x1080, two-column marker geometry, tooltips and role activation.
- Shared services: 54 tests; core: 10 tests.
- All six isolated backend suites pass (assignments, workspace/generation,
  directory, configuration/colors, viewer access, viewer invitations).
- Independent PyMuPDF checks: portrait, landscape and physician reports each
  remain one page, with bounds, columns, headers and weekday styling verified.
- Windows release build succeeds (`build/windows/x64/runner/Release/neuro_admin.exe`).
- No live migration, account changes, assignments or generation were performed.
