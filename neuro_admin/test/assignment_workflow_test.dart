import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_apply_test.dart' show FakeMutations, receipt;
import 'assignment_highlight_test.dart' show selected;
import 'assignment_preview_test.dart'
    show PreviewReader, chooseRole, chooseDoctor, selectDates;
import 'workspace_test.dart' show display;

void main() {
  testWidgets(
    'inactive physicians are hidden in overview and assignment lists',
    (tester) async {
      await display(
        tester,
        RosterDashboard(
          reader: PreviewReader(previewFixture(inactive: {'ben'})),
          onSignOut: () async {},
        ),
      );
      expect(find.byKey(const ValueKey('candidate-ben')), findsNothing);
      expect(find.textContaining('(inactive)'), findsNothing);
      await chooseRole(tester, ambulance);
      expect(find.byKey(const ValueKey('candidate-ben')), findsNothing);
      expect(find.byKey(const ValueKey('candidate-ana')), findsOneWidget);
    },
  );

  testWidgets(
    'days then role then physician assigns exactly the chosen ambulance dates',
    (tester) async {
      final mutations = FakeMutations()..handler = (r) async => receipt(r);
      await display(
        tester,
        RosterDashboard(
          reader: PreviewReader(
            previewFixture(
              contentVersion: 1,
              slots: [
                for (var day = 1; day <= 3; day++) duty(day, role: ambulance),
              ],
            ),
          ),
          mutations: mutations,
          onSignOut: () async {},
        ),
      );
      await selectDates(tester, 1);
      await selectDates(tester, 3);
      final chosen = {DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 3)};
      expect(selected(tester), chosen);
      await chooseRole(tester, ambulance);
      expect(selected(tester), chosen);
      await chooseDoctor(tester, 'ana');
      expect(selected(tester), chosen);
      expect(find.textContaining('assignable |'), findsNothing);
      await tester.tap(find.text('Apply assignments'));
      await tester.pumpAndSettle();
      expect(find.text('2026-10-01, 2026-10-03'), findsOneWidget);
      await tester.tap(find.text('Confirm and apply'));
      await tester.pumpAndSettle();
      expect(mutations.calls, hasLength(1));
      expect(mutations.calls.single.preview.request.roleId, ambulance.id);
      expect(
        mutations.calls.single.preview.request.targets.map((t) => t.date),
        [HospitalDate(2026, 10, 1), HospitalDate(2026, 10, 3)],
      );
    },
  );

  testWidgets(
    'unavailable selected dates block assignment and Available uses the chosen days',
    (tester) async {
      final physician = ana(
        absences: [
          AvailabilityPeriod(
            start: DateTime.utc(2026, 10, 2),
            end: DateTime.utc(2026, 10, 2),
            type: AvailabilityType.vacation,
          ),
        ],
      );
      final mutations = FakeMutations();
      await display(
        tester,
        RosterDashboard(
          reader: PreviewReader(
            previewFixture(
              contentVersion: 1,
              doctors: [physician],
              slots: [
                for (var day = 1; day <= 3; day++) duty(day, role: ambulance),
              ],
            ),
          ),
          mutations: mutations,
          onSignOut: () async {},
        ),
      );
      await selectDates(tester, 1);
      await selectDates(tester, 2);
      await chooseRole(tester, ambulance);
      await chooseDoctor(tester, 'ana');
      expect(selected(tester), {
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 2),
      });
      final preview = tester
          .widget<AssignmentPreviewDetails>(
            find.byType(AssignmentPreviewDetails),
          )
          .preview;
      expect(preview.results, hasLength(2));
      expect(preview.blockedCount, 1);
      expect(
        preview.results.last.errors.map((e) => e.code),
        contains(AssignmentErrorCode.blockingAbsence),
      );
      final apply = find.widgetWithText(FilledButton, 'Apply assignments');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Available'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('candidate-ana')), findsNothing);
      expect(mutations.calls, isEmpty);
      // A retained blocked target can be explicitly deselected.
      await selectDates(tester, 2);
      expect(selected(tester), {DateTime.utc(2026, 10, 1)});
      expect(find.byKey(const ValueKey('candidate-ana')), findsOneWidget);
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
