import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/month_report_screen.dart';

void main() {
  for (final layout in MonthReportLayout.values) {
    testWidgets('$layout keeps dates fixed and rows aligned while scrolling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppLocalizations(language: AppLanguage.english, child: child!),
          home: MonthReportScreen(
            roster: DemoRoster.createJune2026(),
            doctors: DemoRoster.createDoctors(),
            layout: layout,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final date = find.text('1.6.');
      final before = tester.getTopLeft(date);
      final scroll = find.byKey(const ValueKey('report-assignment-scroll'));
      final contentTable = find.descendant(
        of: scroll,
        matching: find.byType(Table),
      );
      final assignmentBefore = tester.getTopLeft(contentTable);
      final start = Offset(tester.getRect(scroll).right - 20, before.dy + 10);
      await tester.dragFrom(start, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(date), before);
      expect(tester.getTopLeft(contentTable).dx, lessThan(assignmentBefore.dx));
      expect(tester.getTopLeft(contentTable).dy, assignmentBefore.dy);

      final tables = tester
          .renderObjectList<RenderBox>(find.byType(Table))
          .toList();
      expect(tables[0].size.height, closeTo(tables[1].size.height, 0.01));
      // Vertical movement scrolls both halves together.
      final oldDateY = tester.getTopLeft(find.text('15.6.')).dy;
      final oldTableY = tester.getTopLeft(contentTable).dy;
      await tester.dragFrom(const Offset(75, 650), const Offset(0, -250));
      await tester.pumpAndSettle();
      final dateDelta = tester.getTopLeft(find.text('15.6.')).dy - oldDateY;
      expect(dateDelta, lessThan(0));
      expect(
        tester.getTopLeft(contentTable).dy - oldTableY,
        closeTo(dateDelta, 0.01),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
