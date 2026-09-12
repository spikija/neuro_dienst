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

## Android Studio and the Pixel emulator

Supabase settings are compile-time Dart defines. Starting `lib/main.dart`
without them launches demo mode, even if a previous installation used Supabase.
Hot reload does not add missing build-time configuration.

For local development, keep the project URL and **publishable** client key in
`neuro_app/.env.supabase.json` (ignored by Git):

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT_REF.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "YOUR_PUBLISHABLE_KEY"
}
```

In Android Studio, open the `neuro_app` Flutter project, select the Pixel emulator,
and open **Run > Edit Configurations > main.dart**. Set **Additional run args** to:

```text
--dart-define-from-file=.env.supabase.json
```

Stop the current run and press Run again so the app is rebuilt with these values.
The local `main.dart` run configuration points to this file. If no saved session
exists, the connected app shows the sign-in screen; otherwise it restores that
session. Its startup log contains `Supabase init completed` instead of the demo
mode message.

The equivalent command, from `neuro_app`, is:

```powershell
flutter run -d emulator-5554 --dart-define-from-file=.env.supabase.json
```

Use the actual device ID from `flutter devices` if it differs. The local config
file is for the public client key only; do not put a secret/service-role key in it.

Never put the Secret key into Flutter source code or `--dart-define` commands
for client apps.

## Password recovery

In Authentication > URL Configuration > Redirect URLs, add the exact URL
`io.neurodienst.app://auth/reset-password`. This already matches the app's
`AuthRedirects.passwordRecovery`; no code URL change is needed when correcting
the dashboard to this value. The bare `io.neurodienst.app://auth` entry does not
cover the recovery path. Follow the [release test plan](password_recovery_testing.md)
to check email delivery, warm/cold app launch, password updates and invalid links.

## First Admin User

Create your own user in the Supabase dashboard:

1. Open Authentication > Users.
2. Add a user with an internal email and a strong password.
   For username login, use this pattern:

```text
spikija@neurodienst.local
```

The app login screen asks for `spikija` and internally signs in with
`spikija@neurodienst.local`. A real email address can still be entered directly
if needed.

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
