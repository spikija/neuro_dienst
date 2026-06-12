import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const key = publishableKey != '' ? publishableKey : legacyAnonKey;

  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;
}

Future<void> initializeSupabaseIfConfigured() async {
  if (!SupabaseConfig.isConfigured) {
    debugPrint('Supabase is not configured; running with demo data.');
    return;
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.key,
  );
}
