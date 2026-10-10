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

Select a role and physician to highlight the whole month and preselect valid
dates. Click to deselect/reselect; drag adds only assignable days. Clear selection
keeps validity visible. Apply confirms only the selected valid dates.

Selection actions are in **Selection**. To target occupied/blocked dates for
removal, enable **Select occupied days for removal**; then choose selected-role
or all-role unassignment and review its confirmation. Disable removal selection
to return to assignment highlighting. **Roster** offers create/preview and safe
draft regeneration. **Reports** opens role/physician tables.

See [Phase 2E workspace, migration and verification](../docs/neuro_admin_phase_2e.md).
