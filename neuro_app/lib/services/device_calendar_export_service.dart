import 'package:device_calendar/device_calendar.dart';
import 'package:neuro_core/neuro_core.dart';

class DeviceCalendarExportResult {
  final String calendarName;
  final int createdCount;
  final int deletedCount;

  const DeviceCalendarExportResult({
    required this.calendarName,
    required this.createdCount,
    required this.deletedCount,
  });
}

class DeviceCalendarTarget {
  final String id;
  final String name;
  final String? accountName;
  final String? accountType;
  final bool isDefault;

  const DeviceCalendarTarget({
    required this.id,
    required this.name,
    this.accountName,
    this.accountType,
    this.isDefault = false,
  });

  String get displayName {
    final account = accountName == null || accountName!.isEmpty
        ? ''
        : ' · $accountName';
    return '$name$account';
  }

  bool get isNeuroDienst => name.toLowerCase() == 'neurodienst';

  @override
  bool operator ==(Object other) {
    return other is DeviceCalendarTarget && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

class DeviceCalendarExportService {
  static const calendarName = 'NeuroDienst';

  final DeviceCalendarPlugin _plugin;

  DeviceCalendarExportService({DeviceCalendarPlugin? plugin})
    : _plugin = plugin ?? DeviceCalendarPlugin();

  Future<DeviceCalendarExportResult> syncDoctorAssignments({
    required RosterMonth roster,
    required Doctor doctor,
    String? calendarId,
  }) async {
    final hasPermission = await _ensurePermission();

    if (!hasPermission) {
      throw const DeviceCalendarExportException(
        'Calendar permission was not granted.',
      );
    }

    var target = calendarId == null
        ? await defaultTargetCalendar()
        : await _targetCalendarById(calendarId);
    final monthStart = DateTime(roster.year, roster.month);
    final monthEnd = DateTime(roster.year, roster.month + 1, 1);

    if (target.isNeuroDienst) {
      target = await _freshNeuroDienstTarget(fallback: target);
      await _primeCalendarProvider(
        exceptCalendarId: target.id,
        start: monthStart,
        end: monthEnd,
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }

    final result = await _syncDoctorAssignmentsOnce(
      roster: roster,
      doctor: doctor,
      target: target,
      monthStart: monthStart,
      monthEnd: monthEnd,
    );

    if (!target.isNeuroDienst) {
      return result;
    }

    await Future<void>.delayed(const Duration(milliseconds: 650));
    final visibleCount = await _countExistingMonthEvents(
      calendarId: target.id,
      doctor: doctor,
      start: monthStart,
      end: monthEnd,
    );

    if (visibleCount >= result.createdCount) {
      return result;
    }

    await _primeCalendarProvider(
      exceptCalendarId: target.id,
      start: monthStart,
      end: monthEnd,
    );
    await Future<void>.delayed(const Duration(milliseconds: 650));

    return _syncDoctorAssignmentsOnce(
      roster: roster,
      doctor: doctor,
      target: target,
      monthStart: monthStart,
      monthEnd: monthEnd,
    );
  }

  Future<DeviceCalendarExportResult> _syncDoctorAssignmentsOnce({
    required RosterMonth roster,
    required Doctor doctor,
    required DeviceCalendarTarget target,
    required DateTime monthStart,
    required DateTime monthEnd,
  }) async {
    final deletedCount = await _deleteExistingMonthEvents(
      calendarId: target.id,
      doctor: doctor,
      start: monthStart,
      end: monthEnd,
    );
    var createdCount = 0;

    for (final assignment in _assignmentsForDoctor(
      roster: roster,
      doctor: doctor,
    )) {
      final result = await _plugin.createOrUpdateEvent(
        _eventForAssignment(
          calendarId: target.id,
          assignment: assignment,
          roster: roster,
        ),
      );

      if (result?.isSuccess == true) {
        createdCount++;
      } else {
        throw DeviceCalendarExportException(
          _errorMessage(result?.errors ?? const []),
        );
      }
    }

    return DeviceCalendarExportResult(
      calendarName: target.name,
      createdCount: createdCount,
      deletedCount: deletedCount,
    );
  }

  Future<void> _primeCalendarProvider({
    required String exceptCalendarId,
    required DateTime start,
    required DateTime end,
  }) async {
    final calendarsResult = await _plugin.retrieveCalendars();

    if (!calendarsResult.isSuccess) {
      return;
    }

    for (final calendar in calendarsResult.data ?? const <Calendar>[]) {
      final id = calendar.id;

      if (id == null ||
          id.isEmpty ||
          id == exceptCalendarId ||
          calendar.isReadOnly == true) {
        continue;
      }

      await _plugin.retrieveEvents(
        id,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      return;
    }
  }

  Future<List<DeviceCalendarTarget>> writableCalendars() async {
    final hasPermission = await _ensurePermission();

    if (!hasPermission) {
      throw const DeviceCalendarExportException(
        'Calendar permission was not granted.',
      );
    }

    final calendarsResult = await _plugin.retrieveCalendars();

    if (!calendarsResult.isSuccess) {
      throw DeviceCalendarExportException(
        _errorMessage(calendarsResult.errors),
      );
    }

    final targets = <DeviceCalendarTarget>[];

    for (final calendar in calendarsResult.data ?? const <Calendar>[]) {
      final id = calendar.id;

      if (id == null || id.isEmpty || calendar.isReadOnly == true) {
        continue;
      }

      targets.add(
        DeviceCalendarTarget(
          id: id,
          name: calendar.name ?? 'Calendar',
          accountName: calendar.accountName,
          accountType: calendar.accountType,
          isDefault: calendar.isDefault ?? false,
        ),
      );
    }

    if (!targets.any((target) => target.isNeuroDienst)) {
      final created = await _createNeuroDienstCalendar();
      if (created != null) {
        targets.add(created);
      }
    }

    final preferredNeuroDienst = _preferredNeuroDienstTarget(targets);
    if (preferredNeuroDienst != null) {
      targets
        ..removeWhere((target) => target.isNeuroDienst)
        ..insert(0, preferredNeuroDienst);
    }

    targets.sort((a, b) {
      if (a.isNeuroDienst != b.isNeuroDienst) {
        return a.isNeuroDienst ? -1 : 1;
      }

      if (a.isDefault != b.isDefault) {
        return a.isDefault ? -1 : 1;
      }

      final aIsGoogle = _isGoogleCalendar(a);
      final bIsGoogle = _isGoogleCalendar(b);

      if (aIsGoogle != bIsGoogle) {
        return aIsGoogle ? -1 : 1;
      }

      return a.displayName.compareTo(b.displayName);
    });

    return targets;
  }

  Future<DeviceCalendarTarget?> _createNeuroDienstCalendar() async {
    final createResult = await _plugin.createCalendar(calendarName);

    if (!createResult.isSuccess || createResult.data == null) {
      return null;
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    return _freshNeuroDienstTarget(
      fallback: DeviceCalendarTarget(
        id: createResult.data!,
        name: calendarName,
      ),
    );
  }

  Future<DeviceCalendarTarget> defaultTargetCalendar() async {
    final calendars = await writableCalendars();

    if (calendars.isEmpty) {
      throw const DeviceCalendarExportException(
        'No writable phone calendars found.',
      );
    }

    return calendars.first;
  }

  Future<bool> _ensurePermission() async {
    final existing = await _plugin.hasPermissions();

    if (existing.data == true) {
      return true;
    }

    final requested = await _plugin.requestPermissions();
    return requested.data == true;
  }

  Future<DeviceCalendarTarget> _targetCalendarById(String calendarId) async {
    final calendars = await writableCalendars();

    for (final calendar in calendars) {
      if (calendar.id == calendarId) {
        return calendar;
      }
    }

    throw const DeviceCalendarExportException(
      'Selected calendar is no longer available.',
    );
  }

  Future<DeviceCalendarTarget> _freshNeuroDienstTarget({
    required DeviceCalendarTarget fallback,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final calendarsResult = await _plugin.retrieveCalendars();

      if (calendarsResult.isSuccess) {
        final targets = <DeviceCalendarTarget>[];

        for (final calendar in calendarsResult.data ?? const <Calendar>[]) {
          final id = calendar.id;

          if (id == null || id.isEmpty || calendar.isReadOnly == true) {
            continue;
          }

          final target = DeviceCalendarTarget(
            id: id,
            name: calendar.name ?? 'Calendar',
            accountName: calendar.accountName,
            accountType: calendar.accountType,
            isDefault: calendar.isDefault ?? false,
          );

          if (target.isNeuroDienst) {
            targets.add(target);
          }
        }

        final preferred = _preferredNeuroDienstTarget(targets);
        if (preferred != null) {
          return preferred;
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 450));
    }

    return fallback;
  }

  DeviceCalendarTarget? _preferredNeuroDienstTarget(
    List<DeviceCalendarTarget> targets,
  ) {
    final neuroDienstTargets = targets
        .where((target) => target.isNeuroDienst)
        .toList();

    if (neuroDienstTargets.isEmpty) {
      return null;
    }

    neuroDienstTargets.sort((a, b) {
      final aId = int.tryParse(a.id);
      final bId = int.tryParse(b.id);

      if (aId != null && bId != null) {
        return bId.compareTo(aId);
      }

      return b.id.compareTo(a.id);
    });

    return neuroDienstTargets.first;
  }

  bool _isGoogleCalendar(DeviceCalendarTarget calendar) {
    final type = calendar.accountType?.toLowerCase() ?? '';
    return type.contains('google');
  }

  Future<int> _deleteExistingMonthEvents({
    required String calendarId,
    required Doctor doctor,
    required DateTime start,
    required DateTime end,
  }) async {
    final eventsResult = await _plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(startDate: start, endDate: end),
    );

    if (!eventsResult.isSuccess) {
      return 0;
    }

    var deletedCount = 0;

    for (final event in eventsResult.data ?? const <Event>[]) {
      final eventId = event.eventId;

      if (eventId == null || eventId.isEmpty) {
        continue;
      }

      if (!_isNeuroDienstEventForDoctor(event, doctor)) {
        continue;
      }

      final deleteResult = await _plugin.deleteEvent(calendarId, eventId);

      if (deleteResult.isSuccess) {
        deletedCount++;
      }
    }

    return deletedCount;
  }

  Future<int> _countExistingMonthEvents({
    required String calendarId,
    required Doctor doctor,
    required DateTime start,
    required DateTime end,
  }) async {
    final eventsResult = await _plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(startDate: start, endDate: end),
    );

    if (!eventsResult.isSuccess) {
      return 0;
    }

    var count = 0;

    for (final event in eventsResult.data ?? const <Event>[]) {
      if (_isNeuroDienstEventForDoctor(event, doctor)) {
        count++;
      }
    }

    return count;
  }

  Event _eventForAssignment({
    required String calendarId,
    required Assignment assignment,
    required RosterMonth roster,
  }) {
    final slot = assignment.slot;
    final template = slot.template;
    final start = _slotDateTime(slot.date, template.timeRange.start);
    final end = _slotDateTime(slot.date, template.timeRange.end);
    final description = _description(assignment: assignment, roster: roster);

    return Event(
      calendarId,
      title: 'NeuroDienst: ${template.name}',
      start: TZDateTime.from(start, local),
      end: TZDateTime.from(end, local),
      description: description,
      location: template.area,
      availability: Availability.Busy,
    );
  }

  bool _isNeuroDienstEventForDoctor(Event event, Doctor doctor) {
    final title = event.title ?? '';
    final description = event.description ?? '';

    return title.startsWith('NeuroDienst:') &&
        description.contains('Doctor ID: ${doctor.id}');
  }

  String _description({
    required Assignment assignment,
    required RosterMonth roster,
  }) {
    final template = assignment.slot.template;
    final state = assignment.state == AssignmentState.confirmed
        ? 'confirmed'
        : 'provisional';

    return [
      'Doctor: ${assignment.doctor.fullName}',
      'Doctor ID: ${assignment.doctor.id}',
      'Role: ${template.name}',
      if (template.area.isNotEmpty) 'Area: ${template.area}',
      'State: $state',
      'Roster: ${roster.month}/${roster.year}',
      'Generated by NeuroDienst',
    ].join('\n');
  }

  List<Assignment> _assignmentsForDoctor({
    required RosterMonth roster,
    required Doctor doctor,
  }) {
    final assignments = [
      for (final day in roster.days)
        ...day.assignments.where(
          (assignment) => assignment.doctor.id == doctor.id,
        ),
    ];

    assignments.sort((a, b) {
      final dateCompare = a.slot.date.compareTo(b.slot.date);
      if (dateCompare != 0) {
        return dateCompare;
      }

      return a.slot.template.timeRange.start.minutesSinceMidnight.compareTo(
        b.slot.template.timeRange.start.minutesSinceMidnight,
      );
    });

    return assignments;
  }

  DateTime _slotDateTime(DateTime date, LocalTime time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _errorMessage(List<ResultError> errors) {
    if (errors.isEmpty) {
      return 'Could not sync device calendar.';
    }

    return errors.map((error) => error.errorMessage).join('\n');
  }
}

class DeviceCalendarExportException implements Exception {
  final String message;

  const DeviceCalendarExportException(this.message);

  @override
  String toString() => message;
}
