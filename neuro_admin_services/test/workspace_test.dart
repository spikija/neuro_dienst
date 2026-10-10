import 'package:test/test.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'support/preview_fixture.dart';

void main() {
  test('national statutory holidays across years without a 2037 cutoff', () {
    expect(
      AustrianHolidays.forYear(2008)[HospitalDate(2008, 5, 1)],
      'Staatsfeiertag; Christi Himmelfahrt',
    );
    for (final year in [2000, 2024, 2026, 2027, 2038, 2040, 2100, 2400]) {
      final holidays = AustrianHolidays.forYear(year);
      expect(holidays.length, 13);
      expect(holidays[HospitalDate(year, 10, 26)], 'Nationalfeiertag');
      expect(holidays[HospitalDate(year, 12, 24)], isNull);
    }
    for (final entry in {
      '2024-04-01': 'Ostermontag',
      '2026-04-06': 'Ostermontag',
      '2026-05-14': 'Christi Himmelfahrt',
      '2026-05-25': 'Pfingstmontag',
      '2026-06-04': 'Fronleichnam',
      '2027-03-29': 'Ostermontag',
      '2040-04-02': 'Ostermontag',
    }.entries) {
      final date = HospitalDate.parse(entry.key);
      final info = AustrianHolidays.day(date);
      expect(info.publicHolidayName, entry.value);
      expect(info.isPublicHoliday, isTrue);
      expect(AustrianHolidays.isWorkingDay(date), isFalse);
    }
    expect(AustrianHolidays.isWorkingDay(HospitalDate(2026, 10, 27)), isTrue);
    expect(AustrianHolidays.isWorkingDay(HospitalDate(2026, 10, 25)), isFalse);
  });
  test(
    'removal scope retains exact role identity, selected dates and no-op dates',
    () {
      final a = duty(1, role: ambulance),
          b = duty(1, role: icb),
          c = duty(2, role: ambulance);
      final facts = [
        AssignmentFact(
          'a',
          ana(),
          a,
          AssignmentState.confirmed,
          RosterPhase.draft,
        ),
        AssignmentFact(
          'b',
          ben(),
          b,
          AssignmentState.provisional,
          RosterPhase.draft,
        ),
        AssignmentFact(
          'c',
          ana(),
          c,
          AssignmentState.confirmed,
          RosterPhase.draft,
        ),
      ];
      final snapshot = previewFixture(
        slots: [a, b, c],
        facts: facts,
        contentVersion: 1,
      );
      final dates = [HospitalDate(2026, 10, 1), HospitalDate(2026, 10, 3)];
      final role = AssignmentRemovalPreview(
        snapshot,
        dates,
        scope: RemovalScope.role,
        roleId: ambulance.id,
      );
      expect(role.assignments.map((a) => a.id), ['a']);
      expect(role.noOpDates, {HospitalDate(2026, 10, 3)});
      expect(
        AssignmentRemovalPreview(
          snapshot,
          dates,
          scope: RemovalScope.all,
        ).assignments.map((a) => a.id),
        ['a', 'b'],
      );
      expect(
        () => AssignmentRemovalPreview(
          snapshot,
          dates,
          scope: RemovalScope.all,
          roleId: ambulance.id,
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'reports preserve configured visibility/order, distinct roles and inactive historical physician',
    () {
      final a = duty(1, role: ambulance), b = duty(1, role: icb);
      final snapshot = previewFixture(
        slots: [a, b],
        facts: [
          AssignmentFact(
            'a',
            ana(),
            a,
            AssignmentState.provisional,
            RosterPhase.draft,
          ),
          AssignmentFact(
            'b',
            ben(),
            b,
            AssignmentState.confirmed,
            RosterPhase.draft,
          ),
        ],
        inactive: {'ben'},
        contentVersion: 1,
      );
      final config = ReportConfiguration(
        roles: [
          ReportRoleSetting(ambulance, 2, true),
          ReportRoleSetting(icb, 1, true),
          ReportRoleSetting(leader, 0, false),
        ],
        physicianPrintOrder: {'ben': 0, 'ana': 1},
      );
      final roles = const FactualReportProjection().project(
        snapshot,
        config,
        ReportRequest(RosterVersion('october', 1), ReportLayout.roles),
      );
      expect(roles.columns.map((c) => c.id), ['icb', 'amb']);
      expect(
        roles.rows.first.cells['icb']!.assignments.single.doctor.id,
        'ben',
      );
      expect(
        roles.rows.first.cells['amb']!.assignments.single.state,
        AssignmentState.provisional,
      );
      final physicians = const FactualReportProjection().project(
        snapshot,
        config,
        ReportRequest(RosterVersion('october', 1), ReportLayout.physicians),
      );
      expect(physicians.columns.map((c) => c.id), ['ben', 'ana']);
      expect(
        reportCellText(
          physicians.rows.first.cells['ben']!,
          ReportLayout.physicians,
        ),
        'ICB',
      );
      expect(
        physicians.rows[25].calendar.publicHolidayName,
        'Nationalfeiertag',
      );
      expect(
        () => const FactualReportProjection().project(
          snapshot,
          config,
          ReportRequest(RosterVersion('october', 0), ReportLayout.roles),
        ),
        throwsStateError,
      );
    },
  );
}
