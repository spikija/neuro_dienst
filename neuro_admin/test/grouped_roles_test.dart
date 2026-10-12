import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/role_indicators.dart';
import 'package:neuro_admin/assignment_candidate_panel.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_highlight_test.dart' show showDashboard;
import 'assignment_preview_test.dart' show PreviewReader, selectDates;

const groupedRoles = [
  StoredRole(
    's2',
    'CUSTOM',
    'Custom stationary',
    group: RoleGroup.stationary,
    displayOrder: 2,
  ),
  StoredRole('a3', 'OTHER', 'Other role', displayOrder: 3),
  StoredRole(
    's1',
    'WARD',
    'Ward',
    group: RoleGroup.stationary,
    displayOrder: 1,
  ),
  // Codes do not override administrator configuration.
  StoredRole('a1', 'SUL', 'Configured ambulatory', displayOrder: 1),
  StoredRole(
    's3',
    'INPATIENT',
    'Inpatient',
    group: RoleGroup.stationary,
    displayOrder: 3,
  ),
  StoredRole('a2', 'CLINIC', 'Clinic', displayOrder: 2),
];

void main() {
  testWidgets(
    'stationary circles stack left; other markers form an ordered two-column grid',
    (tester) async {
      final snapshot = previewFixture(
        roles: groupedRoles,
        slots: [duty(1, role: groupedRoles.first)],
      );
      for (final day in snapshot.days.take(2)) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 44,
                height: 64,
                child: CalendarRoleIndicators(roles: groupedRoles, day: day),
              ),
            ),
          ),
        );
        Offset position(String id) =>
            tester.getTopLeft(find.byKey(ValueKey('role-status-$id')));
        expect(position('s1').dx, position('s2').dx);
        expect(position('s2').dx, position('s3').dx);
        expect(position('s2').dy - position('s1').dy, 14);
        expect(position('s3').dy - position('s2').dy, 14);
        expect(position('a1').dx, greaterThan(position('s1').dx));
        expect(position('a1').dy, position('s1').dy);
        expect(position('a2').dy, position('a1').dy);
        expect(position('a2').dx - position('a1').dx, 14);
        expect(position('a3').dx, position('a1').dx);
        expect(position('a3').dy - position('a1').dy, 14);
        expect(
          tester
              .widgetList<RoleStatusIndicator>(find.byType(RoleStatusIndicator))
              .map((w) => w.staffing.role.id),
          ['s1', 's2', 's3', 'a1', 'a2', 'a3'],
        );
        for (final role in groupedRoles) {
          final marker = find.byKey(ValueKey('role-status-${role.id}'));
          final indicator = tester.widget<RoleStatusIndicator>(marker);
          expect(
            indicator.staffing.state,
            RoleStaffing.forDay(role, day).state,
          );
          expect(
            tester
                .widget<Tooltip>(
                  find.descendant(of: marker, matching: find.byType(Tooltip)),
                )
                .message,
            roleStaffingLabel(
              tester.element(marker),
              RoleStaffing.forDay(role, day),
            ),
          );
          expect(
            tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: marker,
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter,
            isA<RoleStatusPainter>(),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'daily roster keeps ordered sections, grey unscheduled roles and exact click identity',
    (tester) async {
      await showDashboard(
        tester,
        PreviewReader(
          previewFixture(
            roles: groupedRoles,
            slots: [duty(1, role: groupedRoles.first)],
          ),
        ),
      );
      for (final day in [1, 2]) {
        await selectDates(tester, day);
        final keys = [
          'daily-role-group-stationary',
          'daily-role-s1',
          'daily-role-s2',
          'daily-role-s3',
          'daily-role-group-ambulatory',
          'daily-role-a1',
          'daily-role-a2',
          'daily-role-a3',
        ];
        final positions = keys
            .map((key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy)
            .toList();
        expect(positions, orderedEquals([...positions]..sort()));
        expect(find.text('Stationary'), findsOneWidget);
        expect(find.text('Ambulatory / Other'), findsOneWidget);
        final row = find.byKey(const ValueKey('daily-role-a1'));
        expect(
          find.descendant(of: row, matching: find.text('Not scheduled')),
          findsOneWidget,
        );
        final marker = tester.widget<RoleStatusIndicator>(
          find.descendant(of: row, matching: find.byType(RoleStatusIndicator)),
        );
        expect(marker.staffing.state, RoleStaffingState.unscheduled);
      }
      await tester.tap(find.byKey(const ValueKey('daily-role-s2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AssignmentCandidatePanel>(
              find.byType(AssignmentCandidatePanel),
            )
            .role
            .id,
        's2',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
