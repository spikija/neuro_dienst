import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'demo/demo_roster.dart';
import 'screens/month_screen.dart';
import 'services/supabase_bootstrap.dart';
import 'services/supabase_doctor_service.dart';
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
      home: AuthGate(
        child: _AuthorizedMonthHome(
          roster: widget.roster,
          currentDoctor: selectedDoctor,
          doctors: doctors,
          onDoctorChanged: (doctor) {
            setState(() {
              selectedDoctor = doctor;
            });
          },
          onDoctorUpdated: _updateDoctor,
        ),
      ),
    );
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

  const _AuthorizedMonthHome({
    required this.roster,
    required this.currentDoctor,
    required this.doctors,
    required this.onDoctorChanged,
    required this.onDoctorUpdated,
  });

  @override
  State<_AuthorizedMonthHome> createState() => _AuthorizedMonthHomeState();
}

class _AuthorizedMonthHomeState extends State<_AuthorizedMonthHome> {
  late Future<_AuthorizedHomeData> _homeDataFuture;
  late Doctor _selectedDoctor;
  List<Doctor>? _databaseDoctors;

  @override
  void initState() {
    super.initState();
    _selectedDoctor = widget.currentDoctor;
    _homeDataFuture = _loadHomeData();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AuthorizedHomeData>(
      future: _homeDataFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final doctors = data?.doctors ?? _databaseDoctors ?? widget.doctors;
        final selectedDoctor = _doctorFromListOrFallback(
          doctors,
          _selectedDoctor,
        );

        return MonthScreen(
          roster: widget.roster,
          currentDoctor: selectedDoctor,
          doctors: doctors,
          showAdmin: data?.isAdmin ?? false,
          onDoctorChanged: _setSelectedDoctor,
          onDoctorUpdated: _updateDoctor,
          onAdminClosed: _reloadHomeData,
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
      return _AuthorizedHomeData(isAdmin: false, doctors: widget.doctors);
    }

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    final databaseDoctors = await SupabaseDoctorService().loadActiveDoctors();
    final doctors = databaseDoctors.isEmpty ? widget.doctors : databaseDoctors;

    _databaseDoctors = doctors;
    _selectedDoctor = _doctorFromListOrFallback(doctors, _selectedDoctor);

    return _AuthorizedHomeData(
      isAdmin: profile?['role'] == 'admin',
      doctors: doctors,
    );
  }

  void _setSelectedDoctor(Doctor doctor) {
    setState(() {
      _selectedDoctor = doctor;
    });

    widget.onDoctorChanged(doctor);
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

class _AuthorizedHomeData {
  final bool isAdmin;
  final List<Doctor> doctors;

  const _AuthorizedHomeData({required this.isAdmin, required this.doctors});
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
