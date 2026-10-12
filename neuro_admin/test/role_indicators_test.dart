import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/role_indicators.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final square in [false, true]) {
    test(
      'outlined, partial and filled markers paint correctly (square=$square)',
      () async {
        for (final state in RoleStaffingState.values) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          const color = Color(0xff1565c0);
          RoleStatusPainter(
            state,
            color,
            square: square,
          ).paint(canvas, const Size(32, 32));
          final picture = recorder.endRecording();
          final image = await picture.toImage(32, 32);
          final bytes = (await image.toByteData())!;
          int alpha(int x, int y) => bytes.getUint8((y * 32 + x) * 4 + 3);
          expect(
            alpha(8, 16),
            state == RoleStaffingState.staffed ? greaterThan(200) : 0,
          );
          expect(
            alpha(24, 16),
            state == RoleStaffingState.staffed ||
                    state == RoleStaffingState.partial
                ? greaterThan(200)
                : 0,
          );
          // A box has a visible top-left corner; a circle does not.
          expect(alpha(2, 2), square ? greaterThan(0) : 0);
          image.dispose();
          picture.dispose();
        }
      },
    );
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      'stable ordered custom-role indicators and readable colors in $brightness',
      (tester) async {
        const custom = StoredRole(
          'custom',
          'ANY',
          'Any department',
          colorKey: 'teal',
          displayOrder: -1,
          isActive: true,
        );
        final snap = previewFixture(roles: [leader, custom, icb]);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SizedBox(
                width: 80,
                height: 64,
                child: CalendarRoleIndicators(
                  roles: calendarRoles(snap),
                  day: snap.days.first,
                ),
              ),
            ),
          ),
        );
        final indicators = tester
            .widgetList<RoleStatusIndicator>(find.byType(RoleStatusIndicator))
            .toList();
        expect(indicators.map((i) => i.staffing.role.id), [
          'custom',
          'amb',
          'icb',
          'sul',
        ]);
        final empty = indicators.firstWhere(
          (i) => i.staffing.role.id == 'custom',
        );
        expect(empty.staffing.state, RoleStaffingState.unscheduled);
        final painter =
            tester
                    .widgetList<CustomPaint>(
                      find.descendant(
                        of: find.byKey(const ValueKey('role-status-custom')),
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .single
                    .painter!
                as RoleStatusPainter;
        expect(
          painter.color,
          brightness == Brightness.dark
              ? const Color(0xffbdbdbd)
              : const Color(0xff616161),
        );
        final background = brightness == Brightness.dark
            ? const Color(0xff121212)
            : Colors.white;
        for (final color in rolePalette) {
          final actual = Color(
            brightness == Brightness.dark ? color.darkArgb : color.lightArgb,
          );
          final a = actual.computeLuminance(),
              b = background.computeLuminance();
          final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
          expect(ratio, greaterThanOrEqualTo(3), reason: color.key);
        }
      },
    );
  }
  testWidgets(
    'two columns keep row-major order and role tooltips across dates',
    (tester) async {
      final snapshot = previewFixture();
      final roles = calendarRoles(snapshot);
      for (final day in snapshot.days.take(3)) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 80,
                height: 64,
                child: CalendarRoleIndicators(roles: roles, day: day),
              ),
            ),
          ),
        );
        final markers = roles
            .map((role) => find.byKey(ValueKey('role-status-${role.id}')))
            .toList();
        final positions = markers.map(tester.getTopLeft).toList();
        expect(positions[0].dy, positions[1].dy);
        expect(positions[1].dx - positions[0].dx, 14);
        expect(positions[2].dx, positions[0].dx);
        expect(positions[2].dy - positions[0].dy, 14);
        for (var i = 0; i < roles.length; i++) {
          final tooltip = tester.widget<Tooltip>(
            find.descendant(of: markers[i], matching: find.byType(Tooltip)),
          );
          expect(
            tooltip.message,
            roleStaffingLabel(
              tester.element(markers[i]),
              RoleStaffing.forDay(roles[i], day),
            ),
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets('overflow exposes every remaining role in its tooltip', (
    tester,
  ) async {
    final roles = [
      for (var i = 0; i < 20; i++) StoredRole('r$i', 'R$i', 'Role $i'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 28,
            height: 28,
            child: CalendarRoleIndicators(roles: roles, day: null),
          ),
        ),
      ),
    );
    final messages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message!)
        .join('\n');
    for (var i = 0; i < 20; i++) {
      expect(messages, contains('Role $i - not scheduled'));
    }
    expect(find.textContaining('+'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
