import 'package:flutter_riverpod/legacy.dart';
import 'package:neuro_core/neuro_core.dart';

final currentDoctorProvider = StateProvider<Doctor?>((ref) => null);

final currentRosterProvider = StateProvider<RosterMonth?>((ref) => null);
