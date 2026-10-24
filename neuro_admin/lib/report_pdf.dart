import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'localization.dart';
import 'report_presentation.dart';
import 'report_print_layout.dart';

enum ReportOrientation { portrait, landscape }

class ReportPdf {
  final Uint8List bytes;
  final int pageCount;
  const ReportPdf(this.bytes, this.pageCount);
}

/// Pure rendering of the same factual projection as the screen. Fonts are
/// bundled, so exporting never downloads patient/staff data or font resources.
Future<ReportPdf> buildReportPdf(
  ReportDocument report,
  ReportOrientation orientation,
  AdminStrings strings, {
  Set<String>? selectedRoleIds,
}) async {
  final format = orientation == ReportOrientation.portrait
      ? PdfPageFormat.a4
      : PdfPageFormat.a4.landscape;
  final presentation = ReportPresentation(
    report,
    strings,
    selectedRoleIds: selectedRoleIds,
  );
  final columns = presentation.columns;
  if (report.request.layout == ReportLayout.roles && columns.isEmpty) {
    throw const ReportPrintLayoutException(
      'Select at least one role to export.',
    );
  }
  final roleNames = {
    for (final setting in report.configuration.roles)
      setting.role.id: setting.role.name,
  };
  final headings = report.request.layout == ReportLayout.roles
      ? [
          for (final column in columns) roleNames[column.id] ?? column.label,
          strings.text('Absences / holiday'),
        ]
      : presentation.headings;
  final values = report.rows.map(presentation.cells).toList();
  final layout = ReportPrintLayout(
    page: format,
    roleCount: columns.length,
    monthly: report.request.layout == ReportLayout.roles,
  );
  layout.validate();
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-bold.ttf'),
  );
  // Flutter's Material icon font uses CFF outlines, which the PDF font renderer
  // cannot embed. These bundled SVGs contain the same glyph outlines.
  final icons = <AvailabilityType, String>{};
  for (final type
      in report.rows
          .expand(presentation.absences)
          .expand((entry) => entry.periods)
          .map((period) => period.type)
          .where((type) => type != AvailabilityType.efDay)
          .toSet()) {
    icons[type] = await rootBundle.loadString(
      'assets/icons/absence_${type.name}.svg',
    );
  }

  Future<ReportPdf> render(double fontScale, {bool compactRows = false}) async {
    final layout = ReportPrintLayout(
      page: format,
      roleCount: columns.length,
      monthly: report.request.layout == ReportLayout.roles,
      fontScale: fontScale,
      compactRows: compactRows,
    );
    final perBand = layout.monthly
        ? headings.length
        : ((format.width - 48 - 72) / 120).floor().clamp(1, 100);
    final pdf = pw.Document(
      title: presentation.title,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    for (var start = 0; start < headings.length; start += perBand) {
      final end = (start + perBand).clamp(0, headings.length);
      pw.TextSpan absenceText(
        List<ReportAbsenceEntry> entries, {
        String? holiday,
      }) => pw.TextSpan(
        children: [
          if (holiday != null) pw.TextSpan(text: holiday),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0 || holiday != null) const pw.TextSpan(text: '\n'),
            pw.TextSpan(text: entries[i].surname),
            for (final period in entries[i].periods) ...[
              const pw.TextSpan(text: ' '),
              if (period.type == AvailabilityType.efDay)
                const pw.TextSpan(text: 'EF')
              else
                pw.WidgetSpan(
                  baseline: -layout.fontSize * 0.15,
                  child: pw.SvgImage(
                    svg: icons[period.type]!,
                    width: layout.fontSize,
                    height: layout.fontSize,
                  ),
                ),
            ],
          ],
        ],
      );
      pw.Widget cell(
        String value, {
        bool heading = false,
        ReportRow? row,
        double? fontSize,
        List<ReportAbsenceEntry>? absences,
        String? holiday,
      }) => pw.Container(
        constraints: row == null
            ? null
            : pw.BoxConstraints(minHeight: layout.minimumRowHeight(row)),
        padding: pw.EdgeInsets.symmetric(
          horizontal: layout.horizontalPadding,
          vertical: row == null ? 3 : layout.verticalPadding(row),
        ),
        child: pw.RichText(
          text: pw.TextSpan(
            style: pw.TextStyle(
              fontSize: fontSize ?? layout.fontSize,
              fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
            children: [
              if (absences == null)
                pw.TextSpan(text: value)
              else
                absenceText(absences, holiday: holiday),
            ],
          ),
        ),
      );
      pdf.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: pw.EdgeInsets.all(layout.margin),
          maxPages: 1000,
          header: (_) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              presentation.title,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              strings.text('Page {page} of {total}', {
                'page': context.pageNumber,
                'total': context.pagesCount,
              }),
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          build: (_) => [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
              columnWidths: {
                0: pw.FixedColumnWidth(layout.dateWidth),
                if (layout.monthly) ...{
                  for (var c = 1; c <= columns.length; c++)
                    c: pw.FixedColumnWidth(layout.roleWidth),
                  columns.length + 1: pw.FixedColumnWidth(layout.notesWidth),
                },
              },
              defaultColumnWidth: const pw.FlexColumnWidth(),
              children: [
                pw.TableRow(
                  repeat: true,
                  decoration: const pw.BoxDecoration(
                    color: ReportPrintLayout.headerColor,
                  ),
                  children: [
                    cell(
                      strings.text('Date'),
                      heading: true,
                      fontSize: layout.dateFontSize,
                    ),
                    for (var c = start; c < end; c++)
                      cell(headings[c], heading: true),
                  ],
                ),
                for (var r = 0; r < report.rows.length; r++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: layout.rowColor(report.rows[r]),
                    ),
                    children: [
                      pw.Container(
                        constraints: pw.BoxConstraints(
                          minHeight: layout.minimumRowHeight(report.rows[r]),
                        ),
                        padding: pw.EdgeInsets.symmetric(
                          horizontal: 1,
                          vertical: layout.verticalPadding(report.rows[r]),
                        ),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              child: pw.Text(
                                europeanReportDate(report.rows[r].date),
                                style: pw.TextStyle(
                                  fontSize: layout.dateFontSize,
                                ),
                              ),
                            ),
                            pw.SizedBox(
                              width: 22,
                              child: pw.Text(
                                reportWeekday(
                                  report.rows[r].date,
                                  strings.language,
                                ),
                                style: pw.TextStyle(
                                  fontSize: layout.dateFontSize,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var c = start; c < end; c++)
                        cell(
                          values[r][c],
                          row: report.rows[r],
                          absences: c == columns.length
                              ? presentation.absences(report.rows[r])
                              : report.request.layout ==
                                        ReportLayout.physicians &&
                                    report
                                        .rows[r]
                                        .cells[columns[c].id]!
                                        .absencesByPhysician
                                        .isNotEmpty
                              ? presentation.cellAbsences(
                                  report.rows[r].cells[columns[c].id]!,
                                )
                              : null,
                          holiday:
                              c == columns.length &&
                                  report.rows[r].calendar.publicHolidayName !=
                                      null
                              ? presentation.holiday(
                                  report.rows[r].calendar.publicHolidayName!,
                                )
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
    }
    final bytes = await pdf.save();
    final pages = pdf.document.pdfPageList.pages.length;
    return ReportPdf(bytes, pages);
  }

  // Prefer larger text, using tighter row spacing before reducing the font.
  // Every attempt retains all columns and cell text.
  for (final scale
      in layout.monthly ? const [1.2, 1.15, 1.1, 1.05, 1.0] : const [1.2]) {
    final result = await render(scale);
    if (!layout.monthly || result.pageCount == 1) return result;
    final compact = await render(scale, compactRows: true);
    if (compact.pageCount == 1) return compact;
  }
  throw const ReportPrintLayoutException(
    'This month contains too much text for one readable page. Choose another orientation or reduce configured report columns.',
  );
}
