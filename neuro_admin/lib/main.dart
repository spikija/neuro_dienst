import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_admin_services/supabase_admin_directory.dart';
import 'localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:neuro_admin_services/supabase_admin_mutations.dart';

import 'auth/session_gate.dart';
import 'data/roster_reader.dart';
import 'supabase_config.dart';
import 'calendar_theme.dart';
import 'package:neuro_admin_services/supabase_admin_workspace.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = SupabaseConfig.fromEnvironment();
  SupabaseClient? client;
  String? startupError;
  if (config.isConfigured) {
    try {
      if (config.validationError != null) throw const FormatException();
      await Supabase.initialize(
        url: config.url.trim(),
        publishableKey: config.publishableKey.trim(),
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
      client = Supabase.instance.client;
    } catch (_) {
      startupError =
          config.validationError ??
          'Could not initialize Supabase. Check configuration and restart the app.';
    }
  }
  runApp(
    NeuroAdminApp(config: config, client: client, startupError: startupError),
  );
}

class NeuroAdminApp extends StatefulWidget {
  final SupabaseConfig config;
  final SupabaseClient? client;
  final String? startupError;

  const NeuroAdminApp({
    super.key,
    this.config = const SupabaseConfig.fromEnvironment(),
    this.client,
    this.startupError,
  });

  @override
  State<NeuroAdminApp> createState() => _NeuroAdminAppState();
}

class _NeuroAdminAppState extends State<NeuroAdminApp> {
  Locale _locale = const Locale('en');
  bool _languageChosen = false;
  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        'admin_language',
      );
      if (mounted && !_languageChosen && ['en', 'de'].contains(saved)) {
        setState(() => _locale = Locale(saved!));
      }
    } catch (_) {
      /* English remains available if preference storage fails. */
    }
  }

  void _setLanguage(Locale locale) {
    _languageChosen = true;
    setState(() => _locale = locale);
    SharedPreferences.getInstance()
        .then((p) => p.setString('admin_language', locale.languageCode))
        .catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final config = widget.config;
    final startupError = widget.startupError;
    return MaterialApp(
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          AdminLanguageScope(onChanged: _setLanguage, child: child!),
      title: 'NeuroDienst Admin',
      debugShowCheckedModeBanner: false,
      theme: adminTheme(Brightness.light),
      darkTheme: adminTheme(Brightness.dark),
      home: client != null
          ? SessionGate(
              gateway: SupabaseSessionGateway(client),
              reader: SupabaseRosterReader(client),
              mutations: SupabaseAssignmentMutationService(client),
              generation: SupabaseWorkspaceService(client),
              removals: SupabaseWorkspaceService(client),
              reporting: SupabaseReportingService(client),
              administration: SupabaseDirectoryService(client),
            )
          : Scaffold(
              appBar: AppBar(
                title: const AdminText('NeuroDienst Admin'),
                actions: const [LanguageButton()],
              ),
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _PlaceholderPane(
                              title: 'Roster calendar',
                              icon: Icons.calendar_month_outlined,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: _PlaceholderPane(
                              title: 'Physicians / workload',
                              icon: Icons.groups_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const AdminText('Desktop administrator client'),
                    const SizedBox(height: 4),
                    AdminText(
                      startupError ??
                          (config.isConfigured
                              ? 'Supabase is not initialized. Restart with valid configuration.'
                              : 'Supabase configuration not provided'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PlaceholderPane extends StatelessWidget {
  final String title;
  final IconData icon;

  const _PlaceholderPane({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(icon),
              AdminText(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
