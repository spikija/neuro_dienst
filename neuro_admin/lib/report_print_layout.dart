import 'package:pdf/pdf.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';

class ReportPrintLayoutException implements Exception {
  final String message;
  const ReportPrintLayoutException(this.message);
}

/// Print measurements in PDF points, independent of desktop widgets.
class ReportPrintLayout {
  final PdfPageFormat page;
  final int roleCount;
  final bool monthly;
  final double fontScale;
  final bool compactRows;
  const ReportPrintLayout({
    required this.page,
    required this.roleCount,
    required this.monthly,
    this.fontScale = 1.2,
    this.compactRows = false,
  });
  double get margin => 18;
  double get availableWidth => page.width - 2 * margin;
  double get dateWidth => monthly ? 78 : 100;
  double get notesWidth => monthly ? 100 : 110;
  double get roleWidth => roleCount == 0
      ? 0
      : (availableWidth - dateWidth - notesWidth) / roleCount;
  double get fontSize =>
      (monthly ? (roleWidth < 42 ? 7 : 8) : 9) * fontScale + 2;
  double get dateFontSize => monthly ? (roleWidth < 42 ? 7 : 8) : 9;
  double get horizontalPadding => monthly ? 1 : 4;
  double get weekdayHeight => monthly ? (compactRows ? 14 : 18) : 20;
  double get weekendHeight => monthly ? 10 : 14;
  double minimumRowHeight(ReportRow row) =>
      row.calendar.isWeekend ? weekendHeight : weekdayHeight;
  double verticalPadding(ReportRow row) =>
      row.calendar.isWeekend || (monthly && compactRows) ? 0.5 : 2;
  PdfColor rowColor(ReportRow row) => row.calendar.publicHolidayName != null
      ? const PdfColor.fromInt(0xffedf0e3)
      : row.calendar.isWeekend
      ? const PdfColor.fromInt(0xffeeeeee)
      : PdfColors.white;
  static const headerColor = PdfColor.fromInt(0xffdbe4e9);
  void validate() {
    if (monthly && roleCount > 0 && roleWidth < 30) {
      throw const ReportPrintLayoutException(
        'Too many role columns for legible printing. Choose landscape or reduce configured report columns.',
      );
    }
  }
}
