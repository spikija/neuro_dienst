import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/calendar_theme.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_preview_test.dart'
    show
        PreviewReader,
        chooseRole,
        chooseDoctor,
        selectDates,
        DeferredValidation;
import 'assignment_apply_test.dart' show FakeMutations, receipt;

Future<void> showDashboard(
  WidgetTester tester,
  RosterReader reader, {
  PreviewServiceFactory? factory,
  FakeMutations? mutations,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: adminTheme(brightness),
      home: RosterDashboard(
        reader: reader,
        onSignOut: () async {},
        previewServiceFactory: factory,
        mutations: mutations,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Set<DateTime> selected(WidgetTester tester) => tester
    .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
    .selection
    .dates;
Finder cell(int day) => find.byKey(
  ValueKey('assignability-2026-10-${day.toString().padLeft(2, '0')}'),
);

void main() {
  testWidgets(
    'failed month validation clears eligibility and keeps all dates unselectable',
    (tester) async {
      await showDashboard(
        tester,
        PreviewReader(previewFixture()),
        factory: (_) => BrokenValidation(),
      );
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      expect(
        find.text('Month validation failed. Reload to retry.'),
        findsOneWidget,
      );
      await selectDates(tester, 1, 3);
      expect(selected(tester), isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply assignments'),
            )
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'role only and physician only do not preselect; both validate every calendar date',
    (tester) async {
      final reader = PreviewReader(previewFixture());
      final requests = <AssignmentValidationRequest>[];
      await showDashboard(
        tester,
        reader,
        factory: (s) => RecordingValidation(s, requests),
      );
      await tester.tap(find.text('Ana Example'));
      await tester.pumpAndSettle();
      expect(selected(tester), isEmpty);
      expect(requests, isEmpty);
      await tester.tap(find.text('Clear physician selection'));
      await tester.pumpAndSettle();
      await chooseRole(tester, leader);
      expect(selected(tester), isEmpty);
      await chooseDoctor(tester, 'ana');
      expect(requests.last.targets, hasLength(31));
      expect(requests.last.targets.last.date, HospitalDate(2026, 10, 31));
      expect(selected(tester), {
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 2),
        DateTime.utc(2026, 10, 3),
      });
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'valid highlight survives manual deselection and reselection in $brightness',
      (tester) async {
        await showDashboard(
          tester,
          PreviewReader(previewFixture()),
          brightness: brightness,
        );
        await chooseRole(tester, leader);
        await chooseDoctor(tester, 'ana');
        expect(
          (tester.widget<AnimatedContainer>(cell(1)).decoration
                  as BoxDecoration)
              .border!
              .top
              .width,
          3,
        );
        await selectDates(tester, 1);
        expect(selected(tester).contains(DateTime.utc(2026, 10, 1)), isFalse);
        expect(
          (tester.widget<AnimatedContainer>(cell(1)).decoration
                  as BoxDecoration)
              .border!
              .top
              .width,
          2,
        );
        await selectDates(tester, 1);
        expect(selected(tester), hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('warning-valid dates are highlighted and initially selected', (
    tester,
  ) async {
    await showDashboard(
      tester,
      PreviewReader(previewFixture(phase: RosterPhase.locked)),
    );
    await chooseRole(tester, leader);
    await chooseDoctor(tester, 'ana');
    expect(selected(tester), hasLength(3));
    expect(
      find.descendant(of: cell(1), matching: find.byIcon(Icons.warning_amber)),
      findsOneWidget,
    );
    expect(
      find.text('3 assignable | 3 selected | 0 blocked | 3 warning-only'),
      findsOneWidget,
    );
  });

  testWidgets(
    'blocked and missing dates cannot be clicked or added by rectangular drag',
    (tester) async {
      final full = duty(1);
      await showDashboard(
        tester,
        PreviewReader(
          previewFixture(
            slots: [full, duty(2)],
            facts: [
              AssignmentFact(
                'full',
                ben(),
                full,
                AssignmentState.confirmed,
                RosterPhase.draft,
              ),
            ],
          ),
        ),
      );
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
      expect(
        find.descendant(of: cell(1), matching: find.byIcon(Icons.block)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: cell(1),
          matching: find.byIcon(Icons.person_outline),
        ),
        findsOneWidget,
      );
      expect(
        (tester.widget<AnimatedContainer>(cell(3)).decoration as BoxDecoration)
            .border!
            .top
            .width,
        1,
      );
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      await selectDates(tester, 1, 3);
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
      await selectDates(tester, 1);
      await selectDates(tester, 3);
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      expect(selected(tester), isEmpty);
      await tester.tap(find.text('Select all assignable days'));
      await tester.pumpAndSettle();
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
    },
  );

  testWidgets(
    'physician and role changes reset preselection; month changes recompute',
    (tester) async {
      final reader = HighlightReader(previewFixture());
      await showDashboard(tester, reader);
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      await selectDates(tester, 1);
      expect(selected(tester), hasLength(2));
      await chooseDoctor(tester, 'ana');
      expect(selected(tester), hasLength(2));
      await chooseDoctor(tester, 'ben');
      expect(selected(tester), isEmpty);
      await chooseDoctor(tester, 'ana');
      expect(selected(tester), hasLength(3));
      await chooseRole(tester, ambulance);
      expect(selected(tester), {DateTime.utc(2026, 10, 2)});
      await chooseRole(tester, leader);
      expect(selected(tester), hasLength(3));
      await tester.tap(find.byKey(const ValueKey('month-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(selected(tester), {DateTime.utc(2026, 9, 1)});
      expect(reader.reads, 2);
    },
  );

  testWidgets(
    'Apply excludes deselected dates and confirmation includes warning count',
    (tester) async {
      final mutations = FakeMutations()..handler = (r) async => receipt(r);
      await showDashboard(
        tester,
        PreviewReader(previewFixture(contentVersion: 1)),
        mutations: mutations,
      );
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      await selectDates(tester, 2);
      await tester.tap(find.text('Apply assignments'));
      await tester.pumpAndSettle();
      expect(find.text('2 dates; all-or-nothing'), findsOneWidget);
      expect(find.text('0 selected dates with warnings'), findsOneWidget);
      expect(find.text('2026-10-01, 2026-10-03'), findsOneWidget);
      await tester.tap(find.text('Confirm and apply'));
      await tester.pumpAndSettle();
      expect(
        mutations.calls.single.preview.request.targets.map((t) => t.date),
        [HospitalDate(2026, 10, 1), HospitalDate(2026, 10, 3)],
      );
    },
  );

  testWidgets('late physician results cannot preselect obsolete dates', (
    tester,
  ) async {
    final snapshot = previewFixture();
    final deferred = DeferredValidation(snapshot);
    final published = <MonthAssignability>[];
    AssignmentValidationService factory(RosterSnapshot _) => deferred;
    Widget panel(String physician) => MaterialApp(
      home: Scaffold(
        body: AssignmentCandidatePanel(
          snapshot: snapshot,
          role: leader,
          dates: {},
          physicianId: physician,
          onPhysician: (_) {},
          onCancel: () {},
          serviceFactory: factory,
          onAssignability: (validity, _) => published.add(validity),
        ),
      ),
    );
    await tester.pumpWidget(panel('ana'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(panel('ben'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(deferred.pending, hasLength(4));
    await deferred.complete(0);
    await deferred.complete(1);
    await tester.pump();
    expect(published, isEmpty);
    await deferred.complete(2);
    await deferred.complete(3);
    await tester.pumpAndSettle();
    expect(published.single.preview.request.physicianId, 'ben');
    expect(published.single.assignableDates, isEmpty);
  });
}

class RecordingValidation implements AssignmentValidationService {
  final RosterSnapshot snapshot;
  final List<AssignmentValidationRequest> requests;
  RecordingValidation(this.snapshot, this.requests);
  @override
  Future<AssignmentPreview> preview(AssignmentValidationRequest request) {
    requests.add(request);
    return SnapshotAssignmentValidationService(snapshot).preview(request);
  }
}

class BrokenValidation implements AssignmentValidationService {
  @override
  Future<AssignmentPreview> preview(
    AssignmentValidationRequest request,
  ) async => throw StateError('test validation unavailable');
}

class HighlightReader extends PreviewReader {
  HighlightReader(super.snapshot);
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) async {
    if (month.id == snapshot.month.id) return super.loadMonth(month);
    reads++;
    final date = DateTime.utc(month.year, month.month, 1);
    final slot = StoredDuty(
      'september-slot',
      date,
      leader,
      date.add(const Duration(hours: 8)),
      date.add(const Duration(hours: 16)),
      1,
    );
    return RosterSnapshot(
      month,
      [
        StoredDay(
          CalendarDayInfo(date: date, isWeekend: false, isPublicHoliday: false),
          [slot],
          [],
        ),
      ],
      snapshot.doctors,
      {},
      [],
      {},
      roles: [leader, ambulance, icb],
      hasOverlapCoverage: true,
    );
  }
}
