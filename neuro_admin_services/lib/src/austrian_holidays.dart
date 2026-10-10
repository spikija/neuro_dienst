import 'package:neuro_core/neuro_core.dart';
import 'scheduling_time.dart';

/// Nationwide statutory calendar, Gregorian Easter; no network or timezone
/// conversion of DATE values. Regional/school holidays are deliberately absent.
abstract final class AustrianHolidays {
  static const source = 'AT-national-gregorian-v1';
  static Map<HospitalDate, String> forYear(int year) {
    HospitalDate(year, 1, 1); // Validate the domain's full 1..9999 range.
    final a = year % 19, b = year ~/ 100, c = year % 100;
    final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4, k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final n = h + l - 7 * m + 114;
    final easter = HospitalDate(year, n ~/ 31, n % 31 + 1);
    final holidays = <HospitalDate, String>{
      HospitalDate(year, 1, 1): 'Neujahr',
      HospitalDate(year, 1, 6): 'Heilige Drei Könige',
      HospitalDate(year, 5, 1): 'Staatsfeiertag',
      HospitalDate(year, 8, 15): 'Mariä Himmelfahrt',
      HospitalDate(year, 10, 26): 'Nationalfeiertag',
      HospitalDate(year, 11, 1): 'Allerheiligen',
      HospitalDate(year, 12, 8): 'Mariä Empfängnis',
      HospitalDate(year, 12, 25): 'Christtag',
      HospitalDate(year, 12, 26): 'Stefanitag',
    };
    for (final entry in {
      1: 'Ostermontag',
      39: 'Christi Himmelfahrt',
      50: 'Pfingstmontag',
      60: 'Fronleichnam',
    }.entries) {
      final date = easter.addDays(entry.key);
      holidays.update(
        date,
        (name) => '$name; ${entry.value}',
        ifAbsent: () => entry.value,
      );
    }
    return Map.unmodifiable(holidays);
  }

  static CalendarDayInfo day(HospitalDate date) {
    final name = forYear(date.year)[date];
    return CalendarDayInfo(
      date: date.asDateOnlyUtc,
      isWeekend: date.asDateOnlyUtc.weekday >= DateTime.saturday,
      isPublicHoliday: name != null,
      publicHolidayName: name,
    );
  }

  static bool isWorkingDay(HospitalDate date) {
    final info = day(date);
    return !info.isWeekend && !info.isPublicHoliday;
  }
}
