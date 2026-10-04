import 'package:flutter/services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_localizations.dart';

/// All assignments count, including roles hidden from the department report.
/// An absence must never obscure an assigned duty.
List<List<String>> personalRosterRows(
  RosterMonth roster,
  Doctor doctor,
  AppLocalizations l10n,
) {
  const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final days = [...roster.days]..sort((a, b) => a.date.compareTo(b.date));
  return [
    for (final day in days)
      [
        '${day.date.day}.${day.date.month}.',
        l10n.t('weekday.${weekdays[day.date.weekday - 1]}'),
        (day.assignments
                .where((assignment) => assignment.doctor.id == doctor.id)
                .map((assignment) => assignment.slot.template.name)
                .toSet()
                .toList()
              ..sort())
            .join(', '),
      ],
  ];
}

Future<Uint8List> buildPersonalRosterPdf({
  required RosterMonth roster,
  required Doctor doctor,
  required AppLocalizations l10n,
  required PdfPageFormat format,
}) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-bold.ttf'),
  );
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Text(
          '${l10n.t('myDuties')} — ${l10n.t('month.${roster.month}')} ${roster.year}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ),
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: [l10n.t('reportDate'), l10n.t('reportDay'), doctor.fullName],
          data: personalRosterRows(roster, doctor, l10n),
          columnWidths: {
            0: const pw.FixedColumnWidth(44),
            1: const pw.FixedColumnWidth(36),
            2: const pw.FlexColumnWidth(),
          },
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellPadding: const pw.EdgeInsets.all(4),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        ),
      ],
    ),
  );
  return document.save();
}
