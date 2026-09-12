class AuthRedirects {
  // Must exactly match Authentication > URL Configuration > Redirect URLs.
  // Android/iOS register the scheme and auth host, including this path.
  static const passwordRecovery = 'io.neurodienst.app://auth/reset-password';

  const AuthRedirects._();
}
