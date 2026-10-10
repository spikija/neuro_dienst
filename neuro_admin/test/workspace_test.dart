import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin/workspace_dialogs.dart';
import 'package:neuro_admin/reports_screen.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_preview_test.dart' show PreviewReader, selectDates;

class TestWorkspace
    implements
        AssignmentRemovalService,
        RosterGenerationService,
        ReportingService {
  final removed = <AdminWriteIntent>[];
  final generated = <RosterGenerationCommitRequest>[];
  bool uncertain = false;
  List<String> blockers = [];
  @override
  Future<AssignmentMutationReceipt> removeDates(
    AssignmentRemovalPreview p,
    AdminWriteIntent op,
  ) async {
    removed.add(op);
    if (uncertain) {
      uncertain = false;
      throw AssignmentMutationFailure('connectionError', outcomeUnknown: true);
    }
    return AssignmentMutationReceipt(
      requestId: op.requestId,
      version: RosterVersion(p.snapshot.month.id, 2),
      addedAssignmentIds: [],
      removedAssignmentIds: p.assignments.map((a) => a.id),
    );
  }

  @override
  Future<RosterGenerationPlan> preview(
    RosterGenerationRequest r, {
    RosterRevision? existing,
  }) async => RosterGenerationPlan(
    request: r,
    existing: existing,
    days: [AustrianHolidays.day(HospitalDate(r.year, r.month, 1))],
    slots: [],
    blockers: blockers,
    holidaySource: AustrianHolidays.source,
    backendToken: 'preview',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  );
  @override
  Future<RosterRevision> apply(RosterGenerationCommitRequest r) async {
    generated.add(r);
    return RosterRevision(
      version: RosterVersion('new', 1),
      year: r.plan.request.year,
      month: r.plan.request.month,
      revisionNumber: 1,
      phase: RosterPhase.draft,
      isCurrentPublished: false,
    );
  }

  @override
  Future<ReportDocument> load(ReportRequest r) async =>
      const FactualReportProjection().project(
        previewFixture(contentVersion: 1),
        ReportConfiguration(
          roles: [ReportRoleSetting(leader, 0, true)],
          physicianPrintOrder: {},
        ),
        r,
      );
}

Future<void> display(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(1920, 1080),
    const Size(1440, 900),
    const Size(1280, 720),
  ]) {
    testWidgets('three distinct panes and compact role controls at $size', (
      tester,
    ) async {
      await display(
        tester,
        RosterDashboard(
          reader: PreviewReader(previewFixture()),
          onSignOut: () async {},
        ),
      );
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final calendar = tester.getRect(find.byType(CalendarDayGrid));
      final middle = tester.getRect(
        find.byKey(const ValueKey('daily-roster-pane')),
      );
      expect(calendar.right, lessThan(middle.left));
      expect(find.text('Roster calendar'), findsNothing);
      expect(find.text('Duty role for preview'), findsNothing);
      await selectDates(tester, 1);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('daily-roster-pane')),
          matching: find.text('SUL: Stroke Unit Leadership'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('role-chip-sul')))
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'working-day menu excludes holiday; removal mode permits occupied date selection',
    (tester) async {
      final service = TestWorkspace();
      final slot = duty(1);
      await display(
        tester,
        RosterDashboard(
          reader: PreviewReader(
            previewFixture(
              contentVersion: 1,
              facts: [
                AssignmentFact(
                  'a',
                  ana(),
                  slot,
                  AssignmentState.confirmed,
                  RosterPhase.draft,
                ),
              ],
            ),
          ),
          removals: service,
          onSignOut: () async {},
        ),
      );
      Future<void> action(String label) async {
        await tester.tap(find.byTooltip('Selection actions'));
        await tester.pumpAndSettle();
        await tester.tap(
          label == 'Select occupied days for removal'
              ? find.byType(CheckedPopupMenuItem<String>)
              : find.text(label),
        );
        await tester.pumpAndSettle();
      }

      await action('Select all working days');
      expect(
        tester
            .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
            .selection
            .dates,
        isNot(contains(DateTime.utc(2026, 10, 26))),
      );
      expect(find.byIcon(Icons.celebration_outlined), findsOneWidget);
      await action('Select occupied days for removal');
      await selectDates(tester, 1);
      await action('Unassign all roles on selected days');
      expect(find.byType(RemovalDialog), findsOneWidget);
      expect(service.removed, isEmpty);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove assignments'));
      await tester.pumpAndSettle();
      expect(service.removed, hasLength(1));
      expect(find.byType(RemovalDialog), findsNothing);
    },
  );
  testWidgets(
    'locked removal needs reason and uncertain response retries same UUID',
    (tester) async {
      final service = TestWorkspace()..uncertain = true;
      final slot = duty(1);
      final p = AssignmentRemovalPreview(
        previewFixture(
          contentVersion: 1,
          phase: RosterPhase.locked,
          facts: [
            AssignmentFact(
              'a',
              ana(),
              slot,
              AssignmentState.confirmed,
              RosterPhase.locked,
            ),
          ],
        ),
        [HospitalDate(2026, 10, 1)],
        scope: RemovalScope.role,
        roleId: leader.id,
      );
      await display(tester, RemovalDialog(preview: p, service: service));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Remove assignments'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Correction');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove assignments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(service.removed, hasLength(2));
      expect(service.removed.first.requestId, service.removed.last.requestId);
      expect(service.removed.first.reason, 'Correction');
    },
  );
  testWidgets('generation requires preview and blocks destructive plans', (
    tester,
  ) async {
    final service = TestWorkspace()..blockers = ['assignmentLoss'];
    await display(tester, GenerationDialog(service: service));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create roster'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Occupied slots would be removed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Create roster'),
          )
          .onPressed,
      isNull,
    );
    service.blockers = [];
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create roster'));
    await tester.pumpAndSettle();
    expect(service.generated, hasLength(1));
  });
  testWidgets('screen reports switch between role and physician layouts', (
    tester,
  ) async {
    await display(
      tester,
      ReportsScreen(
        service: TestWorkspace(),
        roster: RosterVersion('october', 1),
      ),
    );
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('SUL: Stroke Unit Leadership'), findsOneWidget);
    await tester.tap(find.text('By physician'));
    await tester.pumpAndSettle();
    expect(find.text('Ana Example'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
