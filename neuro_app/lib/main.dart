import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_core/neuro_core.dart';

import 'demo/demo_roster.dart';
import 'screens/month_screen.dart';
import 'services/supabase_bootstrap.dart';
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
        child: MonthScreen(
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
