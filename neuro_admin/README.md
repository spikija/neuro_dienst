# NeuroDienst Admin

Administrator-only, read-only desktop roster and workload client. Windows first;
macOS runner included, not yet qualified. No roster writes or assignment editing.

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
