# Supabase Setup

The app can run in two modes:

- without Supabase settings: demo data mode
- with Supabase settings: initializes the Supabase client at startup

Run the Windows app with Supabase enabled:

```powershell
cd C:\apps\neuro_dienst\neuro_app
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

If the console prints `Supabase is not configured; running with demo data.`,
the app was started without these two `--dart-define` values. In demo mode the
login screen and Admin button are intentionally hidden.

The older `SUPABASE_ANON_KEY` name is also accepted as a fallback, but new
commands should use `SUPABASE_PUBLISHABLE_KEY`.

Never put the Secret key into Flutter source code or `--dart-define` commands
for client apps.

## First Admin User

Create your own user in the Supabase dashboard:

1. Open Authentication > Users.
2. Add a user with your email and a strong password.
3. Copy the created user ID.
4. Open SQL Editor and insert the matching profile:

```sql
insert into public.profiles (id, role, display_name)
values (
  'PASTE_AUTH_USER_ID_HERE',
  'admin',
  'Slaven Pikija'
);
```

Later admin screens will use this profile role, together with MFA assurance
level `aal2`, for protected changes.

The first time you open Admin in the app, it will ask you to set up two-factor
verification with an authenticator app. After scanning the QR code and entering
the six-digit code, the current session is promoted to `aal2` and admin database
writes are allowed by Row Level Security.
