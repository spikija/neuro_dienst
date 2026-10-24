# NeuroDienst Admin

Administrator-only desktop roster and workload client. Windows first; macOS runner
included, not yet qualified. Manual assignment additions, dated unassignment and
month generation use atomic admin+MFA RPCs after their migrations are deployed.
The three-pane workspace also offers screen-only reports. No direct client-side
assignment writes or silent replacement.

```powershell
flutter pub get
flutter run -d windows --dart-define-from-file=../neuro_app/.env.supabase.json
```

Use the existing local ignored public configuration file, or supply SUPABASE_URL
and SUPABASE_PUBLISHABLE_KEY through --dart-define. Never supply service-role keys.
Sign in with an existing administrator account and verified authenticator. MFA
enrollment and password recovery remain in the mobile app. Doctor/viewer accounts
are denied. Missing configuration is shown explicitly, with no demo fallback.

See [architecture and workload definitions](../docs/neuro_admin_initial_architecture.md).
See [Phase 2B preview behavior and limitations](../docs/neuro_admin_phase_2b.md).
See [Phase 2C RPC, deployment and verification](../docs/neuro_admin_phase_2c.md).
See [month highlighting, preselection and reporting/generation parity](../docs/neuro_admin_phase_2d.md).

Select dates, then a role and physician. Click individual dates to toggle them,
or drag a range. Changing the role or physician preserves the chosen dates;
availability highlighting never selects dates automatically. The Available
filter checks all chosen days. Blocked targets remain visible and prevent Apply
until removed; the server revalidates every selected date before assigning.
Inactive physicians are hidden from both workspace lists.

The month calendar shows icons for Urlaub, sick leave, conference, external
rotation and the other recorded absence/day-marker types; EF retains its **EF**
label. Hover an icon for the type and physician names. A selected physician
filters the markers; without a selection they summarize all physicians. When a
date has many marker types, **+N** exposes the remaining details on hover. All
absences and day markers also appear near the top of the daily roster. Administrators can remove any
type, including Urlaub, EF and sick leave: focus a date, use the removal button
beside the physician's entry, and confirm the exact type and date. Other dates
in a multi-day period and overlapping entries of other types are preserved.
24-hour duty and post-duty markers can be removed separately. Removal requires
the generic absence backend migration; see
[deployment and verification](../docs/neuro_admin_absences.md).

Selection actions are in **Selection**. To target occupied/blocked dates for
removal, enable **Select occupied days for removal**; then choose selected-role
or all-role unassignment and review its confirmation. Disable removal selection
to return to assignment highlighting. **Roster** offers create/preview and safe
draft regeneration. **Reports** opens role/physician tables.

Report absence entries show the physician's stored surname and the same icons
as the calendar (EF keeps its compact label). PDF dates come first, with weekdays
in a separate fixed-width position so both align down the page.

See [Phase 2E workspace, migration and verification](../docs/neuro_admin_phase_2e.md).
