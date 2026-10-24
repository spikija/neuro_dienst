import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/absence_icons.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/report_pdf.dart';
import 'package:neuro_admin/report_presentation.dart';
import 'package:neuro_admin/report_table.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import '../../neuro_admin_services/test/support/preview_fixture.dart';

final absenceTypes = AvailabilityType.values
    .where(
      (t) => t != AvailabilityType.available && t != AvailabilityType.duty24,
    )
    .toList();

ReportDocument absenceReport(ReportLayout layout) {
  final doctors = [
    Doctor(
      id: 'johanna',
      firstName: 'Johanna',
      lastName: 'von Mayrhofer',
      rank: DoctorRank.consultant,
      availabilities: [
        for (var i = 0; i < absenceTypes.length; i++)
          AvailabilityPeriod(
            start: DateTime.utc(2026, 10, i + 1),
            end: DateTime.utc(2026, 10, i + 1),
            type: absenceTypes[i],
          ),
      ],
    ),
    Doctor(
      id: 'max',
      firstName: 'Max',
      lastName: 'von Mayrhofer',
      rank: DoctorRank.resident,
      availabilities: [
        AvailabilityPeriod(
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 1),
          type: AvailabilityType.sickLeave,
        ),
      ],
    ),
  ];
  final roles = [
    for (var i = 0; i < 9; i++) StoredRole('r$i', 'R$i', 'Full role name $i'),
  ];
  return const FactualReportProjection().project(
    previewFixture(doctors: doctors, roles: roles),
    ReportConfiguration(
      roles: [
        for (var i = 0; i < roles.length; i++)
          ReportRoleSetting(roles[i], i, true),
      ],
      physicianPrintOrder: {},
    ),
    ReportRequest(RosterVersion.unversioned('october'), layout),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('absence surnames preserve compound names and physician identities', () {
    final report = absenceReport(ReportLayout.roles);
    final presentation = ReportPresentation(report, const AdminStrings('de'));
    expect(report.physicianSurnames['johanna'], 'von Mayrhofer');
    final entries = presentation.absences(report.rows.first);
    // Each role repeats the same underlying absences; each physician appears once.
    expect(entries, hasLength(2));
    expect(entries.map((e) => e.surname), ['von Mayrhofer', 'von Mayrhofer']);
    expect(
      entries.expand((e) => e.periods).map((p) => p.type),
      containsAll([AvailabilityType.vacation, AvailabilityType.sickLeave]),
    );
    expect(
      presentation.cells(report.rows.first).last,
      'von Mayrhofer\nvon Mayrhofer',
    );
    expect(presentation.cells(report.rows[25]).last, 'Nationalfeiertag');
  });

  for (final language in ['de', 'en']) {
    for (final layout in [ReportLayout.roles, ReportLayout.physicians]) {
      testWidgets('$language ${layout.name} shows surnames and icon glyphs', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final report = absenceReport(layout);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.7)),
              child: child!,
            ),
            home: Scaffold(body: ReportTable(report: report)),
          ),
        );
        await tester.pumpAndSettle();
        String cellText(int row, int column) => tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(ValueKey('report-cell-$row-$column')),
                matching: find.byType(Text),
              ),
            )
            .textSpan!
            .toPlainText(includeSemanticsLabels: false);

        for (var i = 0; i < absenceTypes.length; i++) {
          final text = cellText(i, report.columns.length);
          final type = absenceTypes[i];
          expect(text, contains('von Mayrhofer'));
          expect(text, isNot(contains('Johanna')));
          expect(text, isNot(contains('Max')));
          expect(
            text,
            contains(
              type == AvailabilityType.efDay
                  ? 'EF'
                  : String.fromCharCode(absenceIcon(type).codePoint),
            ),
          );
          expect(text, isNot(contains('Urlaub')));
          expect(text, isNot(contains('Krankenstand')));
        }
        if (layout == ReportLayout.physicians) {
          expect(cellText(0, 0), contains('von Mayrhofer'));
          expect(cellText(0, 0), isNot(contains('Vacation')));
          expect(cellText(0, 0), isNot(contains('Urlaub')));
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final orientation in ReportOrientation.values) {
      test(
        '$language ${orientation.name} PDF embeds every absence icon',
        () async {
          final report = absenceReport(ReportLayout.roles);
          final pdf = await buildReportPdf(
            report,
            orientation,
            AdminStrings(language),
          );
          expect(pdf.pageCount, 1);
          final target = File(
            'build/test-pdf/absences-$language-${orientation.name}.pdf',
          );
          await target.parent.create(recursive: true);
          await target.writeAsBytes(pdf.bytes);
        },
      );
    }
  }
}
