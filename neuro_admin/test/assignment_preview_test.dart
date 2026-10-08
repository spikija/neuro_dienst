import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import '../../neuro_admin_services/test/support/preview_fixture.dart';

class PreviewReader implements RosterReader {
  RosterSnapshot snapshot;
  int reads = 0;
  PreviewReader(this.snapshot);
  @override
  Future<List<RosterChoice>> listMonths() async => [
    snapshot.month,
    const RosterChoice('september', 2026, 9, RosterPhase.draft),
  ];
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) async {
    reads++;
    return month.id == snapshot.month.id
        ? snapshot
        : RosterSnapshot(month, [], snapshot.doctors, {}, [], {});
  }
}

Future<void> selectDates(WidgetTester tester, int first, [int? last]) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  Offset center(int day) =>
      tester.getCenter(find.byKey(ValueKey(DateTime.utc(2026, 10, day))));
  await mouse.addPointer(location: center(first));
  await mouse.down(center(first));
  await tester.pump();
  if (last != null) await mouse.moveTo(center(last));
  await mouse.up();
  await mouse.removePointer();
  await tester.pumpAndSettle();
}

Future<void> chooseRole(WidgetTester tester, StoredRole role) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('${role.code}: ${role.name}').last);
  await tester.pumpAndSettle();
}

Future<void> chooseDoctor(WidgetTester tester, String id) async {
  final candidate = find.byKey(ValueKey('candidate-$id'));
  if (candidate.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      candidate,
      id == 'ana' ? -100 : 100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('physician-candidates')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  final name = find
      .descendant(of: candidate, matching: find.byType(Text))
      .first;
  await tester.ensureVisible(name);
  await tester.pumpAndSettle();
  await tester.tap(name);
  await tester.pumpAndSettle();
}

Future<void> revealPreview(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    60,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('assignment-preview-details')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
}

void main() {
  testWidgets(
    'working-day and clear buttons invalidate preview, preserve role/physician and perform no reads',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = PreviewReader(previewFixture());
      await tester.pumpWidget(
        MaterialApp(
          home: RosterDashboard(reader: reader, onSignOut: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await selectDates(tester, 1);
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      await tester.tap(find.text('Select all working days'));
      await tester.pump();
      expect(find.byType(AssignmentPreviewDetails), findsNothing);
      await tester.pumpAndSettle();
      final preview = tester
          .widget<AssignmentPreviewDetails>(
            find.byType(AssignmentPreviewDetails),
          )
          .preview;
      expect(preview.results, hasLength(22));
      expect(preview.validCount, 2);
      expect(preview.blockedCount, 20);
      expect(preview.request.physicianId, 'ana');
      expect(preview.request.roleId, 'sul');
      expect(find.text('22 days selected'), findsOneWidget);
      expect(
        find.text('Monday–Friday only; public holidays may be included.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      expect(find.text('0 days selected'), findsOneWidget);
      expect(find.byType(AssignmentCandidatePanel), findsNothing);
      await tester.tap(find.text('Select all working days'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssignmentPreviewDetails>(
              find.byType(AssignmentPreviewDetails),
            )
            .preview
            .results,
        hasLength(22),
      );
      expect(reader.reads, 1);
      expect(reader.snapshot.facts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [
    const Size(1280, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('bulk preview fits $size and keeps Apply disabled', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = PreviewReader(previewFixture());
      await tester.pumpWidget(
        MaterialApp(
          home: RosterDashboard(reader: reader, onSignOut: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await selectDates(tester, 1, 3);
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ben');
      await chooseDoctor(tester, 'ana');
      expect(
        find.text('3 valid | 0 valid with warnings | 0 blocked'),
        findsOneWidget,
      );
      await revealPreview(
        tester,
        find.text('3 proposed additions; no replacements'),
      );
      expect(
        find.textContaining(
          '90 days: 24h 0 (weekend 0) | station 0 | ambulance 0 | science 0',
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply assignments'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
            .selection
            .dates,
        hasLength(3),
      );
      expect(reader.reads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'role, physician, date and reload changes recompute; cancel and month clear preview',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = PreviewReader(previewFixture());
      await tester.pumpWidget(
        MaterialApp(
          home: RosterDashboard(reader: reader, onSignOut: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await selectDates(tester, 1, 3);
      await chooseRole(tester, leader);
      await chooseDoctor(tester, 'ana');
      await chooseDoctor(tester, 'ben');
      expect(
        find.text('0 valid | 0 valid with warnings | 3 blocked'),
        findsOneWidget,
      );
      expect(find.textContaining('physicianNotEligible:'), findsWidgets);
      await chooseRole(tester, ambulance);
      expect(
        find.text('1 valid | 0 valid with warnings | 2 blocked'),
        findsOneWidget,
      );
      expect(find.textContaining('missingSlot:'), findsWidgets);
      expect(
        tester
            .widget<AssignmentPreviewDetails>(
              find.byType(AssignmentPreviewDetails),
            )
            .preview
            .request
            .roleId,
        'amb',
      );
      await chooseRole(tester, icb);
      expect(
        tester
            .widget<AssignmentPreviewDetails>(
              find.byType(AssignmentPreviewDetails),
            )
            .preview
            .results[2]
            .slotId,
        'icb-3',
      );
      await selectDates(tester, 3);
      expect(
        find.text('1 valid | 0 valid with warnings | 0 blocked'),
        findsOneWidget,
      );
      reader.snapshot = previewFixture(inactive: {'ben'});
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(
        find.text('0 valid | 0 valid with warnings | 1 blocked'),
        findsOneWidget,
      );
      expect(find.textContaining('inactivePhysician:'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel preview'));
      await tester.pumpAndSettle();
      expect(find.byType(AssignmentCandidatePanel), findsNothing);
      expect(find.text('1 day selected'), findsOneWidget);
      await chooseRole(tester, leader);
      await tester.tap(find.byKey(const ValueKey('month-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09').last);
      await tester.pumpAndSettle();
      expect(find.byType(AssignmentCandidatePanel), findsNothing);
      expect(find.text('0 days selected'), findsOneWidget);
      expect(reader.reads, 3);
      expect(tester.takeException(), isNull);
    },
  );

  for (final phase in [RosterPhase.locked, RosterPhase.published]) {
    testWidgets(
      '$phase shows warnings/errors and current occupants without replacements',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final slot = duty(1, capacity: 2);
        final reader = PreviewReader(
          previewFixture(
            phase: phase,
            slots: [slot],
            facts: [
              AssignmentFact(
                'existing',
                ben(),
                slot,
                AssignmentState.confirmed,
                phase,
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: RosterDashboard(reader: reader, onSignOut: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        await selectDates(tester, 1);
        await chooseRole(tester, leader);
        await chooseDoctor(tester, 'ana');
        if (phase == RosterPhase.locked) {
          expect(
            find.text('0 valid | 1 valid with warnings | 0 blocked'),
            findsOneWidget,
          );
        } else {
          expect(
            find.text('0 valid | 0 valid with warnings | 1 blocked'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Published roster requires a new revision before editing.',
            ),
            findsWidgets,
          );
        }
        await revealPreview(
          tester,
          find.text('Current: Ben Example (confirmed)'),
        );
        await revealPreview(tester, find.text('Proposed: Ana Example'));
        await revealPreview(
          tester,
          find.textContaining(
            phase == RosterPhase.locked
                ? 'Warning: Locked roster:'
                : 'rosterNotEditable:',
          ),
        );
        expect(reader.snapshot.facts, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'late results from an earlier role cannot replace the current preview',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final snapshot = previewFixture();
      final deferred = DeferredValidation(snapshot);
      AssignmentValidationService factory(RosterSnapshot _) => deferred;
      Widget panel(StoredRole role) => MaterialApp(
        home: Scaffold(
          body: AssignmentCandidatePanel(
            snapshot: snapshot,
            role: role,
            dates: {HospitalDate(2026, 10, 2)},
            physicianId: 'ana',
            onPhysician: (_) {},
            onCancel: () {},
            serviceFactory: factory,
          ),
        ),
      );
      await tester.pumpWidget(panel(leader));
      await tester.pump(const Duration(milliseconds: 80));
      expect(deferred.pending, hasLength(2));
      await tester.pumpWidget(panel(ambulance));
      expect(find.byType(AssignmentPreviewDetails), findsNothing);
      await tester.pump(const Duration(milliseconds: 80));
      expect(deferred.pending, hasLength(4));
      await deferred.complete(2);
      await deferred.complete(3);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssignmentPreviewDetails>(
              find.byType(AssignmentPreviewDetails),
            )
            .preview
            .request
            .roleId,
        'amb',
      );
      await deferred.complete(0);
      await deferred.complete(1);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssignmentPreviewDetails>(
              find.byType(AssignmentPreviewDetails),
            )
            .preview
            .request
            .roleId,
        'amb',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class DeferredValidation implements AssignmentValidationService {
  final RosterSnapshot snapshot;
  final pending =
      <(AssignmentValidationRequest, Completer<AssignmentPreview>)>[];
  DeferredValidation(this.snapshot);
  @override
  Future<AssignmentPreview> preview(AssignmentValidationRequest request) {
    final completer = Completer<AssignmentPreview>();
    pending.add((request, completer));
    return completer.future;
  }

  Future<void> complete(int index) async {
    final (request, completer) = pending[index];
    completer.complete(
      await SnapshotAssignmentValidationService(snapshot).preview(request),
    );
  }
}
