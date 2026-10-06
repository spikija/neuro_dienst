import 'package:neuro_core/neuro_core.dart';

import 'roster_reader.dart';

/// Half-open date window. Ninety days is deliberately not three calendar months.
class WorkloadWindow {
  final DateTime start;
  final DateTime end;
  const WorkloadWindow(this.start, this.end);
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

class RoleWorkload {
  final StoredRole role;
  final int assignments;
  final int days;
  const RoleWorkload(this.role, this.assignments, this.days);
}

class PhysicianWorkload {
  final int assignments;
  final int assignedDays;
  final int provisional;
  final int recordedDuty24Days;
  final int recordedWeekendDuty24Days;
  final List<RoleWorkload> roles;
  const PhysicianWorkload(
    this.assignments,
    this.assignedDays,
    this.provisional,
    this.recordedDuty24Days,
    this.recordedWeekendDuty24Days,
    this.roles,
  );
  int get confirmed => assignments - provisional;
}

PhysicianWorkload workloadFor(
  RosterSnapshot snapshot,
  Doctor doctor,
  WorkloadWindow window,
) {
  final facts = snapshot.facts
      .where(
        (fact) =>
            fact.doctor.id == doctor.id && window.contains(fact.duty.date),
      )
      .toList();
  final byRole = <String, List<AssignmentFact>>{};
  for (final fact in facts) {
    (byRole[fact.duty.role.id] ??= []).add(fact);
  }
  final dutyDays = <DateTime>{};
  for (final period in doctor.availabilities.where(
    (period) => period.type == AvailabilityType.duty24,
  )) {
    final start = DateTime.utc(
      period.start.year,
      period.start.month,
      period.start.day,
    );
    final end = DateTime.utc(period.end.year, period.end.month, period.end.day);
    for (
      var date = start.isBefore(window.start) ? window.start : start;
      !date.isAfter(end) && date.isBefore(window.end);
      date = date.add(const Duration(days: 1))
    ) {
      dutyDays.add(date);
    }
  }
  final roles = [
    for (final group in byRole.values)
      RoleWorkload(
        group.first.duty.role,
        group.length,
        group.map((fact) => fact.duty.date).toSet().length,
      ),
  ]..sort((a, b) => a.role.code.compareTo(b.role.code));
  return PhysicianWorkload(
    facts.length,
    facts.map((fact) => fact.duty.date).toSet().length,
    facts.where((fact) => fact.state == AssignmentState.provisional).length,
    dutyDays.length,
    dutyDays.where((date) => date.weekday >= DateTime.saturday).length,
    roles,
  );
}
