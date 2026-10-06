import 'dart:convert';

/// Public client configuration only. Never supply a service-role key.
///
/// The authenticated client reads the shared backend. No service-role operations
/// or automatic authentication callback registration are supported.
class SupabaseConfig {
  final String url;
  final String publishableKey;

  const SupabaseConfig({required this.url, required this.publishableKey});

  const SupabaseConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  String? get validationError {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return 'SUPABASE_URL must be a valid HTTP or HTTPS URL.';
    }
    if (publishableKey.trim().startsWith('sb_secret_')) {
      return 'Use a Supabase publishable key, never a secret key.';
    }
    final parts = publishableKey.trim().split('.');
    if (parts.length == 3) {
      try {
        final claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
        if (claims is Map && claims['role'] == 'service_role') {
          return 'Use a Supabase publishable key, never a service-role key.';
        }
      } on FormatException {
        return 'Invalid Supabase public key.';
      }
    }
    return null;
  }
}
