import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/report_table.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_preview_test.dart' show PreviewReader;
import 'workspace_test.dart' show display;

void main() {
  for (final size in [
    const Size(1280, 720),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('frozen report panes and reachable final column at $size', (
      tester,
    ) async {
      final roles = [
        for (var n = 0; n < 20; n++) StoredRole('r$n', 'R$n', 'Role $n'),
      ];
      final report = const FactualReportProjection().project(
        previewFixture(roles: roles),
        ReportConfiguration(
          roles: [
            for (var n = 0; n < roles.length; n++)
              ReportRoleSetting(roles[n], n, true),
          ],
          physicianPrintOrder: {},
        ),
        ReportRequest(
          RosterVersion.unversioned('october'),
          ReportLayout.roles,
        ),
      );
      await display(tester, ReportTable(report: report));
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final corner = tester.getRect(
        find.byKey(const ValueKey('report-corner')),
      );
      final firstDate = tester.getRect(
        find.byKey(const ValueKey('report-date-0')),
      );
      final body = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('report-body')),
      );
      body.controller!.jumpTo(body.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('report-date-0'))),
        firstDate,
      );
      final last = tester.getRect(
        find.byKey(const ValueKey('report-cell-0-20')),
      );
      expect(last.right, lessThanOrEqualTo(size.width));
      expect(last.left, greaterThanOrEqualTo(corner.right));
      final header = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('report-header')),
      );
      expect(header.controller!.offset, body.controller!.offset);
      final vertical = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .singleWhere((w) => w.scrollDirection == Axis.vertical);
      vertical.controller!.jumpTo(
        vertical.controller!.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('report-corner'))),
        corner,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('calendar rows grow with available pane height', (tester) async {
    await display(
      tester,
      RosterDashboard(
        reader: PreviewReader(previewFixture()),
        onSignOut: () async {},
      ),
    );
    final initial = tester.getSize(find.byType(CalendarDayGrid));
    tester.view.physicalSize = const Size(1440, 1080);
    await tester.pumpAndSettle();
    final expanded = tester.getSize(find.byType(CalendarDayGrid));
    expect(expanded.height - initial.height, closeTo(180, 1));
    expect(tester.takeException(), isNull);
  });
}

