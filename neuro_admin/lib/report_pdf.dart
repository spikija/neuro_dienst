import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:neuro_admin_services/neuro_admin_services.dart';
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
  AdminStrings strings,
) async {
  final format = orientation == ReportOrientation.portrait
      ? PdfPageFormat.a4
      : PdfPageFormat.a4.landscape;
  final presentation = ReportPresentation(report, strings);
  final headings = presentation.headings;
  final values = report.rows.map(presentation.cells).toList();
  final layout = ReportPrintLayout(
    page: format,
    roleCount: report.columns.length,
    monthly: report.request.layout == ReportLayout.roles,
  );
  layout.validate();
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/roboto-bold.ttf'),
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
    pw.Widget cell(String value, {bool heading = false, ReportRow? row}) =>
        pw.Container(
          constraints: row == null
              ? null
              : pw.BoxConstraints(minHeight: layout.minimumRowHeight(row)),
          padding: pw.EdgeInsets.symmetric(
            horizontal: layout.horizontalPadding,
            vertical: row == null ? 3 : layout.verticalPadding(row),
          ),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: layout.fontSize,
              fontWeight: heading ? pw.FontWeight.bold : pw.FontWeight.normal,
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
                for (var c = 1; c <= report.columns.length; c++)
                  c: pw.FixedColumnWidth(layout.roleWidth),
                report.columns.length + 1: pw.FixedColumnWidth(
                  layout.notesWidth,
                ),
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
                  cell(strings.text('Date'), heading: true),
                  for (var c = start; c < end; c++)
                    pw.Container(
                      decoration:
                          report.request.layout == ReportLayout.roles &&
                              c < report.columns.length
                          ? pw.BoxDecoration(
                              border: pw.Border(
                                bottom: pw.BorderSide(
                                  color: PdfColor.fromInt(
                                    roleColor(
                                      report.columns[c].id,
                                      report.columns[c].colorKey,
                                    ).lightArgb,
                                  ),
                                  width: 1,
                                ),
                              ),
                            )
                          : null,
                      child: cell(headings[c], heading: true),
                    ),
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
                      child: pw.RichText(
                        text: pw.TextSpan(
                          style: pw.TextStyle(fontSize: layout.fontSize),
                          children: [
                            pw.TextSpan(
                              text:
                                  '${reportWeekday(report.rows[r].date, strings.language)} ',
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.TextSpan(
                              text: europeanReportDate(report.rows[r].date),
                            ),
                          ],
                        ),
                      ),
                    ),
                    for (var c = start; c < end; c++)
                      cell(values[r][c], row: report.rows[r]),
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
  if (layout.monthly && pages > 1) {
    throw const ReportPrintLayoutException(
      'This month contains too much text for one readable page. Choose another orientation or reduce configured report columns.',
    );
  }
  return ReportPdf(bytes, pages);
}
