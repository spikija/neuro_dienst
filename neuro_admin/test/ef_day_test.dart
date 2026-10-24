import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin/data/roster_reader.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import 'assignment_preview_test.dart' show PreviewReader;
import 'workspace_test.dart' show display;

RosterSnapshot november({
  bool removed = false,
  bool generated = true,
  int? version = 1,
}) => decodeRoster(
  const RosterChoice('november', 2026, 11, RosterPhase.draft),
  doctors: [
    {
      'id': 'johanna',
      'first_name': 'Johanna',
      'last_name': 'Mayrhofer',
      'rank': 'consultant',
      'is_active': true,
      'capabilities': [],
    },
  ],
  days: [
    if (generated)
      for (final day in [17, 18, 19])
        {
          'id': 'day-$day',
          'roster_id': 'november',
          'date': '2026-11-$day',
          'is_weekend': false,
          'is_public_holiday': false,
        },
  ],
  roles: [],
  slots: [],
  assignments: [],
  absences: [
    if (!removed)
      {
        'id': 'ef-period',
        'doctor_id': 'johanna',
        'starts_on': '2026-11-17',
        'ends_on': '2026-11-19',
        'type': 'ef_day',
      }
    else
      for (final day in [17, 19])
        {
          'id': 'ef-$day',
          'doctor_id': 'johanna',
          'starts_on': '2026-11-$day',
          'ends_on': '2026-11-$day',
          'type': 'ef_day',
        },
  ],
  rosterRows: [
    {'id': 'november', 'phase': 'draft'},
  ],
  contentVersion: version,
);

class FakeEfRemoval implements AbsenceDayRemovalService {
  final PreviewReader reader;
  final calls = <AbsenceDayRemovalRequest>[];
  bool uncertain = false;
  FakeEfRemoval(this.reader);
  @override
  Future<void> removeDay(AbsenceDayRemovalRequest request) async {
    calls.add(request);
    if (uncertain) {
      uncertain = false;
      throw AssignmentMutationFailure('connectionError', outcomeUnknown: true);
    }
    reader.snapshot = november(removed: true, version: 2);
  }
}

Finder marker(int day) => find.byKey(ValueKey('calendar-ef-2026-11-$day'));
Future<void> focus18(WidgetTester tester) async {
  await tester.tap(find.byKey(ValueKey(DateTime.utc(2026, 11, 18))));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'EF day database values decode on the stored November calendar date',
    () {
      final physician = november().doctors.single;
      expect(
        physician.absenceOn(DateTime.utc(2026, 11, 18))!.type,
        AvailabilityType.efDay,
      );
      expect(physician.absenceOn(DateTime.utc(2026, 11, 20)), isNull);
    },
  );

  for (final generated in [true, false]) {
    testWidgets(
      'EF is visible and removable on 18 November with generated day=$generated',
      (tester) async {
        final reader = PreviewReader(november(generated: generated));
        final service = FakeEfRemoval(reader);
        await display(
          tester,
          RosterDashboard(
            reader: reader,
            absenceRemovals: service,
            onSignOut: () async {},
          ),
        );
        expect(marker(18), findsOneWidget);
        await focus18(tester);
        expect(find.text('Johanna Mayrhofer: EF day'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('remove-absence-johanna-efDay')),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Remove EF day for Johanna Mayrhofer on 18.11.2026?'),
          findsOneWidget,
        );
        expect(service.calls, isEmpty);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove entry'));
        await tester.pumpAndSettle();
        expect(service.calls.single.date, HospitalDate(2026, 11, 18));
        expect(service.calls.single.physicianId, 'johanna');
        expect(service.calls.single.type, AvailabilityType.efDay);
        expect(service.calls.single.roster.contentVersion, 1);
        expect(marker(18), findsNothing);
        expect(marker(17), findsOneWidget);
        expect(marker(19), findsOneWidget);
        expect(reader.reads, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancel makes no change; uncertain removal retries the identical request',
    (tester) async {
      final reader = PreviewReader(november());
      final service = FakeEfRemoval(reader)..uncertain = true;
      await display(
        tester,
        RosterDashboard(
          reader: reader,
          absenceRemovals: service,
          onSignOut: () async {},
        ),
      );
      await focus18(tester);
      await tester.tap(
        find.byKey(const ValueKey('remove-absence-johanna-efDay')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(marker(18), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('remove-absence-johanna-efDay')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove entry'));
      await tester.pumpAndSettle();
      expect(marker(18), findsOneWidget);
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(service.calls, hasLength(2));
      expect(service.calls.first, same(service.calls.last));
      expect(marker(18), findsNothing);
    },
  );

  testWidgets('unversioned data shows the EF marker but disables removal', (
    tester,
  ) async {
    final reader = PreviewReader(november(version: null));
    final service = FakeEfRemoval(reader);
    await display(
      tester,
      RosterDashboard(
        reader: reader,
        absenceRemovals: service,
        onSignOut: () async {},
      ),
    );
    await focus18(tester);
    expect(marker(18), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('remove-absence-johanna-efDay')),
          )
          .onPressed,
      isNull,
    );
    expect(service.calls, isEmpty);
  });
}
