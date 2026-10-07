import 'package:neuro_admin_services/neuro_admin_services.dart'
    show HospitalDate;

/// Date-only identity: preserve calendar components, never convert timezones.
DateTime calendarDate(DateTime value) =>
    HospitalDate.fromCalendarComponents(value).asDateOnlyUtc;

/// Local, role-independent state for a future bulk-assignment workflow.
/// Pointer geometry belongs to the calendar widget, not this model.
class CalendarSelection {
  final Set<DateTime> _dates = {};
  bool _dragging = false;
  DateTime? _lastVisited;

  Set<DateTime> get dates => Set.unmodifiable(_dates);
  bool get isDragging => _dragging;
  DateTime? get lastVisited => _lastVisited;

  void select(DateTime date) {
    clear();
    _add(date);
  }

  void beginDrag(DateTime date) {
    select(date);
    _dragging = true;
  }

  void enter(DateTime date) {
    if (_dragging) _add(date);
  }

  void endDrag() => _dragging = false;

  void clear() {
    _dates.clear();
    _lastVisited = null;
    _dragging = false;
  }

  void _add(DateTime date) {
    _lastVisited = calendarDate(date);
    _dates.add(_lastVisited!);
  }
}
