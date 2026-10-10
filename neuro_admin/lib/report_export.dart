import 'package:file_selector/file_selector.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'report_pdf.dart';
import 'localization.dart';

abstract interface class ReportExportService {
  Future<void> export(
    ReportDocument report,
    ReportOrientation orientation,
    AdminStrings strings, {
    required bool print,
  });
}

class DesktopReportExport implements ReportExportService {
  const DesktopReportExport();
  @override
  Future<void> export(
    ReportDocument report,
    ReportOrientation orientation,
    AdminStrings strings, {
    required bool print,
  }) async {
    final pdf = await buildReportPdf(report, orientation, strings);
    final name =
        'NeuroDienst-${report.rows.isEmpty ? 'report' : report.rows.first.date}-${report.request.layout.name}-${orientation.name}.pdf';
    if (print) {
      await Printing.layoutPdf(
        name: name,
        format: orientation == ReportOrientation.portrait
            ? PdfPageFormat.a4
            : PdfPageFormat.a4.landscape,
        dynamicLayout: false,
        onLayout: (_) => Future.value(pdf.bytes),
      );
    } else {
      final location = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (location != null) {
        await XFile.fromData(
          pdf.bytes,
          mimeType: 'application/pdf',
          name: name,
        ).saveTo(location.path);
      }
    }
  }
}
