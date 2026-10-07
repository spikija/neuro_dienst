import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/data/roster_reader.dart';
import 'package:neuro_admin/data/workload.dart';
import 'package:neuro_admin/data/workload_category.dart';
import 'package:neuro_core/neuro_core.dart';

import 'phase_one_test.dart' show fixture;

void main() {
  test('only exact evidenced role codes receive a clinical category', () {
    for (final code in ['SUL', 'SU1', 'SU2']) {
      expect(classifyRoleCode(code), WorkloadCategory.station);
    }
    expect(classifyRoleCode('AMB'), WorkloadCategory.ambulance);
    expect(classifyRoleCode('SCI'), WorkloadCategory.science);
    for (final code in [
      'SON',
      'NVB',
      'OFO',
      'ICB',
      'CUSTOM',
      'duty_24',
      '24H',
      'amb',
      '',
    ]) {
      expect(classifyRoleCode(code), WorkloadCategory.other, reason: code);
    }
  });

  test(
    'category days deduplicate roles per date, retain inactive history and use half-open 90-day bounds',
    () {
      final original = fixture();
      final doctor = original.doctors.single;
      final start = original.historyStart;
      final end = original.historyEnd;
      final facts = <AssignmentFact>[];
      void add(
        String code,
        DateTime date, {
        AssignmentState state = AssignmentState.confirmed,
      }) {
        final id = 'a${facts.length}';
        // Clock instants deliberately fall on a different date: scheduling uses
        // the stored DATE, including the first/last days of the reporting window.
        final duty = StoredDuty(
          id,
          date,
          StoredRole(code, code, code),
          end,
          end.add(const Duration(hours: 24)),
          1,
        );
        facts.add(AssignmentFact(id, doctor, duty, state, RosterPhase.locked));
      }

      add('SUL', start.subtract(const Duration(days: 1))); // excluded
      add('SUL', start);
      add('SU1', start); // same station date
      add('SU2', start); // same station date
      add(
        'SU1',
        start.add(const Duration(days: 1)),
        state: AssignmentState.provisional,
      );
      add('AMB', start);
      add('AMB', start); // duplicate date, separate assignment
      add('SCI', end.subtract(const Duration(days: 1)));
      add('SCI', end); // excluded
      add('SON', start);
      add('NVB', start);
      add('OFO', start);
      add('ICB', start);
      add('CUSTOM', start);
      final snapshot = RosterSnapshot(
        original.month,
        original.days,
        original.doctors,
        original.inactiveDoctorIds,
        facts,
        original.loadedHistoryDates,
      );
      final totals = workloadFor(snapshot, doctor, WorkloadWindow(start, end));
      expect(snapshot.inactiveDoctorIds, contains(doctor.id));
      expect(totals.assignments, 12);
      expect(totals.assignedDays, 3);
      expect(totals.confirmed, 11);
      expect(totals.provisional, 1);
      expect(totals.daysFor(WorkloadCategory.station), 2);
      expect(totals.daysFor(WorkloadCategory.ambulance), 1);
      expect(totals.daysFor(WorkloadCategory.science), 1);
      expect(totals.daysFor(WorkloadCategory.other), 1);
      expect(totals.recordedDuty24Days, 3);
      expect(totals.daysFor(WorkloadCategory.duty24h), 3);
      expect(totals.recordedWeekendDuty24Days, 2);
      expect(
        totals.roles.firstWhere((role) => role.role.code == 'AMB').assignments,
        2,
      );
    },
  );
}
