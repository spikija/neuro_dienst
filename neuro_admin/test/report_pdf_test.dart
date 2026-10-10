import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/report_pdf.dart';
import 'package:neuro_admin/report_presentation.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final orientation in ReportOrientation.values) {
    test(
      'A4 ${orientation.name} keeps all configured columns across pages',
      () async {
        final roles = [
          for (var i = 0; i < 18; i++)
            StoredRole('r$i', 'R$i', 'Report role $i'),
        ];
        final snapshot = previewFixture(roles: roles);
        final report = const FactualReportProjection().project(
          snapshot,
          ReportConfiguration(
            roles: [
              for (var i = 0; i < roles.length; i++)
                ReportRoleSetting(roles[i], i, true),
            ],
            physicianPrintOrder: {},
          ),
          ReportRequest(
            RosterVersion.unversioned('october'),
            ReportLayout.roles,
          ),
        );
        final pdf = await buildReportPdf(
          report,
          orientation,
          const AdminStrings('de'),
        );
        expect(ascii.decode(pdf.bytes.take(5).toList()), '%PDF-');
        expect(pdf.pageCount, greaterThan(1));
        final target = File('build/test-pdf/${orientation.name}.pdf');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(pdf.bytes);
        expect(
          ReportPresentation(report, const AdminStrings('de')).headings.last,
          'Abwesenheiten / Feiertag',
        );
      },
    );
  }
  test(
    'physician PDF retains inactive history and original assignment states',
    () async {
      final snapshot = previewFixture(
        contentVersion: 1,
        inactive: {'ana'},
        facts: [
          AssignmentFact(
            'a',
            ana(),
            duty(1),
            AssignmentState.provisional,
            RosterPhase.draft,
          ),
          AssignmentFact(
            'b',
            ben(),
            duty(2),
            AssignmentState.confirmed,
            RosterPhase.draft,
          ),
        ],
      );
      final report = const FactualReportProjection().project(
        snapshot,
        ReportConfiguration(
          roles: [
            const ReportRoleSetting(leader, 0, true),
            const ReportRoleSetting(ambulance, 1, false),
          ],
          physicianPrintOrder: {'ana': 0, 'ben': 1},
        ),
        ReportRequest(RosterVersion('october', 1), ReportLayout.physicians),
      );
      final original = report.rows
          .expand((r) => r.cells.values)
          .expand((c) => c.assignments)
          .map((a) => a.state)
          .toList();
      final pdf = await buildReportPdf(
        report,
        ReportOrientation.portrait,
        const AdminStrings('de'),
      );
      expect(report.columns.map((c) => c.id), contains('ana'));
      expect(original, [
        AssignmentState.provisional,
        AssignmentState.confirmed,
      ]);
      expect(
        report.rows
            .expand((r) => r.cells.values)
            .expand((c) => c.assignments)
            .map((a) => a.state),
        original,
      );
      await File('build/test-pdf/physicians.pdf').writeAsBytes(pdf.bytes);
    },
  );
}
