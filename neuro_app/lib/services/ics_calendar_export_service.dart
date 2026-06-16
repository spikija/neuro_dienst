import 'package:neuro_core/neuro_core.dart';

class IcsCalendarExportService {
  String buildDoctorAssignmentsCalendar({
    required RosterMonth roster,
    required Doctor doctor,
    DateTime? generatedAt,
  }) {
    final generated = (generatedAt ?? DateTime.now()).toUtc();
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//NeuroDienst//Duty Roster//EN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escapeText('NeuroDienst ${doctor.fullName}')}',
      'X-WR-CALDESC:${_escapeText('Assigned NeuroDienst duties')}',
    ];

    final assignments = _assignmentsForDoctor(roster: roster, doctor: doctor);

    for (final assignment in assignments) {
      lines.addAll(_eventLines(assignment, roster, generated));
    }

    lines.add('END:VCALENDAR');

    return lines.map(_foldLine).join('\r\n');
  }

  int countAssignments({required RosterMonth roster, required Doctor doctor}) {
    return _assignmentsForDoctor(roster: roster, doctor: doctor).length;
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

  List<String> _eventLines(
    Assignment assignment,
    RosterMonth roster,
    DateTime generated,
  ) {
    final slot = assignment.slot;
    final template = slot.template;
    final start = _slotDateTime(slot.date, template.timeRange.start);
    final end = _slotDateTime(slot.date, template.timeRange.end);
    final state = assignment.state == AssignmentState.confirmed
        ? 'confirmed'
        : 'provisional';
    final description = [
      'Doctor: ${assignment.doctor.fullName}',
      'Role: ${template.name}',
      if (template.area.isNotEmpty) 'Area: ${template.area}',
      'State: $state',
      'Roster: ${roster.month}/${roster.year}',
    ].join('\n');

    return [
      'BEGIN:VEVENT',
      'UID:${_escapeText('neurodienst-${slot.id}-${assignment.doctor.id}@neurodienst')}',
      'DTSTAMP:${_formatUtc(generated)}',
      'DTSTART:${_formatLocal(start)}',
      'DTEND:${_formatLocal(end)}',
      'SUMMARY:${_escapeText('NeuroDienst: ${template.name}')}',
      if (template.area.isNotEmpty) 'LOCATION:${_escapeText(template.area)}',
      'DESCRIPTION:${_escapeText(description)}',
      'STATUS:CONFIRMED',
      'TRANSP:OPAQUE',
      'END:VEVENT',
    ];
  }

  DateTime _slotDateTime(DateTime date, LocalTime time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatUtc(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return '${_two(utc.year, 4)}${_two(utc.month)}${_two(utc.day)}T'
        '${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';
  }

  String _formatLocal(DateTime dateTime) {
    return '${_two(dateTime.year, 4)}${_two(dateTime.month)}${_two(dateTime.day)}T'
        '${_two(dateTime.hour)}${_two(dateTime.minute)}${_two(dateTime.second)}';
  }

  String _two(int value, [int width = 2]) {
    return value.toString().padLeft(width, '0');
  }

  String _escapeText(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,');
  }

  String _foldLine(String line) {
    const maxLength = 73;

    if (line.length <= maxLength) {
      return line;
    }

    final buffer = StringBuffer();
    var index = 0;

    while (index < line.length) {
      final end = (index + maxLength).clamp(0, line.length);
      if (index == 0) {
        buffer.write(line.substring(index, end));
      } else {
        buffer.write('\r\n ');
        buffer.write(line.substring(index, end));
      }
      index = end;
    }

    return buffer.toString();
  }
}
