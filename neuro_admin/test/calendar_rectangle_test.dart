import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_selection.dart';

void main() {
  DateTime june(int day) => DateTime.utc(2026, 6, day); // Starts Monday.
  Set<DateTime> dates(List<int> days) => days.map(june).toSet();
  for (final (start, end, expected) in [
    (1, 5, [1, 2, 3, 4, 5]),
    (1, 12, [1, 2, 3, 4, 5, 8, 9, 10, 11, 12]),
    (12, 1, [1, 2, 3, 4, 5, 8, 9, 10, 11, 12]),
    (2, 18, [2, 3, 4, 9, 10, 11, 16, 17, 18]),
    (3, 17, [3, 10, 17]),
  ]) {
    test(
      'rectangle $start to $end uses endpoints, regardless of intermediate path',
      () {
        final selection = CalendarSelection()..beginDrag(june(start));
        selection.enter(june(28));
        selection.enter(june(end));
        expect(selection.dates, dates(expected));
        selection.endDrag();
        selection.enter(june(29));
        expect(selection.dates, dates(expected));
        expect(selection.isDragging, isFalse);
        selection.beginDrag(june(7));
        expect(selection.dates, {june(7)});
      },
    );
  }
  test(
    'padding endpoints exclude other months and selection never changes month',
    () {
      final grid = CalendarGridMonth(2026, 10);
      expect(grid.dateAt(0, 0), isNull);
      expect(grid.dateAt(4, 6), isNull);
      expect(grid.cellOf(DateTime.utc(2026, 10, 1)), (0, 3));
      final selection = CalendarSelection()
        ..beginDrag(DateTime.utc(2026, 10, 9));
      selection.enterCell(0, 0);
      expect(selection.dates.map((d) => d.day).toSet(), {1, 2, 5, 6, 7, 8, 9});
      selection.enterCell(4, 6);
      expect(selection.dates.map((d) => d.day).toSet(), {
        9,
        10,
        11,
        16,
        17,
        18,
        23,
        24,
        25,
        30,
        31,
      });
      selection.enter(DateTime.utc(2026, 11, 1));
      expect(selection.dates.every((d) => d.month == 10), isTrue);
    },
  );
  test(
    'working days use dates even without roster records; Austrian holidays are excluded',
    () {
      final selection = CalendarSelection()..selectWorkingDays(2026, 10);
      expect(selection.dates, {
        for (final day in [
          1,
          2,
          5,
          6,
          7,
          8,
          9,
          12,
          13,
          14,
          15,
          16,
          19,
          20,
          21,
          22,
          23,
          27,
          28,
          29,
          30,
        ])
          DateTime.utc(2026, 10, day),
      });
      expect(
        selection.dates.every((d) => d.isUtc && d.hour == 0 && d.weekday <= 5),
        isTrue,
      );
      expect(
        selection.dates,
        isNot(contains(DateTime.utc(2026, 10, 26))),
        reason: 'Austrian holiday is excluded even without persisted metadata',
      );
      selection.clear();
      expect(selection.dates, isEmpty);
      expect(selection.isDragging, isFalse);
    },
  );
}
