# Password recovery release tests

## Configuration

The URL confirmed in Supabase and already used by `AuthRedirects.passwordRecovery` is:

```text
io.neurodienst.app://auth/reset-password
```

Keep this exact URL in **Authentication > URL Configuration > Redirect URLs**.
The shorter `io.neurodienst.app://auth` entry does not cover the recovery path.
No application redirect change is needed for the dashboard correction.
Android and iOS already register the app's custom URL scheme. Windows registers
the scheme when the app starts. If shipping another platform, verify its link
registration separately.

Both Android and iOS disable Flutter's default deep-link handler so Supabase's
`app_links` integration handles the recovery callback. The missing iOS opt-out
has been added, following [Flutter's guidance](https://docs.flutter.dev/ui/navigation/deep-linking).
The iOS setting still needs verification on an iOS release build.

Supabase's reset email should use its verification link (`{{ .ConfirmationURL }}`
in the standard template), rather than a plain link to the app. A plain app link
does not establish the authenticated recovery session. If using a customized
template, verify that it preserves the requested redirect and verification step.
See [Supabase redirect configuration](https://supabase.com/docs/guides/auth/redirect-urls)
and [Flutter password reset](https://supabase.com/docs/reference/dart/auth-resetpasswordforemail).

The Flutter client uses PKCE. Request the reset from the installed app and open
the email on the same device, returning to the same installation. Do not clear
app storage or reinstall between requesting and opening the link: the locally
stored verifier is required. A dashboard-generated link or a link opened on a
different device is not an equivalent test of this flow.

## Test on the release build before shipping

Use a dedicated test account with a real mailbox and access to the test roster.
Install through the intended distribution channel (for Android, the Play internal
testing track) with the real Supabase configuration. Demo mode has no login flow.
Use a fresh reset email for each successful scenario.

| Scenario | Steps and expected result |
| --- | --- |
| Main path | Sign out, tap **Forgot password?**, enter the registered email, and send. The app displays the same neutral confirmation regardless of whether an account exists. The real account receives an email. |
| App still open | Leave the request confirmation visible, open the email and follow its link. **Choose new password** must appear immediately above the old request page, with no roster/splash blocking it. |
| Cold start | Request a fresh link, close the app without clearing its data, then follow the email link. The app starts on **Choose new password**. |
| Existing session | Request a fresh link, sign in, open another app page, then follow the link. Recovery takes priority over that page and regular app access. |
| Password validation | A password shorter than 12 characters or a mismatching confirmation stays on the form with a useful error. A matching valid password succeeds. Check with the keyboard visible on a small phone. |
| Login afterward | On success the app returns to sign-in. The new password works and the old password fails. Check on a second installation too. |
| Cancel | Follow a fresh link, then tap **Cancel**. The recovery session is signed out and the old password still works. |
| Expired / reused link | Open an expired link and reopen a link after a completed reset. It must not authorize another reset. Depending on where validation fails, Supabase may show an error in the browser or the app shows a retry message. Requesting a fresh link must recover. |
| Missing verifier | Open a fresh link on a different device. It must not silently complete recovery. Request a new link from the device where recovery will be completed. |
| Invalid / unknown email | A clearly invalid address stays on the form; a syntactically valid unregistered email does not reveal whether an account exists. |
| Network / rate limit | Disable connectivity before sending or submitting; retry after restoring it. Repeated sends subject to Supabase rate limits show an error and allow retry later. Rapid button/keyboard submissions must not create duplicate requests. |

Repeat the main, warm-start and cold-start paths on every platform being released,
using the email clients your users actually use. This verifies email delivery,
browser-to-app handoff and the installed release's platform configuration.

If email arrives but the app does not open, first inspect the redirect and platform
link registration. If the app opens without recovery, inspect auth errors and the
PKCE installation/device. Do not share reset URLs or tokens in bug reports.

## Automated checks

From `neuro_app`:

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

`test/password_recovery_test.dart` covers the exact redirect sent by the form,
email normalization, duplicate request prevention, validation/retry, recovery
navigation above the request screen, replayed startup recovery, token refresh,
password submission/sign-out, cancellation, auth errors, and small-screen layout.
It uses a fake auth client: email delivery, Supabase's allowlist, token expiration,
password persistence and real OS link handoff still require the release tests above.
