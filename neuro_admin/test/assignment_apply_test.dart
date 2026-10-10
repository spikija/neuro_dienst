import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_preview_test.dart'
    show PreviewReader, selectDates, chooseRole, chooseDoctor;

class FakeMutations implements AssignmentMutationService {
  bool authorized = true;
  Future<bool> Function()? accessCheck;
  final calls = <AssignmentCommitRequest>[];
  Future<AssignmentMutationReceipt> Function(AssignmentCommitRequest)? handler;
  @override
  Future<bool> canApply() async =>
      accessCheck == null ? authorized : await accessCheck!();
  @override
  Future<AssignmentMutationReceipt> bulkAssign(
    AssignmentCommitRequest request,
  ) {
    calls.add(request);
    return handler!(request);
  }

  @override
  Future<AssignmentMutationReceipt> assign(AssignmentCommitRequest r) =>
      bulkAssign(r);
  @override
  Future<AssignmentMutationReceipt> remove(AssignmentRemovalRequest r) =>
      throw UnimplementedError();
  @override
  Future<AssignmentMutationReceipt> replace(AssignmentReplacementRequest r) =>
      throw UnimplementedError();
}

Future<void> setup(
  WidgetTester tester,
  PreviewReader reader,
  FakeMutations mutations,
) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: RosterDashboard(
        reader: reader,
        mutations: mutations,
        onSignOut: () async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await selectDates(tester, 1);
  await chooseRole(tester, leader);
  await chooseDoctor(tester, 'ana');
  // Preselection includes all three valid dates. Explicitly keep only day 1.
  await selectDates(tester, 2);
  await selectDates(tester, 3);
}

AssignmentMutationReceipt receipt(AssignmentCommitRequest request) =>
    AssignmentMutationReceipt(
      requestId: request.operation.requestId,
      version: RosterVersion('october', 2),
      addedAssignmentIds: ['new'],
      removedAssignmentIds: [],
    );
Finder get apply => find.widgetWithText(FilledButton, 'Apply assignments');

void main() {
  testWidgets(
    'disposing the workflow during access recheck prevents submission',
    (tester) async {
      final reader = PreviewReader(previewFixture(contentVersion: 1));
      final mutations = FakeMutations();
      await setup(tester, reader, mutations);
      final access = Completer<bool>();
      mutations.accessCheck = () => access.future;
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and apply'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      access.complete(true);
      await tester.pumpAndSettle();
      expect(mutations.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'valid preview confirms once, disables in-flight Apply, reloads and keeps dates',
    (tester) async {
      final reader = PreviewReader(previewFixture(contentVersion: 1));
      final mutations = FakeMutations();
      final pending = Completer<AssignmentMutationReceipt>();
      mutations.handler = (_) => pending.future;
      await setup(tester, reader, mutations);
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(find.text('Confirm assignments'), findsOneWidget);
      expect(find.text('1 dates; all-or-nothing'), findsOneWidget);
      expect(mutations.calls, isEmpty);
      await tester.tap(find.text('Confirm and apply'));
      await tester.pump();
      expect(mutations.calls, hasLength(1));
      expect(
        find.byType(CalendarDayGrid),
        findsOneWidget,
        reason: 'The roster stays visible while the write is pending',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Applying...'),
            )
            .onPressed,
        isNull,
      );
      final request = mutations.calls.single;
      expect(request.preview.request.roster.contentVersion, 1);
      reader.snapshot = previewFixture(
        contentVersion: 2,
        facts: [
          AssignmentFact(
            'new',
            ana(),
            duty(1),
            AssignmentState.confirmed,
            RosterPhase.draft,
          ),
        ],
      );
      pending.complete(receipt(request));
      await tester.pumpAndSettle();
      expect(reader.reads, 2);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(AssignmentCandidatePanel), findsOneWidget);
      expect(
        tester
            .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
            .selection
            .dates,
        hasLength(2),
      );
      expect(
        find.text('Assignments saved. Roster and workload refreshed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final variant in ['unversioned', 'unauthorized', 'invalid']) {
    testWidgets('Apply disabled for $variant', (tester) async {
      final reader = PreviewReader(
        previewFixture(contentVersion: variant == 'unversioned' ? null : 1),
      );
      final mutations = FakeMutations()..authorized = variant != 'unauthorized';
      await setup(tester, reader, mutations);
      if (variant == 'invalid') await chooseDoctor(tester, 'ben');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      expect(mutations.calls, isEmpty);
    });
  }
  testWidgets('stale response reloads and requires new preview', (
    tester,
  ) async {
    final reader = PreviewReader(previewFixture(contentVersion: 1));
    final mutations = FakeMutations()
      ..handler = (_) async => throw AssignmentMutationFailure('staleVersion');
    await setup(tester, reader, mutations);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and apply'));
    await tester.pumpAndSettle();
    expect(reader.reads, 2);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(AssignmentPreviewDetails), findsOneWidget);
    expect(
      find.textContaining('Roster changed. Data reloaded'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('authoritative per-date errors override valid advisory preview', (
    tester,
  ) async {
    final reader = PreviewReader(previewFixture(contentVersion: 1));
    final mutations = FakeMutations()
      ..handler = (request) async => throw AssignmentMutationFailure(
        'validationFailed',
        results: [
          AssignmentValidationResult(
            date: HospitalDate(2026, 10, 1),
            slotId: 'sul-1',
            physicianId: 'ana',
            roleId: 'sul',
            errors: [
              const AssignmentValidationError(
                AssignmentErrorCode.slotFull,
                'Server slot is full.',
              ),
            ],
          ),
        ],
      );
    await setup(tester, reader, mutations);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and apply'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
          .selection
          .dates,
      isEmpty,
    );
    expect(
      find.text('2 assignable | 0 selected | 1 blocked | 0 warning-only'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(reader.reads, 1);
    expect(find.textContaining('Server rejected'), findsOneWidget);
  });
  testWidgets(
    'uncertain response retries identical request ID without a second confirmation',
    (tester) async {
      final reader = PreviewReader(previewFixture(contentVersion: 1));
      final mutations = FakeMutations();
      mutations.handler = (request) async {
        if (mutations.calls.length == 1) {
          throw AssignmentMutationFailure(
            'connectionError',
            outcomeUnknown: true,
          );
        }
        return receipt(request);
      };
      await setup(tester, reader, mutations);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(mutations.calls, hasLength(2));
      expect(mutations.calls[0], same(mutations.calls[1]));
      expect(reader.reads, 2);
    },
  );
  testWidgets('locked roster requires correction reason before confirmation', (
    tester,
  ) async {
    final reader = PreviewReader(
      previewFixture(contentVersion: 1, phase: RosterPhase.locked),
    );
    final mutations = FakeMutations()
      ..handler = (request) async => receipt(request);
    await setup(tester, reader, mutations);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Confirm and apply');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Reviewed correction');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(
      mutations.calls.single.preview.request.correctionReason,
      'Reviewed correction',
    );
    expect(tester.takeException(), isNull);
  });
}
