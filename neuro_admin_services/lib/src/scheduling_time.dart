import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// A hospital calendar date, not an instant in the workstation's timezone.
final class HospitalDate implements Comparable<HospitalDate> {
  final int year;
  final int month;
  final int day;

  factory HospitalDate(int year, int month, int day) {
    final normalized = DateTime.utc(year, month, day);
    if (year < 1 ||
        year > 9999 ||
        normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError('Invalid hospital calendar date');
    }
    return HospitalDate._(year, month, day);
  }
  const HospitalDate._(this.year, this.month, this.day);

  /// Only for date-valued inputs (e.g. calendar selection), never UTC instants.
  factory HospitalDate.fromCalendarComponents(DateTime date) =>
      HospitalDate(date.year, date.month, date.day);

  factory HospitalDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('Expected a hospital DATE (yyyy-MM-dd)', value);
    }
    final parts = value.split('-').map(int.parse).toList();
    try {
      return HospitalDate(parts[0], parts[1], parts[2]);
    } on ArgumentError {
      throw FormatException('Invalid hospital calendar date', value);
    }
  }

  /// Compatibility representation for existing neuro_core date-only models.
  DateTime get asDateOnlyUtc => DateTime.utc(year, month, day);
  HospitalDate addDays(int days) => HospitalDate.fromCalendarComponents(
    asDateOnlyUtc.add(Duration(days: days)),
  );
  @override
  int compareTo(HospitalDate other) =>
      asDateOnlyUtc.compareTo(other.asDateOnlyUtc);
  @override
  bool operator ==(Object other) =>
      other is HospitalDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;
  @override
  int get hashCode => Object.hash(year, month, day);
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

enum AmbiguousWallTime { earlier, later }

/// One scheduling zone for every client, independent of tz.local/device settings.
abstract final class ViennaSchedulingTime {
  static const zoneName = 'Europe/Vienna';
  static final tz.Location _location = _initialize();

  static tz.Location _initialize() {
    tzdata.initializeTimeZones();
    return tz.getLocation(zoneName);
  }

  /// Conservatively stop at the final explicit transition. The cached library
  /// otherwise extrapolates its last offset forever, losing future DST.
  static DateTime get verifiedUntilUtc => DateTime.fromMillisecondsSinceEpoch(
    _location.transitionAt.last,
    isUtc: true,
  );

  static void _requireCovered(DateTime instant) {
    if (!instant.toUtc().isBefore(verifiedUntilUtc)) {
      throw FormatException(
        'Europe/Vienna timezone data is verified only before '
        '${verifiedUntilUtc.toIso8601String()}. Update timezone data for later duties.',
      );
    }
  }

  static tz.TZDateTime localTime(DateTime instant) {
    _requireCovered(instant);
    return tz.TZDateTime.from(instant, _location);
  }

  static HospitalDate dateOfInstant(DateTime instant) =>
      HospitalDate.fromCalendarComponents(localTime(instant));

  /// A database timestamptz must include its offset. Naive timestamps must not
  /// silently inherit the Windows/macOS timezone.
  static DateTime parseInstant(String value) {
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const FormatException('Duty timestamp must include a UTC offset.');
    }
    final instant = DateTime.parse(value).toUtc();
    _requireCovered(instant);
    return instant;
  }

  /// Strict future template conversion. Gaps are rejected; repeated autumn
  /// times require an explicit earlier/later choice. No silent DST adjustment.
  static DateTime resolveWallTime(
    HospitalDate date,
    int hour,
    int minute, {
    int second = 0,
    AmbiguousWallTime? ambiguity,
  }) {
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      throw ArgumentError('Invalid hospital wall-clock time');
    }
    final wall = DateTime.utc(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
      second,
    );
    final candidates = <DateTime>{};
    for (final offset in _location.zones.map((zone) => zone.offset).toSet()) {
      final candidate = wall.subtract(Duration(milliseconds: offset));
      final local = tz.TZDateTime.from(candidate, _location);
      if (local.year == date.year &&
          local.month == date.month &&
          local.day == date.day &&
          local.hour == hour &&
          local.minute == minute &&
          local.second == second) {
        _requireCovered(candidate);
        candidates.add(candidate);
      }
    }
    final ordered = candidates.toList()..sort();
    if (ordered.isEmpty) {
      throw const FormatException(
        'Nonexistent Europe/Vienna wall time (DST gap).',
      );
    }
    if (ordered.length > 1 && ambiguity == null) {
      throw const FormatException(
        'Ambiguous Europe/Vienna wall time: choose earlier or later.',
      );
    }
    return ambiguity == AmbiguousWallTime.later ? ordered.last : ordered.first;
  }
}
