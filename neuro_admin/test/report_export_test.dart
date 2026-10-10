import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/report_export.dart';
import 'package:neuro_admin/report_pdf.dart';
import 'package:neuro_admin/reports_screen.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'workspace_test.dart' show TestWorkspace, display;

class FakeExport implements ReportExportService {
  final calls = <(ReportDocument, ReportOrientation, bool)>[];
  @override
  Future<void> export(
    ReportDocument report,
    ReportOrientation orientation,
    AdminStrings strings, {
    required bool print,
  }) async {
    calls.add((report, orientation, print));
  }
}

void main() {
  for (final print in [false, true]) {
    testWidgets(
      'export dialog forwards orientation and ${print ? 'print' : 'save'} to platform adapter',
      (tester) async {
        final exporter = FakeExport();
        await display(
          tester,
          ReportsScreen(
            service: TestWorkspace(),
            roster: RosterVersion('october', 1),
            exporter: exporter,
          ),
        );
        await tester.tap(find.byTooltip('Print / PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('A4 Landscape'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, print ? 'Print' : 'Save PDF'),
        );
        await tester.pumpAndSettle();
        expect(exporter.calls.single.$2, ReportOrientation.landscape);
        expect(exporter.calls.single.$3, print);
        expect(exporter.calls.single.$1.request.roster.rosterId, 'october');
        expect(find.byType(ReportExportDialog), findsNothing);
      },
    );
  }
}
