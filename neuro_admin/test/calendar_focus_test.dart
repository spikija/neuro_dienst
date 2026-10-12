import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_highlight_test.dart' show showDashboard, selected;
import 'assignment_preview_test.dart'
    show PreviewReader, selectDates, chooseRole, chooseDoctor;

CalendarDayGrid grid(WidgetTester tester) =>
    tester.widget<CalendarDayGrid>(find.byType(CalendarDayGrid));

class MonthsReader extends PreviewReader {
  MonthsReader() : super(previewFixture());
  @override
  Future<List<RosterChoice>> listMonths() async => [
    snapshot.month,
    const RosterChoice('nov', 2026, 11, RosterPhase.draft),
  ];
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) async {
    if (month.id == 'october') return snapshot;
    return RosterSnapshot(
      month,
      [],
      snapshot.doctors,
      {},
      [],
      {},
      roles: snapshot.roles,
    );
  }
}

void main() {
  testWidgets(
    'mouse establishes arrow focus; day and week navigation never select',
    (tester) async {
      await showDashboard(tester, PreviewReader(previewFixture()));
      await selectDates(tester, 10);
      final before = selected(tester);
      for (final (key, day) in [
        (LogicalKeyboardKey.arrowRight, 11),
        (LogicalKeyboardKey.arrowLeft, 10),
        (LogicalKeyboardKey.arrowUp, 3),
        (LogicalKeyboardKey.arrowDown, 10),
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(grid(tester).focusedDate, DateTime.utc(2026, 10, day));
        expect(selected(tester), before);
        expect(
          find.byKey(
            ValueKey(
              'calendar-focus-2026-10-${day.toString().padLeft(2, '0')}',
            ),
          ),
          findsOneWidget,
        );
      }
    },
  );
  testWidgets(
    'cross-month navigation retains selected dates and loads adjacent roster',
    (tester) async {
      await showDashboard(tester, MonthsReader());
      await selectDates(tester, 31);
      final before = selected(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(grid(tester).month, 11);
      expect(grid(tester).focusedDate, DateTime.utc(2026, 11, 1));
      expect(selected(tester), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(grid(tester).month, 10);
      expect(grid(tester).focusedDate, DateTime.utc(2026, 10, 31));
      expect(selected(tester), before);
    },
  );
  testWidgets(
    'missing adjacent roster shows empty calendar without generation or selection change',
    (tester) async {
      await showDashboard(tester, PreviewReader(previewFixture()));
      await selectDates(tester, 31);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(grid(tester).month, 11);
      expect(selected(tester), {DateTime.utc(2026, 10, 31)});
      expect(find.text('No roster generated for this month.'), findsOneWidget);
      expect(find.byKey(const ValueKey('daily-role-sul')), findsOneWidget);
    },
  );
  testWidgets(
    'role/physician selection survives arrows and cross-month validation does not preselect',
    (tester) async {
      await showDashboard(tester, MonthsReader());
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      final before = selected(tester);
      // A blocked day may receive navigation focus without entering bulk selection.
      await selectDates(tester, 31);
      expect(selected(tester), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(grid(tester).month, 11);
      expect(selected(tester), before);
      final panel = tester.widget<AssignmentCandidatePanel>(
        find.byType(AssignmentCandidatePanel),
      );
      expect(panel.role.id, leader.id);
      expect(panel.physicianId, 'ana');
      expect(panel.dates, isEmpty);
    },
  );
  testWidgets(
    'daily role order remains fixed and unscheduled rows are compact',
    (tester) async {
      await showDashboard(tester, PreviewReader(previewFixture()));
      await selectDates(tester, 2);
      final row = find.byKey(const ValueKey('daily-role-amb'));
      final scheduledHeight = tester.getSize(row).height;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(tester.getSize(row).height, lessThan(scheduledHeight));
      expect(tester.getSize(row).height, lessThanOrEqualTo(36));
      expect(
        tester.getTopLeft(row).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('daily-role-icb'))).dy,
        ),
      );
      expect(
        find.descendant(of: row, matching: find.text('Not scheduled')),
        findsOneWidget,
      );
      expect(grid(tester).focusedDate, DateTime.utc(2026, 10, 3));
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
    },
  );
  testWidgets('keyboard focus reveals the day in a short calendar viewport', (
    tester,
  ) async {
    await showDashboard(tester, PreviewReader(previewFixture()));
    tester.view.physicalSize = const Size(1440, 600);
    await tester.pumpAndSettle();
    await selectDates(tester, 1);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(grid(tester).focusedDate, DateTime.utc(2026, 10, 29));
    final day = tester.getRect(
      find.byKey(ValueKey(DateTime.utc(2026, 10, 29))),
    );
    final viewport = tester.getRect(
      find.byKey(const ValueKey('roster-calendar-scroll')),
    );
    expect(day.top, greaterThanOrEqualTo(viewport.top));
    expect(day.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(selected(tester), {DateTime.utc(2026, 10, 1)});
  });
}
