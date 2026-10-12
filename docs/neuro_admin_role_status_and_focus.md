# Role status, colors and calendar focus

The desktop calendar and Daily Roster use exact database role IDs. Active roles
(including roles hidden from printed reports) stay in the configured `display_order`,
then code, then ID order. Roles referenced by this month remain inspectable even
when inactive. Unused inactive roles are excluded. A role without a slot stays in
its usual position and is shown as not scheduled.

`RoleStaffing` in neuro_admin_services projects actual slot capacities and unique
assignment IDs. Both provisional and confirmed facts count toward staffing.
Empty scheduled slots use an outlined colored marker; partial staffing uses a
half-filled marker; full staffing uses a filled marker; unscheduled roles use a
grey outline. Stationary markers are circles; ambulatory/other markers are boxes. Multiple shifts aggregate per role; overstaffing one shift does not
mask a vacant second shift. Tooltips show the exact assigned/capacity totals.

The same ordered indicator grid appears at the left of each day. When available
space is exhausted, an explicit +N tooltip contains every remaining role and its
status. Daily Roster cards retain configured order with compact, content-sized
scheduled rows and one-line unscheduled rows. Multiple slots and physician names
wrap without nested scrolling. Calendar markers use compact grouped layouts
with explicit tooltip overflow per group. `roles.ui_group` separates stationary
roles into a 12 px left column and ambulatory/other roles into a 26 px two-column
block to its right, with a 4 px separation. Stationary roles use circles; ambulatory/other roles use boxes. Both use 12 px
markers and 2 px gaps, with outline, half-fill and full-fill staffing states.
The daily roster has matching localized section headings and retains configured
order within each section. Empty groups omit their heading; unscheduled roles
remain visible. Grouping never changes assignment rules or workload categories.

Role administration exposes the group alongside color. The additive migration
`202610120002_role_ui_groups.sql` seeds SUL/SU1/SU2 as stationary once and defaults
other existing/new roles to ambulatory. No runtime code tests neurology codes for
grouping. Older clients preserve the group when omitting it. Unknown future group
tokens display in Other in older clients, retaining role identities. To add a
new distinct section later, extend the database constraint, shared RoleGroup and
localized section label; this does not require changes to scheduling services.

Apply the grouping migration after the color migration and before deploying the
new build. No live migration is applied by this task.

Daily rows use 5 px vertical padding, 11-14 px text (physician names: 14 px)
with a 1.15 line height, and 2 px card margins. Same-day shifts show times only; overnight
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

Grouping follow-up verification (2026-10-12): flutter analyze clean, all 99 desktop
and 55 shared-service tests pass, isolated configuration/backend tests pass with
seed/default/change/rejection/older-client preservation checks, and Windows
release build succeeds. Grouped widget tests cover the vertical stationary column,
right-hand two-column grid, stable ordering, staffing tooltips, daily sections and
exact role activation. No live migration was applied.

## Neurology banner order

The top role selector groups stationary roles first, then ambulatory/other roles,
using configured order within each group. Apply
`202610120003_neurology_role_order.sql` for the requested one-time order:
SUL, SU1, SU2, AMB, SON, NVB, OFO, ICB (or the separate ICB AMB code if present).
Other existing roles follow in their previous relative order; none are removed.
This updates the shared editable display/report order, without changing group,
role identity, templates or assignments. No runtime code hardcodes this sequence.
The migration has not been applied to the live backend by this task.
