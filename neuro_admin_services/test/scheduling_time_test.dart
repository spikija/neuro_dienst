import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'future Vienna dates extend current EU recurrence instead of freezing at 2037',
    () {
      expect(
        ViennaSchedulingTime.localTime(DateTime.utc(2038, 7, 1, 6)).hour,
        8,
      );
      expect(
        ViennaSchedulingTime.resolveWallTime(HospitalDate(2100, 7, 1), 8, 0),
        DateTime.utc(2100, 7, 1, 6),
      );
      expect(
        ViennaSchedulingTime.resolveWallTime(HospitalDate(2100, 1, 1), 8, 0),
        DateTime.utc(2100, 1, 1, 7),
      );
      expect(
        () => ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2040, 3, 25),
          2,
          30,
        ),
        throwsFormatException,
      );
      expect(
        () => ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2040, 10, 28),
          2,
          30,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'date-only identity is strict and independent of an instant conversion',
    () {
      expect(
        HospitalDate.parse('2026-10-01'),
        HospitalDate.fromCalendarComponents(DateTime(2026, 10, 1, 23)),
      );
      expect({
        HospitalDate(2026, 10, 1),
        HospitalDate.parse('2026-10-01'),
      }, hasLength(1));
      expect(HospitalDate(2026, 3, 29).addDays(1), HospitalDate(2026, 3, 30));
      expect(HospitalDate(2026, 10, 25).addDays(1), HospitalDate(2026, 10, 26));
      expect(HospitalDate(2024, 2, 29).toString(), '2024-02-29');
      expect(() => HospitalDate(2026, 2, 29), throwsArgumentError);
      expect(() => HospitalDate.parse('2026-02-30'), throwsFormatException);
      expect(
        () => HospitalDate.parse('2026-10-01T00:00:00Z'),
        throwsFormatException,
      );
    },
  );

  test('Vienna wall clocks convert to UTC with winter and summer offsets', () {
    expect(
      ViennaSchedulingTime.resolveWallTime(HospitalDate(2026, 1, 15), 8, 0),
      DateTime.utc(2026, 1, 15, 7),
    );
    expect(
      ViennaSchedulingTime.resolveWallTime(HospitalDate(2026, 7, 15), 8, 0),
      DateTime.utc(2026, 7, 15, 6),
    );
    expect(
      ViennaSchedulingTime.dateOfInstant(DateTime.utc(2026, 7, 15, 23)),
      HospitalDate(2026, 7, 16),
    );
  });

  test(
    'DST spring gap is rejected and autumn fold requires an explicit choice',
    () {
      expect(
        () => ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2026, 3, 29),
          2,
          30,
        ),
        throwsFormatException,
      );
      expect(
        () => ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2026, 10, 25),
          2,
          30,
        ),
        throwsFormatException,
      );
      expect(
        ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2026, 10, 25),
          2,
          30,
          ambiguity: AmbiguousWallTime.earlier,
        ),
        DateTime.utc(2026, 10, 25, 0, 30),
      );
      expect(
        ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2026, 10, 25),
          2,
          30,
          ambiguity: AmbiguousWallTime.later,
        ),
        DateTime.utc(2026, 10, 25, 1, 30),
      );
      expect(
        () => ViennaSchedulingTime.resolveWallTime(
          HospitalDate(2026, 10, 1),
          24,
          0,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'display is identical with different process-local timezone settings',
    () {
      final instant = DateTime.utc(2026, 7, 15, 6);
      final expected = ViennaSchedulingTime.localTime(instant);
      final original = tz.local;
      addTearDown(() => tz.setLocalLocation(original));
      for (final name in ['America/New_York', 'Asia/Tokyo', 'UTC']) {
        tz.setLocalLocation(tz.getLocation(name));
        final actual = ViennaSchedulingTime.localTime(instant);
        expect(actual.hour, 8);
        expect(actual.toString(), expected.toString());
      }
    },
  );

  test(
    'naive stored timestamps are rejected instead of inheriting device timezone',
    () {
      expect(
        ViennaSchedulingTime.parseInstant('2026-07-15T08:00:00+02:00'),
        DateTime.utc(2026, 7, 15, 6),
      );
      expect(
        ViennaSchedulingTime.parseInstant('2026-07-15T06:00:00Z'),
        DateTime.utc(2026, 7, 15, 6),
      );
      expect(
        () => ViennaSchedulingTime.parseInstant('2026-07-15T08:00:00'),
        throwsFormatException,
      );
    },
  );
}
