import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_highlight_test.dart' show showDashboard;
import 'assignment_preview_test.dart' show PreviewReader, selectDates;

void main() {
  for (final size in [const Size(1440, 900), const Size(1920, 1080)]) {
    testWidgets('ten scheduled roles fit without scrolling at $size', (
      tester,
    ) async {
      final roles = [
        for (var i = 0; i < 10; i++)
          StoredRole(
            'role$i',
            'R$i',
            'Department role $i',
            displayOrder: i,
            isActive: true,
          ),
      ];
      final snapshot = previewFixture(
        roles: roles,
        slots: [for (final role in roles) duty(2, role: role)],
      );
      await showDashboard(tester, PreviewReader(snapshot));
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await selectDates(tester, 2);
      final pane = tester.getRect(
        find.byKey(const ValueKey('daily-roster-pane')),
      );
      for (final role in roles) {
        final row = find.byKey(ValueKey('daily-role-${role.id}'));
        final bounds = tester.getRect(row);
        expect(bounds.height, lessThanOrEqualTo(76));
        expect(bounds.top, greaterThanOrEqualTo(pane.top));
        expect(bounds.bottom, lessThanOrEqualTo(pane.bottom));
        expect(
          find.descendant(of: row, matching: find.text('0/1')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'compact unscheduled row remains clickable and identifies exact role',
    (tester) async {
      await showDashboard(tester, PreviewReader(previewFixture()));
      await selectDates(tester, 1);
      final row = find.byKey(const ValueKey('daily-role-amb'));
      expect(tester.getSize(row).height, lessThanOrEqualTo(36));
      expect(
        find.descendant(of: row, matching: find.text('Not scheduled')),
        findsOneWidget,
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssignmentCandidatePanel>(
              find.byType(AssignmentCandidatePanel),
            )
            .role
            .id,
        ambulance.id,
      );
      final scheduled = find.byKey(const ValueKey('daily-role-sul'));
      await tester.tap(scheduled);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssignmentCandidatePanel>(
              find.byType(AssignmentCandidatePanel),
            )
            .role
            .id,
        leader.id,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
