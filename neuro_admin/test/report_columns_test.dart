import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/report_pdf.dart';
import 'package:neuro_admin/report_presentation.dart';
import 'package:neuro_admin/report_print_preferences.dart';
import 'package:neuro_admin/report_print_layout.dart';
import 'package:neuro_admin/reports_screen.dart';
import 'package:neuro_admin/report_table.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'report_export_test.dart' show FakeExport;
import 'workspace_test.dart' show display;

const custom = StoredRole('custom', 'CUSTOM', 'Custom Clinic');
const rare = StoredRole('rare', 'RARE', 'Rare Board');
const hidden = StoredRole('hidden', 'HIDDEN', 'Hidden Default');
ReportDocument columnsFixture() => const FactualReportProjection().project(
  previewFixture(
    roles: [custom, rare, hidden],
    slots: [duty(2, role: custom)],
    facts: [
      AssignmentFact(
        'historic',
        ana(),
        duty(3, role: hidden),
        AssignmentState.confirmed,
        RosterPhase.draft,
      ),
    ],
  ),
  ReportConfiguration(
    roles: [
      const ReportRoleSetting(rare, 2, true),
      const ReportRoleSetting(custom, 0, true),
      const ReportRoleSetting(hidden, 1, false),
    ],
    physicianPrintOrder: {},
  ),
  ReportRequest(RosterVersion.unversioned('october'), ReportLayout.roles),
);

class ColumnReports implements ReportingService {
  @override
  Future<ReportDocument> load(ReportRequest request) async => columnsFixture();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'preferences restore deselection, ignore deleted IDs and apply new defaults',
    () async {
      final report = columnsFixture();
      const store = ReportPrintPreferences();
      expect(await store.restore(report), {'custom', 'rare'});
      SharedPreferences.setMockInitialValues({
        ReportPrintPreferences.key: '{"custom":false,"deleted":true}',
      });
      expect(await store.restore(report), {'rare'});
      await store.save(report, {'hidden'});
      expect(await const ReportPrintPreferences().restore(columnsFixture()), {
        'hidden',
      });
      SharedPreferences.setMockInitialValues({
        ReportPrintPreferences.key: 'broken JSON',
      });
      expect(await store.restore(report), {'custom', 'rare'});
    },
  );

  test(
    'used roles include slots and assignment-only facts; selection preserves configured order',
    () {
      final report = columnsFixture();
      expect(usedReportRoleIds(report), {'custom', 'hidden'});
      final presentation = ReportPresentation(
        report,
        const AdminStrings('en'),
        selectedRoleIds: {'hidden', 'custom', 'deleted'},
      );
      expect(presentation.columns.map((c) => c.id), ['custom', 'hidden']);
      expect(report.columns.map((c) => c.id), ['custom', 'rare']);
    },
  );

  testWidgets(
    'all, none and used selections validate and leave screen columns unchanged',
    (tester) async {
      final exporter = FakeExport();
      await display(
        tester,
        ReportsScreen(
          service: ColumnReports(),
          roster: RosterVersion.unversioned('october'),
          exporter: exporter,
        ),
      );
      await tester.tap(find.byTooltip('Print / PDF'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 roles'), findsOneWidget);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .map((w) => w.key),
        [
          const ValueKey('print-role-custom'),
          const ValueKey('print-role-hidden'),
          const ValueKey('print-role-rare'),
        ],
      );
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('3 of 3 roles'), findsOneWidget);
      await tester.tap(find.text('Select none'));
      await tester.pumpAndSettle();
      expect(find.text('Select at least one role to export.'), findsOneWidget);
      for (final label in ['Print', 'Save PDF']) {
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, label))
              .onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Preview'))
            .onPressed,
        isNull,
      );
      expect(exporter.calls, isEmpty);
      await tester.tap(find.text('Only roles used this month'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 roles'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save PDF'));
      await tester.pumpAndSettle();
      expect(exporter.selections.single, {'custom', 'hidden'});
      expect(
        tester
            .widget<ReportTable>(find.byType(ReportTable))
            .report
            .columns
            .map((c) => c.id),
        ['custom', 'rare'],
      );
      await tester.tap(find.byTooltip('Print / PDF'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('print-role-rare')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('print-role-hidden')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.text('Select none'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await const ReportPrintPreferences().restore(columnsFixture()), {
        'custom',
        'hidden',
      });
    },
  );

  for (final orientation in ReportOrientation.values) {
    test(
      'selected custom columns render one-page ${orientation.name} PDF',
      () async {
        final report = columnsFixture();
        final pdf = await buildReportPdf(
          report,
          orientation,
          const AdminStrings('de'),
          selectedRoleIds: {'hidden', 'custom'},
        );
        expect(pdf.pageCount, 1);
        final target = File('build/test-pdf/selected-${orientation.name}.pdf');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(pdf.bytes);
        final all = await buildReportPdf(
          report,
          orientation,
          const AdminStrings('de'),
          selectedRoleIds: report.availableRoleColumns.map((c) => c.id).toSet(),
        );
        expect(all.pageCount, 1);
        await expectLater(
          buildReportPdf(
            report,
            orientation,
            const AdminStrings('de'),
            selectedRoleIds: {},
          ),
          throwsA(isA<ReportPrintLayoutException>()),
        );
      },
    );
  }
}
