# NeuroDienst Google Play release checklist

This project is prepared for a first **internal testing** release. Do not start production review until the legal and visual items below are complete.

## Fixed Android identity

- App name: `NeuroDienst`
- Application ID: `io.neurodienst.app`
- Current version: `0.2.0+2`
- Auth deep link: `io.neurodienst.app://auth`

The application ID cannot be changed after the first Play Console artifact is uploaded. Confirm it before creating the app.

## 1. Create and protect the upload key

Run this once in PowerShell. Keep the keystore outside the repository and back it up securely.

```powershell
keytool -genkeypair -v -keystore C:\secure\neurodienst\neurodienst-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `neuro_app/android/key.properties.example` to `neuro_app/android/key.properties`, then replace every placeholder. The real file and `.jks` files are ignored by Git. Never send the keystore or its passwords in chat or commit them.

Google Play App Signing should be enabled in Play Console. The local key is the upload key; Google manages the app-signing key.

## 2. Build the Android App Bundle

From `neuro_app`:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release --dart-define=SUPABASE_URL=https://aafmrdxsuvqwztndjefa.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The output is `build/app/outputs/bundle/release/app-release.aab`. A Supabase publishable key is designed for client applications; never build a service-role key or database password into the app.

Increment the build number after every uploaded bundle (`0.2.0+3`, `0.2.0+4`, and so on). Play Console rejects a reused version code.

## 3. Supabase production configuration

- Add `io.neurodienst.app://auth` to the allowed Auth redirect URLs.
- Keep Row Level Security enabled and verify ordinary doctors cannot invoke admin operations.
- Require MFA for privileged admin actions.
- Create a dedicated Play reviewer account with non-destructive sample data. Store its credentials in Play Console **App access**, not in this repository.
- Verify password reset, invitation, login, logout, and deep-link recovery on a physical Android device using the release build.

## 4. Play Console declarations

- **App access:** explain that login is required and provide working reviewer credentials and navigation instructions.
  Use `docs/google_play_review_access.md` to provision and verify the dedicated non-admin reviewer account.
- **Data safety:** declare account identifiers, professional profile data, roster/absence data, and operational/security data sent to Supabase. Declare optional device-calendar access and its import/export purpose. The app currently has no ads or advertising SDK.
- **Data deletion:** provide a public HTTPS URL for `docs/account_deletion.md`; the app also exposes the request under Profile.
- **Privacy policy:** publish `docs/privacy_policy.md` at a public, non-editable HTTPS URL and enter it in Play Console and the store listing.
- **Permissions:** explain that calendar permissions support user-initiated roster import/export. If Play flags broad calendar access, replace it with a narrower system-calendar flow before production.
- Complete content rating, target audience, ads, health-app, and government-affiliation declarations accurately. NeuroDienst must not imply official institutional sponsorship unless that authorization exists.

GitHub Pages is a no-cost way to publish the two policy pages without buying a domain. After publishing, test both URLs in a private browser window without signing in.

## 5. Store assets

- Final launcher icons and the 512 x 512 Play icon are prepared in `docs/google_play/assets/` and the Android density-specific launcher files.
- The 1024 x 500 feature graphic is prepared in `docs/google_play/assets/`.
- At least two representative phone screenshots, with no real staff roster or personal data.
- Support email and a concise English/German store description.

Use `docs/google_play/PLAY_CONSOLE_SUBMISSION.md` for the complete copy/paste listing, declarations, reviewer instructions, and screenshot plan.

Suggested short description (80-character limit):

> Plan neurology duty rosters, absences and team coverage securely.

Suggested full-description opening:

> NeuroDienst gives authorized clinical teams one shared view of monthly duty assignments, absences and coverage. Doctors can review their duties, submit planning changes and export assignments to their device calendar, while designated administrators manage users, roles and roster publication.

## 6. Release sequence

1. Upload the signed `.aab` to **Internal testing**.
2. Add a small tester group and complete a closed workflow test on Android.
   If this is a personal developer account created after 13 November 2023,
   keep at least 12 testers continuously opted in to the closed test for 14
   days before applying for production access.
3. Review pre-launch reports and fix crashes, layout issues, security findings, and accessibility problems.
4. Complete the legal controller/retention details in both policy pages.
5. Replace placeholder launcher/store artwork and capture sanitized screenshots.
6. Promote only the tested artifact to closed testing, then production when the operational owner approves it.
