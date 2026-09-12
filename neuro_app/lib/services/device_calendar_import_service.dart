import 'package:device_calendar/device_calendar.dart';

class CalendarImportSource {
  final String id;
  final String name;
  final String? accountName;
  final String? accountType;

  const CalendarImportSource({
    required this.id,
    required this.name,
    this.accountName,
    this.accountType,
  });

  String get displayName => [
    name,
    if (accountName != null && accountName!.isNotEmpty) accountName!,
    if (accountType?.toLowerCase().contains('google') == true) 'Google',
    if (accountType?.toLowerCase().contains('outlook') == true ||
        accountType?.toLowerCase().contains('exchange') == true)
      'Microsoft',
    if (accountType?.toUpperCase() == 'LOCAL') 'Local',
  ].join(' · ');
}

class CalendarVacationScan {
  final List<CalendarImportSource> sources;
  final List<CalendarVacationCandidate> candidates;

  const CalendarVacationScan({required this.sources, required this.candidates});
}

class CalendarVacationCandidate {
  final String? calendarId;
  final String calendarName;
  final String? accountName;
  final String? accountType;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  CalendarVacationCandidate({
    this.calendarId,
    required this.calendarName,
    this.accountName,
    this.accountType,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
  });

  String get sourceLabel => CalendarImportSource(
    id: calendarId ?? '',
    name: calendarName,
    accountName: accountName,
    accountType: accountType,
  ).displayName;

  List<DateTime> datesWithin(DateTime rangeStart, DateTime rangeEnd) {
    final dates = <DateTime>[];
    final first = _dateOnly(start).isBefore(rangeStart)
        ? rangeStart
        : _dateOnly(start);
    final last = _dateOnly(end).isAfter(rangeEnd) ? rangeEnd : _dateOnly(end);

    for (
      var date = first;
      !date.isAfter(last);
      date = date.add(const Duration(days: 1))
    ) {
      dates.add(date);
    }

    return dates;
  }
}

class DeviceCalendarImportService {
  final DeviceCalendarPlugin _plugin;

  DeviceCalendarImportService({DeviceCalendarPlugin? plugin})
    : _plugin = plugin ?? DeviceCalendarPlugin();

  Future<List<CalendarVacationCandidate>> loadVacationCandidates({
    required DateTime start,
    required DateTime end,
  }) async => (await loadVacationScan(start: start, end: end)).candidates;

  Future<CalendarVacationScan> loadVacationScan({
    required DateTime start,
    required DateTime end,
  }) async {
    final hasPermission = await _ensurePermission();

    if (!hasPermission) {
      throw const CalendarImportException(
        'Calendar permission was not granted.',
      );
    }

    final calendarsResult = await _plugin.retrieveCalendars();

    if (!calendarsResult.isSuccess) {
      throw CalendarImportException(_errorMessage(calendarsResult.errors));
    }

    final calendars = calendarsResult.data ?? const [];
    final candidates = <CalendarVacationCandidate>[];
    final sources = <CalendarImportSource>[];

    for (final calendar in calendars) {
      final calendarId = calendar.id;

      if (calendarId == null || calendarId.isEmpty) {
        continue;
      }

      sources.add(
        CalendarImportSource(
          id: calendarId,
          name: calendar.name ?? 'Calendar',
          accountName: calendar.accountName,
          accountType: calendar.accountType,
        ),
      );

      final eventsResult = await _plugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: start, endDate: end),
      );

      if (!eventsResult.isSuccess) {
        continue;
      }

      for (final event in eventsResult.data ?? const <Event>[]) {
        final title = event.title?.trim();
        final eventStart = event.start;
        final eventEnd = event.end;

        if (title == null ||
            title.isEmpty ||
            eventStart == null ||
            eventEnd == null ||
            !_looksLikeVacation(title)) {
          continue;
        }

        candidates.add(
          CalendarVacationCandidate(
            calendarId: calendarId,
            calendarName: calendar.name ?? 'Calendar',
            accountName: calendar.accountName,
            accountType: calendar.accountType,
            title: title,
            start: _dateOnly(eventStart),
            end: _dateOnly(eventEnd),
            allDay: event.allDay ?? false,
          ),
        );
      }
    }

    candidates.sort((a, b) => a.start.compareTo(b.start));
    sources.sort((a, b) => a.displayName.compareTo(b.displayName));
    return CalendarVacationScan(sources: sources, candidates: candidates);
  }

  Future<bool> _ensurePermission() async {
    final existing = await _plugin.hasPermissions();

    if (existing.data == true) {
      return true;
    }

    final requested = await _plugin.requestPermissions();
    return requested.data == true;
  }

  bool _looksLikeVacation(String title) {
    final normalized = title.toLowerCase();
    const keywords = [
      'vacation',
      'holiday',
      'leave',
      'pto',
      'annual leave',
      'urlaub',
      'ferien',
      'frei',
    ];

    return keywords.any(normalized.contains);
  }

  String _errorMessage(List<ResultError> errors) {
    if (errors.isEmpty) {
      return 'Could not read device calendars.';
    }

    return errors.map((error) => error.errorMessage).join('\n');
  }
}

class CalendarImportException implements Exception {
  final String message;

  const CalendarImportException(this.message);

  @override
  String toString() => message;
}

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}
