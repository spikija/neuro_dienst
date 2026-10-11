import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/report_pdf.dart';
import 'package:neuro_admin/report_presentation.dart';
import 'package:neuro_admin/report_print_layout.dart';
import 'package:pdf/pdf.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final orientation in ReportOrientation.values) {
    test(
      'A4 ${orientation.name} keeps all standard monthly columns on one page',
      () async {
        const names = [
          'Science Slot',
          'Stroke Unit Leader',
          'Stroke Unit Team 1',
          'Stroke Unit Team 2',
          'Ambulance',
          'Neurosonology',
          'Neurovascular Interdisciplinary Board',
          'OFO Board',
          'Other clinic',
        ];
        final roles = [
          for (var i = 0; i < names.length; i++)
            StoredRole('r$i', 'R$i', names[i]),
        ];
        final snapshot = previewFixture(
          roles: roles,
          facts: [
            for (var d = 1; d <= 31; d++)
              for (final r in roles)
                if (DateTime.utc(2026, 10, d).weekday <= 5 ||
                    (d == 3 && r == roles.last))
                  AssignmentFact(
                    'a-$d-${r.id}',
                    ana(),
                    duty(d, role: r),
                    AssignmentState.confirmed,
                    RosterPhase.draft,
                  ),
          ],
        );
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
        expect(pdf.pageCount, 1);
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
    'print layout has European dates, localized weekdays, compact weekends and holiday color',
    () {
      final layout = ReportPrintLayout(
        page: PdfPageFormat.a4,
        roleCount: 9,
        monthly: true,
      );
      expect(layout.roleWidth, (PdfPageFormat.a4.width - 36 - 78 - 68) / 9);
      expect(layout.weekendHeight, lessThan(layout.weekdayHeight));
      expect(europeanReportDate(HospitalDate(2026, 10, 5)), '05.10.2026');
      expect(reportWeekday(HospitalDate(2026, 10, 5), 'de'), 'Mo');
      expect(reportWeekday(HospitalDate(2026, 10, 5), 'en'), 'Mon');
      final holiday = ReportRow(
        HospitalDate(2026, 10, 26),
        CalendarDayInfo(
          date: DateTime.utc(2026, 10, 26),
          isWeekend: false,
          isPublicHoliday: true,
          publicHolidayName: 'Nationalfeiertag',
        ),
        {},
      );
      expect(layout.rowColor(holiday), isNot(PdfColors.white));
    },
  );
  test(
    'extreme role count gives explicit warning, never drops columns',
    () async {
      final roles = [
        for (var i = 0; i < 30; i++) StoredRole('r$i', 'R$i', 'Role $i'),
      ];
      final report = const FactualReportProjection().project(
        previewFixture(roles: roles),
        ReportConfiguration(
          roles: [for (final r in roles) ReportRoleSetting(r, 0, true)],
          physicianPrintOrder: {},
        ),
        ReportRequest(RosterVersion.unversioned('october'), ReportLayout.roles),
      );
      try {
        await buildReportPdf(
          report,
          ReportOrientation.portrait,
          const AdminStrings('de'),
        );
        fail('Expected legibility warning');
      } on ReportPrintLayoutException catch (e) {
        expect(e.message, contains('landscape'));
      }
    },
  );
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
