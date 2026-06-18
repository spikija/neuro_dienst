import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo/demo_roster.dart';
import 'l10n/app_language.dart';
import 'l10n/app_localizations.dart';
import 'screens/admin_home_screen.dart';
import 'screens/mfa_screen.dart';
import 'screens/month_screen.dart';
import 'services/supabase_bootstrap.dart';
import 'services/supabase_doctor_service.dart';
import 'services/supabase_roster_service.dart';
import 'widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeSupabaseIfConfigured();

  final roster = DemoRoster.createJune2026();
  final doctor = DemoRoster.createCurrentDoctor();
  final doctors = DemoRoster.createDoctors();

  runApp(
    ProviderScope(
      child: NeuroDienstApp(
        roster: roster,
        currentDoctor: doctor,
        doctors: doctors,
      ),
    ),
  );
}

class NeuroDienstApp extends StatefulWidget {
  final RosterMonth roster;
  final Doctor currentDoctor;
  final List<Doctor> doctors;

  const NeuroDienstApp({
    super.key,
    required this.roster,
    required this.currentDoctor,
    required this.doctors,
  });

  @override
  State<NeuroDienstApp> createState() => _NeuroDienstAppState();
}

class _NeuroDienstAppState extends State<NeuroDienstApp> {
  late Doctor selectedDoctor;
  late List<Doctor> doctors;
  ThemeMode _themeMode = ThemeMode.light;
  AppLanguage _language = AppLanguage.english;

  @override
  void initState() {
    super.initState();
    selectedDoctor = widget.currentDoctor;
    doctors = widget.doctors;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NeuroDienst',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      builder: (context, child) {
        return AppLocalizations(language: _language, child: child!);
      },
      home: AuthGate(
        child: _AuthorizedMonthHome(
          key: ValueKey(
            SupabaseConfig.isConfigured
                ? Supabase.instance.client.auth.currentUser?.id
                : 'demo',
          ),
          roster: widget.roster,
          currentDoctor: selectedDoctor,
          doctors: doctors,
          language: _language,
          onLanguageChanged: _setLanguage,
          onDoctorChanged: (doctor) {
            setState(() {
              selectedDoctor = doctor;
            });
          },
          onDoctorUpdated: _updateDoctor,
          isDarkMode: _themeMode == ThemeMode.dark,
          onToggleDarkMode: _toggleDarkMode,
        ),
      ),
    );
  }

  void _toggleDarkMode() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  Future<void> _setLanguage(AppLanguage language) async {
    setState(() {
      _language = language;
    });

    if (!SupabaseConfig.isConfigured) {
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return;
    }

    await Supabase.instance.client
        .from('profiles')
        .update({'preferred_language': language.code})
        .eq('id', userId);
  }

  void _updateDoctor(Doctor updatedDoctor) {
    setState(() {
      doctors = doctors
          .map(
            (doctor) => doctor.id == updatedDoctor.id ? updatedDoctor : doctor,
          )
          .toList();

      if (selectedDoctor.id == updatedDoctor.id) {
        selectedDoctor = updatedDoctor;
      }
    });
  }
}

class _AuthorizedMonthHome extends StatefulWidget {
  final RosterMonth roster;
  final Doctor currentDoctor;
  final List<Doctor> doctors;
  final ValueChanged<Doctor> onDoctorChanged;
  final ValueChanged<Doctor> onDoctorUpdated;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;
  final bool isDarkMode;
  final VoidCallback onToggleDarkMode;

  const _AuthorizedMonthHome({
    super.key,
    required this.roster,
    required this.currentDoctor,
    required this.doctors,
    required this.onDoctorChanged,
    required this.onDoctorUpdated,
    required this.language,
    required this.onLanguageChanged,
    required this.isDarkMode,
    required this.onToggleDarkMode,
  });

  @override
  State<_AuthorizedMonthHome> createState() => _AuthorizedMonthHomeState();
}

class _AuthorizedMonthHomeState extends State<_AuthorizedMonthHome> {
  late Future<_AuthorizedHomeData> _homeDataFuture;
  late Doctor _selectedDoctor;
  late DateTime _visibleMonth;
  List<Doctor>? _databaseDoctors;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _selectedDoctor = widget.currentDoctor;
    _visibleMonth = DateTime(widget.roster.year, widget.roster.month);
    _homeDataFuture = _loadHomeData();
    if (SupabaseConfig.isConfigured) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) {
            if (mounted) {
              _reloadHomeData();
            }
          });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AuthorizedHomeData>(
      future: _homeDataFuture,
      builder: (context, snapshot) {
        if (SupabaseConfig.isConfigured &&
            snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _HomeErrorView(
            message: snapshot.error.toString(),
            onRetry: _reloadHomeData,
          );
        }

        final data = snapshot.data;
        final doctors = data?.doctors ?? _databaseDoctors ?? widget.doctors;

        if (SupabaseConfig.isConfigured && doctors.isEmpty) {
          return _NoDoctorsConfiguredView(
            isAdmin: data?.isAdmin ?? false,
            onAdminClosed: _reloadHomeData,
          );
        }

        final selectedDoctor = _doctorFromListOrFallback(
          doctors,
          _selectedDoctor,
        );

        return MonthScreen(
          roster: data?.roster ?? widget.roster,
          currentDoctor: selectedDoctor,
          doctors: doctors,
          showAdmin: data?.isAdmin ?? false,
          signedInEmail: data?.signedInEmail,
          language: widget.language,
          onLanguageChanged: widget.onLanguageChanged,
          onDoctorChanged: _setSelectedDoctor,
          onDoctorUpdated: _updateDoctor,
          onAdminClosed: _reloadHomeData,
          onVisibleMonthChanged: _setVisibleMonth,
          isDarkMode: widget.isDarkMode,
          onToggleDarkMode: widget.onToggleDarkMode,
        );
      },
    );
  }

  void _reloadHomeData() {
    setState(() {
      _homeDataFuture = _loadHomeData();
    });
  }

  Future<_AuthorizedHomeData> _loadHomeData() async {
    if (!SupabaseConfig.isConfigured) {
      return _AuthorizedHomeData(isAdmin: false, doctors: widget.doctors);
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;

    if (userId == null) {
      return const _AuthorizedHomeData(isAdmin: false, doctors: []);
    }

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role, preferred_language')
        .eq('id', userId)
        .maybeSingle();
    final isAdmin = profile?['role'] == 'admin';

    final preferredLanguage = AppLanguage.fromCode(
      profile?['preferred_language'] as String?,
    );

    if (preferredLanguage != widget.language) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onLanguageChanged(preferredLanguage);
        }
      });
    }

    final databaseDoctors = await SupabaseDoctorService().loadActiveDoctors();
    final linkedDoctorId = await _loadLinkedDoctorId(userId);
    final databaseRoster = await SupabaseRosterService().loadRoster(
      year: _visibleMonth.year,
      month: _visibleMonth.month,
      doctors: databaseDoctors,
    );

    _databaseDoctors = databaseDoctors;
    _selectedDoctor = isAdmin
        ? _doctorFromListOrFallback(databaseDoctors, _selectedDoctor)
        : _doctorByIdOrFallback(databaseDoctors, linkedDoctorId);

    return _AuthorizedHomeData(
      isAdmin: isAdmin,
      doctors: databaseDoctors,
      roster: databaseRoster,
      signedInEmail: Supabase.instance.client.auth.currentUser?.email,
    );
  }

  Future<String?> _loadLinkedDoctorId(String userId) async {
    final row = await Supabase.instance.client
        .from('doctors')
        .select('id')
        .eq('auth_user_id', userId)
        .eq('is_active', true)
        .maybeSingle();

    return row?['id'] as String?;
  }

  void _setSelectedDoctor(Doctor doctor) {
    setState(() {
      _selectedDoctor = doctor;
    });

    widget.onDoctorChanged(doctor);
  }

  void _setVisibleMonth(DateTime month) {
    _visibleMonth = DateTime(month.year, month.month);
  }

  void _updateDoctor(Doctor updatedDoctor) {
    final currentDoctors = _databaseDoctors ?? widget.doctors;

    setState(() {
      _databaseDoctors = currentDoctors
          .map(
            (doctor) => doctor.id == updatedDoctor.id ? updatedDoctor : doctor,
          )
          .toList();

      if (_selectedDoctor.id == updatedDoctor.id) {
        _selectedDoctor = updatedDoctor;
      }
    });

    widget.onDoctorUpdated(updatedDoctor);
  }
}

class _NoDoctorsConfiguredView extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onAdminClosed;

  const _NoDoctorsConfiguredView({
    required this.isAdmin,
    required this.onAdminClosed,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('app.name')),
        actions: [
          IconButton(
            tooltip: l10n.t('signOut'),
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.group_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  l10n.t('noDoctorsConfigured'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  isAdmin
                      ? l10n.t('noDoctorsConfiguredAdmin')
                      : l10n.t('noDoctorsConfiguredUser'),
                  textAlign: TextAlign.center,
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openAdmin(context),
                    icon: const Icon(Icons.admin_panel_settings),
                    label: Text(l10n.t('openAdmin')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAdmin(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const MfaScreen(verifiedDestinationBuilder: _buildAdminHomeScreen),
      ),
    );

    if (!context.mounted) {
      return;
    }

    onAdminClosed();
  }
}

class _HomeErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _HomeErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('app.name')),
        actions: [
          IconButton(
            tooltip: l10n.t('signOut'),
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.t('retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorizedHomeData {
  final bool isAdmin;
  final List<Doctor> doctors;
  final RosterMonth? roster;
  final String? signedInEmail;

  const _AuthorizedHomeData({
    required this.isAdmin,
    required this.doctors,
    this.roster,
    this.signedInEmail,
  });
}

Doctor _doctorFromListOrFallback(List<Doctor> doctors, Doctor fallback) {
  for (final doctor in doctors) {
    if (doctor.id == fallback.id) {
      return doctor;
    }
  }

  if (doctors.isNotEmpty) {
    return doctors.first;
  }

  return fallback;
}

Doctor _doctorByIdOrFallback(List<Doctor> doctors, String? doctorId) {
  if (doctorId != null) {
    for (final doctor in doctors) {
      if (doctor.id == doctorId) {
        return doctor;
      }
    }
  }

  if (doctors.isNotEmpty) {
    return doctors.first;
  }

  return DemoRoster.createCurrentDoctor();
}

Widget _buildAdminHomeScreen(BuildContext context) {
  return const AdminHomeScreen();
}
