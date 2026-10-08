import 'dart:math' as math;

import 'package:neuro_admin_services/neuro_admin_services.dart'
    show HospitalDate;

/// Date-only identity: preserve calendar components, never convert timezones.
DateTime calendarDate(DateTime value) =>
    HospitalDate.fromCalendarComponents(value).asDateOnlyUtc;

/// Monday-first geometry, independent of widgets. Padding has no month date.
class CalendarGridMonth {
  final int year;
  final int month;
  CalendarGridMonth(this.year, this.month);
  int get offset => DateTime.utc(year, month).weekday - 1;
  int get dayCount => DateTime.utc(year, month + 1, 0).day;
  int get rows => (offset + dayCount + 6) ~/ 7;
  DateTime? dateAt(int row, int column) {
    if (row < 0 || row >= rows || column < 0 || column >= 7) return null;
    final day = row * 7 + column - offset + 1;
    return day >= 1 && day <= dayCount ? DateTime.utc(year, month, day) : null;
  }

  (int, int) cellOf(DateTime date) {
    if (date.year != year || date.month != month) {
      throw ArgumentError('Date outside displayed month');
    }
    final index = offset + date.day - 1;
    return (index ~/ 7, index % 7);
  }

  Set<DateTime> rectangle((int, int) anchor, (int, int) current) => {
    for (
      var row = math.min(anchor.$1, current.$1);
      row <= math.max(anchor.$1, current.$1);
      row++
    )
      for (
        var column = math.min(anchor.$2, current.$2);
        column <= math.max(anchor.$2, current.$2);
        column++
      )
        ?dateAt(row, column),
  };

  /// Holiday flags currently have no reliable provenance; weekdays only.
  Set<DateTime> get workingDays => {
    for (var day = 1; day <= dayCount; day++)
      if (DateTime.utc(year, month, day).weekday <= DateTime.friday)
        DateTime.utc(year, month, day),
  };
}

/// Local role-independent selection; the final state always contains dates.
class CalendarSelection {
  final Set<DateTime> _dates = {};
  CalendarGridMonth? _grid;
  (int, int)? _anchor;
  bool _dragging = false;
  DateTime? _lastVisited;

  Set<DateTime> get dates => Set.unmodifiable(_dates);
  bool get isDragging => _dragging;
  DateTime? get lastVisited => _lastVisited;

  void select(DateTime date) {
    replace([date]);
  }

  void replace(Iterable<DateTime> dates) {
    final normalized = dates.map(calendarDate).toSet();
    clear();
    _dates.addAll(normalized);
    _lastVisited = (_dates.toList()..sort()).firstOrNull;
  }

  void selectWorkingDays(int year, int month) =>
      replace(CalendarGridMonth(year, month).workingDays);

  void beginDrag(DateTime date) {
    select(date);
    _grid = CalendarGridMonth(date.year, date.month);
    _anchor = _grid!.cellOf(date);
    _dragging = true;
  }

  void enter(DateTime date) {
    if (!_dragging || date.year != _grid!.year || date.month != _grid!.month) {
      return;
    }
    final (row, column) = _grid!.cellOf(date);
    enterCell(row, column);
  }

  void enterCell(int row, int column) {
    if (!_dragging ||
        row < 0 ||
        row >= _grid!.rows ||
        column < 0 ||
        column >= 7) {
      return;
    }
    _dates
      ..clear()
      ..addAll(_grid!.rectangle(_anchor!, (row, column)));
    _lastVisited = _grid!.dateAt(row, column);
  }

  void endDrag() {
    _dragging = false;
    _anchor = null;
    _grid = null;
  }

  void clear() {
    _dates.clear();
    _lastVisited = null;
    endDrag();
  }
}
