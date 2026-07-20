# NeuroDienst Google Play Console submission worksheet

Prepared from the Android manifest, Flutter source, Supabase schema, and bundled dependencies on 16 July 2026.

This is a copy/paste worksheet, not legal advice. Re-check each answer against the production Supabase configuration and any services added after this audit.

## Owner details to complete before production

Replace every `OWNER ACTION` item before submitting a production release:

- `OWNER ACTION` Publish the privacy policy at a public HTTPS URL.
- `OWNER ACTION` Publish the account-deletion page at a public HTTPS URL.
- `OWNER ACTION` Confirm the Supabase production project region.
- `OWNER ACTION` Create a dedicated reviewer account and enter its credentials only in Play Console.
- `OWNER ACTION` Confirm whether the developer account represents the developer personally or an institution. Do not claim hospital or government affiliation without authorization.

## App identity

- App name: `NeuroDienst`
- Default language: English (`en-US` or `en-GB`; choose the one used by your support material)
- App or game: App
- Free or paid: Free
- Category: Medical
- Package name: `io.neurodienst.app`
- Support email: `spikija@gmail.com`

## Main store listing — English

### App name

```text
NeuroDienst
```

### Short description

```text
Coordinate neurology duty rosters, absences and team coverage securely.
```

### Full description

```text
NeuroDienst is a restricted-access duty-roster workspace for authorized neurology teams.

Keep monthly coverage clear
• Review shared monthly duty rosters in one place
• See assigned roles, working areas and coverage gaps
• Check personal duties and team availability

Plan collaboratively
• Record vacation, leave, conferences and rotations
• Select or update assignments according to your permissions
• Give designated administrators tools to manage doctors, roles and roster publication

Take your duties with you
• Export your assignments to a device calendar
• Import selected vacation dates from a device calendar
• Share an .ics calendar file when needed

Designed for controlled clinical-team access
• Email-and-password authentication
• Two-factor verification for protected administrative actions
• Role-based access to shared roster information
• English and German interface

NeuroDienst is an administrative staff-planning tool. It does not provide medical advice, diagnose conditions, recommend treatment, or store patient records. Access is available only to users invited by an authorized administrator.
```

## Main store listing — German

Add German as a custom store listing/localization if it matches the intended launch regions.

### App name

```text
NeuroDienst
```

### Short description

```text
Neurologische Dienste, Abwesenheiten und Teamabdeckung sicher koordinieren.
```

### Full description

```text
NeuroDienst ist ein zugangsbeschränkter Arbeitsbereich für die Dienstplanung autorisierter neurologischer Teams.

Monatliche Abdeckung im Blick
• Gemeinsame Monatsdienstpläne an einem Ort prüfen
• Zugewiesene Rollen, Arbeitsbereiche und Abdeckungslücken sehen
• Eigene Dienste und Teamverfügbarkeit prüfen

Gemeinsam planen
• Urlaub, Abwesenheiten, Kongresse und Rotationen eintragen
• Zuweisungen im Rahmen der eigenen Berechtigungen auswählen oder ändern
• Ärztinnen und Ärzte, Rollen und Dienstplanfreigaben administrieren

Dienste in den Kalender übernehmen
• Eigene Zuweisungen in einen Gerätekalender exportieren
• Ausgewählte Urlaubstage aus einem Gerätekalender importieren
• Bei Bedarf eine .ics-Kalenderdatei teilen

Für kontrollierten Teamzugang entwickelt
• Anmeldung mit E-Mail-Adresse und Passwort
• Zwei-Faktor-Verifizierung für geschützte Verwaltungsaktionen
• Rollenbasierter Zugriff auf gemeinsame Dienstplandaten
• Oberfläche auf Deutsch und Englisch

NeuroDienst ist ein administratives Werkzeug zur Personal- und Dienstplanung. Die App erteilt keine medizinischen Ratschläge, stellt keine Diagnosen, empfiehlt keine Behandlungen und speichert keine Patientendaten. Der Zugang ist ausschließlich für durch eine autorisierte Administration eingeladene Personen vorgesehen.
```

## Graphics and screenshots

Ready-to-upload graphics are in `docs/google_play/assets/`:

- `play-icon-512.png` — Play Store icon, 512 × 512 PNG
- `feature-graphic-1024x500.png` — feature graphic, 1024 × 500 PNG

Capture at least four phone screenshots from an internal/reviewer account containing fictional data only:

1. Login screen — shows restricted access and bilingual support.
2. Monthly roster — populated with fictional clinicians and assignments.
3. Personal assignments or day view — shows practical duty details.
4. Calendar export — shows user-controlled calendar integration.
5. Optional: administrator dashboard, only if the reviewer account can access it safely.

Recommended captions:

- `One shared monthly roster`
- `See duties and coverage at a glance`
- `Keep availability coordinated`
- `Export assignments to your calendar`

Do not include real clinician names, email addresses, authentication QR codes, MFA secrets, Supabase identifiers, notifications, or patient information.

## App access

Select: **All or some functionality is restricted**.

Reviewer instructions:

```text
NeuroDienst is restricted to invited clinical-team users and requires sign-in.

Reviewer email: OWNER ACTION — enter the dedicated review account
Reviewer password: OWNER ACTION — enter the dedicated review password

Steps:
1. Launch the app and wait for the NeuroDienst splash screen to finish.
2. Enter the reviewer email and password, then select Sign in.
3. No invitation, email confirmation, one-time code, or MFA step is required.
4. The app opens on the monthly roster. The review account has access to fictional sample roster data and may safely browse the month/day views, create and remove its own assignments, and open the relevant navigation areas.

MFA instructions: Not applicable. The dedicated reviewer is a regular non-admin account and does not require MFA. Never provide a clinician's real MFA secret.

No organization VPN, geographic restriction, paid membership, QR code, or external hardware is required. If that changes, update these instructions before submission.

For help accessing the app, contact spikija@gmail.com.
```

Recommended setup: use a non-admin reviewer account with fictional data and no destructive privileges. If protected admin functionality must be reviewed, provide a separate review-only admin path and MFA instructions that remain valid for the full review period.

Copy/paste reviewer instructions:

> Open the NeuroDienst app. On the login screen, enter the email address and password provided above and tap ‘Anmelden’. No invitation, email confirmation, one-time PIN or two-factor authentication is required. The reviewer account provides access to all essential app features, including the monthly roster, daily assignments and role selection. An internet connection is required.

Provisioning, verification, reset, and deletion instructions are in
`docs/google_play_review_access.md`.

## Ads

- Does the app contain ads? **No**

Evidence: no advertising SDK is declared in `pubspec.yaml`, and no advertising integration appears in the source audit.

## Target audience and content

- Target age groups: **18 and over**
- Designed for children: **No**
- Appeal to children: **No**
- Store listing imagery aimed at children: **No**

Rationale: the app is a professional workforce-planning tool restricted to authorized clinical staff. Do not select child age groups merely because the content is non-violent.

## Content rating

Choose the **Utility, productivity, communication, or other** app category if offered. Based on the audited app, answer **No** to questionnaire items about:

- violence or graphic medical procedures;
- fear/horror content;
- sexual content or nudity;
- offensive language;
- controlled substances;
- gambling or simulated gambling;
- user-to-user public communication or public content sharing;
- unrestricted web browsing;
- purchasable digital goods;
- location sharing.

The app displays administrative duty and absence information, not medical imagery or patient treatment content. Submit the questionnaire and accept the IARC rating it calculates; do not choose a rating manually.

## Health apps declaration

Recommended conservative declaration:

- Select **Healthcare Services and Management**.
- Do not select Medical Device Apps.
- Do not claim clinical decision support, diagnosis, disease management, treatment, or patient-record functionality.

Suggested explanation if requested:

```text
NeuroDienst is an administrative workforce and duty-roster tool for authorized clinical teams. It coordinates clinician assignments and availability, including optional absence categories such as sick leave. It does not process patient records, provide medical advice, diagnose conditions, recommend treatment, or function as a medical device.
```

Why this is conservative: the app operates in a healthcare setting and can store a clinician's `sick_leave` absence status. Google says apps that access health data to support non-health functionality must complete the Health apps declaration. If Google offers a more precise non-health/administrative option in the live form, use it and preserve the explanation above.

## Data safety

### Overview answers

- Does the app collect or share required user data types? **Yes — collects data**
- Is all collected user data encrypted in transit? **Yes** (Supabase connections use HTTPS/TLS; verify the production endpoint remains HTTPS)
- Can users request deletion of data? **Yes**
- Does the app share user data with third parties? **No**, assuming Supabase acts only as your contracted service provider and production data is not disclosed to any independent third party
- Account creation method: accounts are created/invited by an administrator; users cannot freely self-register
- Account-deletion URL: `OWNER ACTION — public HTTPS URL for account_deletion.md`

Under Google's definition, processing by a service provider on the developer's behalf is generally not “sharing.” Reassess this if Supabase or another vendor uses the data for its own purposes or if another institution receives it independently.

### Data types to declare as collected

| Play data type | Collected | Required or optional | Purpose | Notes |
|---|---:|---|---|---|
| Personal info — Name | Yes | Required | App functionality; account management | First/last name and display name identify clinicians in the roster. |
| Personal info — Email address | Yes | Required | App functionality; account management; security | Used for invitation, login, password recovery and support/account deletion. |
| Personal info — User IDs | Yes | Required | App functionality; account management; security | Supabase auth ID, doctor ID and relational creator IDs. |
| Personal info — Other info | Yes | Required | App functionality; account management | Professional rank, capabilities, language preference, role and account status. |
| Health and fitness — Health info | Yes | Optional | App functionality | A user/admin may record `sick_leave`; declare conservatively because this can reveal health status. |
| App activity — Other user-generated content | Yes | Required for roster use | App functionality | Duty selections, assignments, absence/availability entries and optional planning notes. If the live form does not place this under App activity, use the closest user-generated-content category it presents. |

For each item above:

- Ephemeral processing: **No** — the backend stores it.
- Shared: **No**, subject to the service-provider qualification above.
- Collection purposes: select only those listed in the table. Do not select advertising, marketing, personalization, developer communications, or analytics.

### Data accessed but not collected off-device

Do **not** mark Calendar events as collected based on the current code. The app reads event title, calendar name, and dates locally only after the user invokes vacation import. It uploads only the dates selected by the user as a NeuroDienst absence record; it does not upload the source event title, calendar name, attendees, notes, or full calendar. Calendar export writes NeuroDienst duty events to the selected device calendar.

Update the declaration immediately if later code sends calendar-event content to Supabase or another server.

### Production configuration that can change the answers

Before submission, inspect Supabase Auth logs, Edge Function logging, any SMTP/email provider, crash reporting, analytics, and support tooling. If they collect IP addresses, device identifiers, diagnostics, app interactions, or other data beyond strictly necessary service operations, add the corresponding Play data types and purposes.

## Account deletion

- In-app request path: **Menu → Profile → Account and privacy → Request account deletion**
- Outside-app path: publish `docs/account_deletion.md` and place its HTTPS URL in Data safety.
- Current mechanism: pre-filled email request to `spikija@gmail.com`.

The published page identifies Slaven Pikija as the service operator, uses a one-month response/completion deadline, and discloses the two-year retention periods for roster/audit records and backup copies. Google requires deletion of the account and associated user data unless specific retention is justified and disclosed.

## Calendar permissions

Manifest permissions:

```text
android.permission.READ_CALENDAR
android.permission.WRITE_CALENDAR
```

Purpose explanation if Play Console requests one:

```text
Calendar access is optional and initiated by the user. READ_CALENDAR lets the user select vacation events from device calendars and converts only the selected dates into availability entries. Source event titles, calendar names, notes and attendees are not uploaded. WRITE_CALENDAR lets the user export their own NeuroDienst duty assignments to a selected device calendar and update NeuroDienst-created events. The app does not access calendars in the background or use calendar data for advertising, analytics or profiling.
```

The current manifest requests broad calendar access. If Play flags it, consider an implementation using Android's system calendar intents or another narrower user-mediated flow before production.

## Other App content declarations

- Government apps: **No**
- News apps: **No**
- Financial features: **No financial features**
- Ads: **No**
- Families/children: **Not designed for children**
- COVID-19 contact tracing/status: **No**
- Data broker activity: **No**
- Medical device: **No**

## Release notes for the first test release

### English

```text
First Google Play test release of NeuroDienst.
• Shared monthly neurology duty roster
• Personal assignments and availability planning
• Secure account access with protected admin actions
• Optional calendar import and export
• English and German interface
```

### German

```text
Erste Google-Play-Testversion von NeuroDienst.
• Gemeinsamer neurologischer Monatsdienstplan
• Persönliche Zuweisungen und Abwesenheitsplanung
• Sicherer Kontozugang und geschützte Verwaltungsaktionen
• Optionaler Kalenderimport und -export
• Deutsche und englische Oberfläche
```

## Final submission gate

Do not submit to production until all are true:

- Public privacy and deletion URLs work without login in a private browser.
- The controller identity, address, Supabase region and retention periods are correct.
- Reviewer credentials work in the Play-installed release and MFA instructions are durable.
- Screenshots use fictional data only.
- Data safety matches the production Supabase, email and logging configuration.
- The signed AAB contains the production Supabase URL and publishable key, never a service-role key.
- Password reset and `io.neurodienst.app://auth` links work on Android.
- Pre-launch reports show no unresolved crashes or high-severity issues.
