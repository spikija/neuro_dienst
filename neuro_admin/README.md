# NeuroDienst Admin

Administrator-only desktop roster and workload client. Windows first; macOS runner
included, not yet qualified. Phase 2C supports confirmed manual additions through
an atomic admin+MFA RPC after the backend migration is deployed. Unmigrated backends
remain preview-only. No direct assignment table writes, removal or replacement.

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
