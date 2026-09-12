import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/day_screen.dart';
import 'package:neuro_app/screens/month_screen.dart';
import 'package:neuro_app/widgets/month_day_card.dart';
import 'package:neuro_core/neuro_core.dart';

Finder day(int number) => find.byWidgetPredicate(
  (widget) => widget is MonthDayCard && widget.day.date.day == number,
);

Future<void> pumpMonth(
  WidgetTester tester, {
  Future<RosterMonth?> Function(DateTime)? loadMonth,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) =>
          AppLocalizations(language: AppLanguage.english, child: child!),
      home: MonthScreen(
        roster: DemoRoster.createJune2026(),
        currentDoctor: DemoRoster.createCurrentDoctor(),
        doctors: DemoRoster.createDoctors(),
        onDoctorChanged: (_) {},
        onDoctorUpdated: (_) {},
        loadMonth: loadMonth,
      ),
    ),
  );
}

void main() {
  testWidgets('short tap selects the day and opens actions without roles', (
    tester,
  ) async {
    await pumpMonth(tester);
    await tester.tap(day(1));
    await tester.pumpAndSettle();
    expect(tester.widget<MonthDayCard>(day(1)).isSelected, isTrue);
    expect(find.text('Vacation').hitTestable(), findsOneWidget);
    expect(find.byType(DayScreen), findsNothing);

    // Dismiss the menu to add a non-adjacent day to the selection.
    await tester.tapAt(const Offset(10, 90));
    await tester.pumpAndSettle();
    await tester.tap(day(3));
    await tester.pumpAndSettle();
    expect(tester.widget<MonthDayCard>(day(1)).isSelected, isTrue);
    expect(tester.widget<MonthDayCard>(day(3)).isSelected, isTrue);
    expect(find.text('Vacation').hitTestable(), findsOneWidget);
  });

  for (final number in [1, 4, 6, 7]) {
    testWidgets(
      'hold and release opens full day $number including holidays/weekends',
      (tester) async {
        await pumpMonth(tester);
        await tester.longPress(day(number));
        await tester.pumpAndSettle();
        expect(find.byType(DayScreen), findsOneWidget);
        expect(find.text('$number.6.2026'), findsOneWidget);
        expect(find.byTooltip('Actions'), findsNothing);
      },
    );
  }

  testWidgets('hold and drag selects a range and opens actions on release', (
    tester,
  ) async {
    await pumpMonth(tester);
    final gesture = await tester.startGesture(tester.getCenter(day(2)));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveTo(tester.getCenter(day(9)));
    await tester.pump();
    expect(find.text('Vacation').hitTestable(), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<MonthDayCard>(find.byType(MonthDayCard))
        .where((card) => card.isSelected)
        .map((card) => card.day.date.day);
    expect(selected, [2, 3, 4, 5, 6, 7, 8, 9]);
    expect(find.text('Vacation').hitTestable(), findsOneWidget);
    expect(find.byType(DayScreen), findsNothing);
    expect(find.text('6/2026'), findsOneWidget);
  });

  testWidgets('horizontal swipes change months and never select days', (
    tester,
  ) async {
    await pumpMonth(tester);
    await tester.drag(day(3), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('7/2026'), findsOneWidget);
    await tester.drag(day(8), const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(find.text('6/2026'), findsOneWidget);
    expect(find.byType(DayScreen), findsNothing);
    expect(find.byTooltip('Actions'), findsNothing);
  });

  testWidgets(
    'slow swipe cancels holding even after crossing the hold duration',
    (tester) async {
      await pumpMonth(tester);
      final origin = tester.getCenter(day(3));
      final gesture = await tester.startGesture(origin);
      await gesture.moveTo(origin - const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveTo(origin - const Offset(180, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('7/2026'), findsOneWidget);
      expect(find.byTooltip('Actions'), findsNothing);
    },
  );

  testWidgets(
    'unavailable months keep the current month and show feedback in both directions',
    (tester) async {
      final requested = <DateTime>[];
      await pumpMonth(
        tester,
        loadMonth: (month) async {
          requested.add(month);
          return null;
        },
      );
      await tester.drag(day(3), const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(find.text('6/2026'), findsOneWidget);
      expect(
        find.text('No generated roster for 7/2026').hitTestable(),
        findsOneWidget,
      );
      await tester.drag(day(3), const Offset(180, 0));
      await tester.pumpAndSettle();
      expect(
        find.text('No generated roster for 5/2026').hitTestable(),
        findsOneWidget,
      );
      expect(requested, [DateTime(2026, 7), DateTime(2026, 5)]);
      expect(find.byTooltip('Actions'), findsNothing);
    },
  );

  testWidgets('cancelling a hold does not select or open a day', (
    tester,
  ) async {
    await pumpMonth(tester);
    final gesture = await tester.startGesture(tester.getCenter(day(1)));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byType(DayScreen), findsNothing);
    expect(find.byTooltip('Actions'), findsNothing);
  });
}
