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

  /// End of explicit bundled history. Later years use the recurring EU rule,
  /// not the package's incorrect permanent-last-offset extrapolation.
  static DateTime get verifiedUntilUtc => DateTime.fromMillisecondsSinceEpoch(
    _location.transitionAt.last,
    isUtc: true,
  );

  static final Map<int, tz.Location> _futureLocations = {};
  static tz.Location _locationFor(DateTime instant) {
    if (instant.toUtc().isBefore(verifiedUntilUtc)) return _location;
    final year = instant.toUtc().year;
    return _futureLocations.putIfAbsent(year, () {
      final transitions = <int>[DateTime.utc(year - 1).millisecondsSinceEpoch];
      final zones = <int>[0];
      for (var y = year - 1; y <= year + 1; y++) {
        for (final month in [3, 10]) {
          final end = DateTime.utc(y, month + 1, 0, 1);
          transitions.add(
            end
                .subtract(Duration(days: end.weekday % 7))
                .millisecondsSinceEpoch,
          );
          zones.add(month == 3 ? 1 : 0);
        }
      }
      return tz.Location(zoneName, transitions, zones, const [
        tz.TimeZone(3600000, isDst: false, abbreviation: 'CET'),
        tz.TimeZone(7200000, isDst: true, abbreviation: 'CEST'),
      ]);
    });
  }

  static tz.TZDateTime localTime(DateTime instant) {
    return tz.TZDateTime.from(instant, _locationFor(instant));
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
      final local = localTime(candidate);
      if (local.year == date.year &&
          local.month == date.month &&
          local.day == date.day &&
          local.hour == hour &&
          local.minute == minute &&
          local.second == second) {
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
