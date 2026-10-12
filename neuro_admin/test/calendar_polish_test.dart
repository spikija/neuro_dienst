import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_highlight_test.dart' show showDashboard, selected;
import 'assignment_preview_test.dart' show PreviewReader, selectDates;
import 'workspace_transition_test.dart' show TransitionReader;

CalendarDayGrid calendar(WidgetTester tester) =>
    tester.widget<CalendarDayGrid>(find.byType(CalendarDayGrid));

class TodayReader implements RosterReader {
  final now = ViennaSchedulingTime.localTime(DateTime.now().toUtc());
  @override
  Future<List<RosterChoice>> listMonths() async => [
    RosterChoice('today', now.year, now.month, RosterPhase.draft),
  ];
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) async =>
      RosterSnapshot(month, [], [], {}, [], {});
}

void main() {
  testWidgets(
    'previous/next month clamp focus, preserve direct picker and local refresh',
    (tester) async {
      await showDashboard(tester, PreviewReader(previewFixture()));
      await selectDates(tester, 31);
      await tester.tap(find.byKey(const ValueKey('previous-month')));
      await tester.pumpAndSettle();
      expect(calendar(tester).month, 9);
      expect(calendar(tester).focusedDate, DateTime.utc(2026, 9, 30));
      expect(selected(tester), isEmpty);
      await tester.tap(find.byKey(const ValueKey('next-month')));
      await tester.pumpAndSettle();
      expect(calendar(tester).focusedDate, DateTime.utc(2026, 10, 30));
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(calendar(tester).focusedDate, DateTime.utc(2026, 10, 30));
      await tester.tap(find.byKey(const ValueKey('month-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09').last);
      await tester.pumpAndSettle();
      expect(calendar(tester).month, 9);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'month button leaves old grid mounted while loading and on failure',
    (tester) async {
      final reader = TransitionReader();
      await showDashboard(tester, reader);
      final element = tester.element(find.byType(CalendarDayGrid));
      reader.pending = Completer();
      await tester.tap(find.byKey(const ValueKey('next-month')));
      await tester.pump();
      expect(tester.element(find.byType(CalendarDayGrid)), same(element));
      expect(calendar(tester).month, 10);
      reader.pending!.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(CalendarDayGrid)), same(element));
      expect(find.textContaining('Could not load roster data'), findsOneWidget);
    },
  );

  for (final size in [
    const Size(1280, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('continuous grid and clear day/week headers at $size', (
      tester,
    ) async {
      await showDashboard(tester, PreviewReader(previewFixture()));
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final grid = tester.widget<Container>(
        find.byKey(const ValueKey('continuous-calendar-grid')),
      );
      expect((grid.foregroundDecoration as BoxDecoration).border, isNotNull);
      final first = tester.getRect(
        find.byKey(ValueKey(DateTime.utc(2026, 10, 1))),
      );
      final second = tester.getRect(
        find.byKey(ValueKey(DateTime.utc(2026, 10, 2))),
      );
      expect(first.right, closeTo(second.left, .01));
      final nextWeek = tester.getRect(
        find.byKey(ValueKey(DateTime.utc(2026, 10, 8))),
      );
      expect(first.bottom, closeTo(nextWeek.top, .01));
      final number = tester.widget<AdminText>(
        find.byKey(const ValueKey('calendar-day-number-2026-10-01')),
      );
      expect(number.style!.fontSize, 17);
      expect(number.style!.fontWeight, FontWeight.w600);
      expect(
        tester
            .widget<AdminText>(find.byKey(const ValueKey('weekday-Mon')))
            .style!
            .fontWeight,
        FontWeight.w600,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('previous-month'))).height,
        greaterThanOrEqualTo(48),
      );
      await selectDates(tester, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(calendar(tester).focusedDate, DateTime.utc(2026, 10, 3));
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('today marker is independent of focus and selection', (
    tester,
  ) async {
    final reader = TodayReader();
    await showDashboard(tester, reader);
    final key = HospitalDate(reader.now.year, reader.now.month, reader.now.day);
    expect(find.byKey(ValueKey('calendar-today-$key')), findsOneWidget);
    expect(selected(tester), isEmpty);
    expect(
      calendar(tester).focusedDate,
      DateTime.utc(reader.now.year, reader.now.month),
    );
  });
}
