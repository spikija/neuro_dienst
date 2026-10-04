import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/personal_roster_report_screen.dart';
import 'package:neuro_app/services/personal_roster_report.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const l10n = AppLocalizations(
    language: AppLanguage.english,
    child: SizedBox(),
  );

  test(
    'personal rows include every day and only the requested doctor duties',
    () {
      final roster = DemoRoster.createJune2026();
      final assignedDoctor = DemoRoster.createOtherDoctor();
      final rows = personalRosterRows(roster, assignedDoctor, l10n);
      expect(rows, hasLength(30));
      expect(rows.first.take(2), ['1.6.', 'Mon']);
      final roles = roster.days.first.assignments.map(
        (assignment) => assignment.slot.template.name,
      );
      for (final role in roles) {
        expect(rows.first.last, contains(role));
      }
      expect(rows.last.first, '30.6.');
      expect(rows.skip(1).every((row) => row.last.isEmpty), isTrue);

      final unassignedRows = personalRosterRows(
        roster,
        DemoRoster.createCurrentDoctor(),
        l10n,
      );
      expect(unassignedRows.every((row) => row.last.isEmpty), isTrue);
      expect(rows.every((row) => row.length == 3), isTrue);
    },
  );

  test(
    'PDF generates offline with bundled fonts and a German doctor name',
    () async {
      final bytes = await buildPersonalRosterPdf(
        roster: DemoRoster.createJune2026(),
        doctor: DemoRoster.createOtherDoctor(),
        l10n: const AppLocalizations(
          language: AppLanguage.german,
          child: SizedBox(),
        ),
        format: PdfPageFormat.a4,
      );
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    },
  );

  testWidgets('missing account doctor cannot fall back to another doctor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            AppLocalizations(language: AppLanguage.english, child: child!),
        home: PersonalRosterReportScreen(
          roster: DemoRoster.createJune2026(),
          doctors: DemoRoster.createDoctors(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No active doctor profile is linked to your account.'),
      findsOneWidget,
    );
    expect(find.byType(PdfPreview), findsNothing);
  });
}
