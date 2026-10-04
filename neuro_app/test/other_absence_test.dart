import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/month_screen.dart';
import 'package:neuro_app/screens/month_report_screen.dart';
import 'package:neuro_app/widgets/month_day_card.dart';
import 'package:neuro_core/neuro_core.dart';

Finder day(int number) => find.byWidgetPredicate(
  (widget) => widget is MonthDayCard && widget.day.date.day == number,
);

Future<void> selectAction(WidgetTester tester, String label) async {
  final item = find.text(label);
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> pumpMonth(
  WidgetTester tester,
  Doctor doctor,
  ValueChanged<Doctor> onUpdated,
) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) =>
          AppLocalizations(language: AppLanguage.german, child: child!),
      home: MonthScreen(
        roster: DemoRoster.createJune2026(),
        currentDoctor: doctor,
        doctors: [doctor],
        language: AppLanguage.german,
        onDoctorChanged: (_) {},
        onDoctorUpdated: onUpdated,
      ),
    ),
  );
}

void main() {
  for (final type in otherAbsenceTypes) {
    test('$type blocks morning and afternoon, never the next day', () {
      final doctor = DemoRoster.createCurrentDoctor().copyWith(
        availabilities: [
          AvailabilityPeriod(
            start: DateTime(2026, 6, 30),
            end: DateTime(2026, 6, 30),
            type: type,
          ),
        ],
      );
      final template = SlotTemplate(
        id: 'test',
        name: 'Test',
        area: 'Test',
        kind: SlotKind.science,
        timeRange: TimeRange(start: LocalTime(8, 0), end: LocalTime(16, 0)),
        role: DutyRole.backup,
        allowedRanks: {doctor.rank},
      );
      for (final date in [DateTime(2026, 6, 30), DateTime(2026, 7, 1)]) {
        final slot = DailySlot(id: 'slot', date: date, template: template);
        final decision = AssignmentService().canAssignDoctorToSlot(
          doctor: doctor,
          slot: slot,
          day: RosterDay(
            calendarInfo: CalendarDayInfo(
              date: date,
              isWeekend: false,
              isPublicHoliday: false,
            ),
            slots: [slot],
          ),
        );
        expect(decision.accepted, date.month == 7);
      }
    });
  }

  testWidgets(
    'picker blocks only nonconsecutive selected days and clears their assignments',
    (tester) async {
      final doctor = DemoRoster.createOtherDoctor().copyWith(
        availabilities: [],
      );
      Doctor? updated;
      await pumpMonth(tester, doctor, (value) => updated = value);
      await tester.tap(day(1));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 90));
      await tester.pumpAndSettle();
      await tester.tap(day(3));
      await tester.pumpAndSettle();
      await selectAction(tester, 'Andere Abwesenheit…');
      for (final label in [
        'Spätdienst im ZAM',
        'ZAM tagsüber',
        'Andere Ambulanz',
        'Kongress',
        'Andere',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await selectAction(tester, 'Spätdienst im ZAM');
      expect(updated!.availabilities.map((period) => period.start.day), [1, 3]);
      expect(updated!.isAbsentOn(DateTime(2026, 6, 2)), isFalse);
      expect(updated!.isAbsentOn(DateTime(2026, 6, 4)), isFalse);
      expect(tester.widget<MonthDayCard>(day(1)).day.assignments, isEmpty);
      expect(
        updated!.availabilities.every(
          (period) => period.type == AvailabilityType.zamLateShift,
        ),
        isTrue,
      );
    },
  );

  testWidgets('range skips holidays and weekends; cancellation has no effect', (
    tester,
  ) async {
    final doctor = DemoRoster.createCurrentDoctor().copyWith(
      availabilities: [],
    );
    Doctor? updated;
    await pumpMonth(tester, doctor, (value) => updated = value);
    final gesture = await tester.startGesture(tester.getCenter(day(3)));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveTo(tester.getCenter(day(8)));
    await gesture.up();
    await tester.pumpAndSettle();
    await selectAction(tester, 'Andere Abwesenheit…');
    await selectAction(tester, 'Abbrechen');
    expect(updated, isNull);
    await tester.tap(find.byTooltip('Aktionen'));
    await tester.pumpAndSettle();
    await selectAction(tester, 'Andere Abwesenheit…');
    await selectAction(tester, 'Andere');
    expect(updated!.availabilities.map((period) => period.start.day), [
      3,
      5,
      8,
    ]);
  });

  testWidgets('removal splits additional absences and preserves common types', (
    tester,
  ) async {
    final doctor = DemoRoster.createCurrentDoctor().copyWith(
      availabilities: [
        for (final type in [
          ...otherAbsenceTypes,
          AvailabilityType.vacation,
          AvailabilityType.duty24,
          AvailabilityType.postDuty,
          AvailabilityType.efDay,
        ])
          AvailabilityPeriod(
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 3),
            type: type,
          ),
      ],
    );
    Doctor? updated;
    await pumpMonth(tester, doctor, (value) => updated = value);
    await tester.tap(day(2));
    await tester.pumpAndSettle();
    await selectAction(tester, 'Andere Abwesenheit entfernen');
    expect(find.text('Andere Abwesenheit von 1 Tag entfernt'), findsOneWidget);
    for (final type in otherAbsenceTypes) {
      expect(updated!.availabilityOn(DateTime(2026, 6, 1), type), isNotNull);
      expect(updated!.availabilityOn(DateTime(2026, 6, 2), type), isNull);
      expect(updated!.availabilityOn(DateTime(2026, 6, 3), type), isNotNull);
    }
    for (final type in [
      AvailabilityType.vacation,
      AvailabilityType.duty24,
      AvailabilityType.postDuty,
      AvailabilityType.efDay,
    ]) {
      expect(updated!.availabilityOn(DateTime(2026, 6, 2), type), isNotNull);
    }
  });

  testWidgets(
    'physician report shows the selected reason instead of vacation',
    (tester) async {
      final doctor = DemoRoster.createCurrentDoctor().copyWith(
        availabilities: [
          AvailabilityPeriod(
            start: DateTime(2026, 6, 1),
            end: DateTime(2026, 6, 1),
            type: AvailabilityType.zamLateShift,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppLocalizations(language: AppLanguage.german, child: child!),
          home: MonthReportScreen(
            roster: DemoRoster.createJune2026(),
            doctors: [doctor],
            layout: MonthReportLayout.physicians,
          ),
        ),
      );
      expect(find.text('Spätdienst im ZAM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
