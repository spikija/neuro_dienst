import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_day_markers.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import 'assignment_preview_test.dart' show PreviewReader;
import 'ef_day_test.dart' show november;
import 'workspace_test.dart' show display;

AvailabilityPeriod period(AvailabilityType type, int first, [int? last]) =>
    AvailabilityPeriod(
      start: DateTime.utc(2026, 11, first),
      end: DateTime.utc(2026, 11, last ?? first),
      type: type,
    );
RosterSnapshot fixture({bool generated = true}) {
  final source = november(generated: generated);
  return RosterSnapshot(
    source.month,
    source.days,
    [
      source.doctors.single.copyWith(
        availabilities: [
          period(AvailabilityType.vacation, 17, 19),
          period(AvailabilityType.vacation, 18),
          period(AvailabilityType.efDay, 18),
        ],
      ),
      Doctor(
        id: 'other',
        firstName: 'Other',
        lastName: 'Physician',
        rank: DoctorRank.resident,
        availabilities: [period(AvailabilityType.sickLeave, 18)],
      ),
    ],
    {},
    [],
    {},
  );
}

Finder marker(AvailabilityType type, {int day = 18}) => find.byKey(
  ValueKey(
    type == AvailabilityType.efDay
        ? 'calendar-ef-2026-11-$day'
        : 'calendar-absence-${type.name}-2026-11-$day',
  ),
);

void main() {
  test(
    'date grouping deduplicates periods and scopes markers to the chosen physician',
    () {
      final snapshot = fixture();
      final markers = calendarDayMarkers(
        snapshot.doctors,
        DateTime.utc(2026, 11, 18),
      );
      expect(markers.map((m) => m.type), [
        AvailabilityType.efDay,
        AvailabilityType.vacation,
        AvailabilityType.sickLeave,
      ]);
      expect(markers[1].physicians, hasLength(1));
      expect(
        markers[1].description(const AdminStrings('de')),
        'Urlaub: Johanna Mayrhofer',
      );
      expect(
        calendarDayMarkers(snapshot.doctors, DateTime.utc(2026, 11, 16)),
        isEmpty,
      );
      expect(
        calendarDayMarkers(
          snapshot.doctors,
          DateTime.utc(2026, 11, 18),
          physicianId: 'other',
        ).single.type,
        AvailabilityType.sickLeave,
      );
    },
  );

  for (final generated in [true, false]) {
    testWidgets(
      'calendar shows vacation and sick leave with generated date=$generated and filters by physician',
      (tester) async {
        await display(
          tester,
          RosterDashboard(
            reader: PreviewReader(fixture(generated: generated)),
            onSignOut: () async {},
          ),
        );
        expect(marker(AvailabilityType.vacation), findsOneWidget);
        expect(marker(AvailabilityType.sickLeave), findsOneWidget);
        expect(marker(AvailabilityType.efDay), findsOneWidget);
        expect(find.byTooltip('Vacation: Johanna Mayrhofer'), findsWidgets);
        expect(find.byTooltip('Sick leave: Other Physician'), findsOneWidget);
        // Icons retain the calendar's date selection, exposing the daily details.
        await tester.tap(marker(AvailabilityType.vacation));
        await tester.pumpAndSettle();
        expect(find.text('Johanna Mayrhofer: Vacation'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('physician-search')),
          'Joh',
        );
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(marker(AvailabilityType.vacation), findsOneWidget);
        expect(marker(AvailabilityType.sickLeave), findsNothing);
        await tester.enterText(
          find.byKey(const ValueKey('physician-search')),
          'Other',
        );
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(marker(AvailabilityType.vacation), findsNothing);
        expect(marker(AvailabilityType.efDay), findsNothing);
        expect(marker(AvailabilityType.sickLeave), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'narrow $brightness markers retain all details in localized overflow',
      (tester) async {
        final doctor = fixture().doctors.first.copyWith(
          availabilities: [
            for (final type in AvailabilityType.values) period(type, 18),
          ],
        );
        final markers = calendarDayMarkers([
          doctor,
        ], DateTime.utc(2026, 11, 18));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            locale: const Locale('de'),
            supportedLocales: const [Locale('en'), Locale('de')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 60,
                  child: CalendarDayMarkerIndicators(
                    date: HospitalDate(2026, 11, 18),
                    markers: markers,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(marker(AvailabilityType.efDay), findsOneWidget);
        final overflow = find.byKey(
          const ValueKey('calendar-absence-overflow-2026-11-18'),
        );
        expect(tester.widget<Text>(overflow).data, '+10');
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: overflow, matching: find.byType(Tooltip)),
        );
        for (final entry in markers.skip(2)) {
          expect(
            tooltip.message,
            contains(entry.description(const AdminStrings('de'))),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
