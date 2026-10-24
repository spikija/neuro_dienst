import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import 'assignment_preview_test.dart' show PreviewReader;
import 'ef_day_test.dart' show november, focus18;
import 'workspace_test.dart' show display;

RosterSnapshot fixture(
  AvailabilityType type, {
  bool removed = false,
  bool duplicate = false,
}) {
  final source = november();
  return RosterSnapshot(
    source.month,
    source.days,
    [
      source.doctors.single.copyWith(
        availabilities: [
          if (!removed)
            AvailabilityPeriod(
              start: DateTime.utc(2026, 11, 17),
              end: DateTime.utc(2026, 11, 19),
              type: type,
            )
          else
            for (final day in [17, 19])
              AvailabilityPeriod(
                start: DateTime.utc(2026, 11, day),
                end: DateTime.utc(2026, 11, day),
                type: type,
              ),
          AvailabilityPeriod(
            start: DateTime.utc(2026, 11, 18),
            end: DateTime.utc(2026, 11, 18),
            type: type == AvailabilityType.efDay
                ? AvailabilityType.vacation
                : AvailabilityType.efDay,
          ),
          if (duplicate)
            AvailabilityPeriod(
              start: DateTime.utc(2026, 11, 18),
              end: DateTime.utc(2026, 11, 18),
              type: type,
            ),
        ],
      ),
    ],
    {},
    [],
    {},
    contentVersion: removed ? 2 : 1,
  );
}

class FakeRemoval implements AbsenceDayRemovalService {
  final PreviewReader reader;
  final AvailabilityType type;
  final calls = <AbsenceDayRemovalRequest>[];
  FakeRemoval(this.reader, this.type);
  @override
  Future<void> removeDay(AbsenceDayRemovalRequest request) async {
    calls.add(request);
    reader.snapshot = fixture(type, removed: true);
  }
}

void main() {
  testWidgets('overlapping periods of the same type have one removal control', (
    tester,
  ) async {
    final reader = PreviewReader(
      fixture(AvailabilityType.vacation, duplicate: true),
    );
    final service = FakeRemoval(reader, AvailabilityType.vacation);
    await display(
      tester,
      RosterDashboard(
        reader: reader,
        absenceRemovals: service,
        onSignOut: () async {},
      ),
    );
    await focus18(tester);
    final calendarMarker = find.byKey(
      const ValueKey('calendar-absence-vacation-2026-11-18'),
    );
    expect(calendarMarker, findsOneWidget);
    final remove = find.byKey(
      const ValueKey('remove-absence-johanna-vacation'),
    );
    expect(remove, findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove entry'));
    await tester.pumpAndSettle();
    expect(service.calls, hasLength(1));
    expect(remove, findsNothing);
    expect(calendarMarker, findsNothing);
  });
  for (final type in AvailabilityType.values) {
    testWidgets(
      'administrator can remove ${type.name} for one date, preserving other types and dates',
      (tester) async {
        final reader = PreviewReader(fixture(type));
        final service = FakeRemoval(reader, type);
        await display(
          tester,
          RosterDashboard(
            reader: reader,
            absenceRemovals: service,
            onSignOut: () async {},
          ),
        );
        await focus18(tester);
        final calendarMarker = find.byKey(
          ValueKey(
            type == AvailabilityType.efDay
                ? 'calendar-ef-2026-11-18'
                : 'calendar-absence-${type.name}-2026-11-18',
          ),
        );
        expect(calendarMarker, findsOneWidget);
        final remove = find.byKey(
          ValueKey('remove-absence-johanna-${type.name}'),
        );
        await tester.tap(remove);
        await tester.pumpAndSettle();
        final label = reader.snapshot.doctors.single.availabilities.first.label;
        expect(
          find.text('Remove $label for Johanna Mayrhofer on 18.11.2026?'),
          findsOneWidget,
        );
        expect(service.calls, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove entry'));
        await tester.pumpAndSettle();
        expect(service.calls.single.type, type);
        expect(service.calls.single.physicianId, 'johanna');
        expect(service.calls.single.date, HospitalDate(2026, 11, 18));
        expect(remove, findsNothing);
        expect(calendarMarker, findsNothing);
        final other = type == AvailabilityType.efDay
            ? AvailabilityType.vacation
            : AvailabilityType.efDay;
        expect(
          find.byKey(ValueKey('remove-absence-johanna-${other.name}')),
          findsOneWidget,
        );
        expect(
          reader.snapshot.doctors.single.availabilityOn(
            DateTime.utc(2026, 11, 17),
            type,
          ),
          isNotNull,
        );
        expect(
          reader.snapshot.doctors.single.availabilityOn(
            DateTime.utc(2026, 11, 19),
            type,
          ),
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
