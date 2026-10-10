import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'localization.dart';
import 'report_presentation.dart';

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
  AdminStrings strings,
) async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-bold.ttf'),
  );
  final format = orientation == ReportOrientation.portrait
      ? PdfPageFormat.a4
      : PdfPageFormat.a4.landscape;
  final presentation = ReportPresentation(report, strings);
  final headings = presentation.headings;
  final values = report.rows.map(presentation.cells).toList();
  final perBand = ((format.width - 48 - 72) / 120).floor().clamp(1, 100);
  final pdf = pw.Document(
    title: presentation.title,
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );
  for (var start = 0; start < headings.length; start += perBand) {
    final end = (start + perBand).clamp(0, headings.length);
    pw.Widget cell(String value, {bool heading = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
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
            columnWidths: {0: const pw.FixedColumnWidth(72)},
            defaultColumnWidth: const pw.FlexColumnWidth(),
            children: [
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell(strings.text('Date'), heading: true),
                  for (var c = start; c < end; c++)
                    cell(headings[c], heading: true),
                ],
              ),
              for (var r = 0; r < report.rows.length; r++)
                pw.TableRow(
                  children: [
                    cell('${report.rows[r].date}'),
                    for (var c = start; c < end; c++) cell(values[r][c]),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
  final bytes = await pdf.save();
  return ReportPdf(bytes, pdf.document.pdfPageList.pages.length);
}
