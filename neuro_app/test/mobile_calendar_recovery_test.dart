import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/month_screen.dart';
import 'package:neuro_app/widgets/month_day_card.dart';
import 'package:neuro_core/neuro_core.dart';

// The database repair supplies real calendar days without recreating test duties.
RosterMonth calendarOnlyMonth(int month) => RosterMonth(
  year: 2026,
  month: month,
  phase: RosterPhase.draft,
  days: [
    for (var d = 1; d <= DateTime(2026, month + 1, 0).day; d++)
      RosterDay(
        calendarInfo: CalendarDayInfo(
          date: DateTime(2026, month, d),
          isWeekend: DateTime(2026, month, d).weekday >= DateTime.saturday,
          isPublicHoliday: false,
        ),
        slots: [],
        assignments: [],
      ),
  ],
);

void main() {
  testWidgets(
    'existing mobile calendar navigates June through October to November without duty slots',
    (tester) async {
      final requested = <DateTime>[];
      final visible = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppLocalizations(language: AppLanguage.english, child: child!),
          home: MonthScreen(
            roster: calendarOnlyMonth(6),
            currentDoctor: DemoRoster.createCurrentDoctor(),
            doctors: DemoRoster.createDoctors(),
            onDoctorChanged: (_) {},
            onDoctorUpdated: (_) {},
            onVisibleMonthChanged: visible.add,
            loadMonth: (date) async {
              requested.add(date);
              return calendarOnlyMonth(date.month);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var month = 6; month <= 11; month++) {
        expect(find.text('$month/2026'), findsOneWidget);
        final cards = tester.widgetList<MonthDayCard>(
          find.byType(MonthDayCard),
        );
        expect(cards.length, DateTime(2026, month + 1, 0).day);
        expect(
          cards.every((c) => c.day.slots.isEmpty && c.day.assignments.isEmpty),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        if (month < 11) {
          await tester.tap(find.byIcon(Icons.chevron_right));
          await tester.pumpAndSettle();
        }
      }
      expect(requested, [for (var m = 7; m <= 11; m++) DateTime(2026, m)]);
      expect(visible, requested);
    },
  );
}
