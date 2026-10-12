import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'localization.dart';

/// Formatting only. ReportDocument remains the source of staffing/absence facts.
class ReportPresentation {
  final ReportDocument report;
  final AdminStrings strings;
  final Set<String>? selectedRoleIds;
  const ReportPresentation(this.report, this.strings, {this.selectedRoleIds});
  List<ReportColumn> get columns =>
      report.request.layout == ReportLayout.roles && selectedRoleIds != null
      ? report.availableRoleColumns
            .where((c) => selectedRoleIds!.contains(c.id))
            .toList()
      : report.columns;
  String get title =>
      '${strings.text('Reports')} · ${report.rows.isEmpty ? '' : '${report.rows.first.date.year}-${report.rows.first.date.month.toString().padLeft(2, '0')}'} · ${strings.text(report.request.layout == ReportLayout.roles ? 'By role' : 'By physician')}';
  List<String> get headings => [
    ...columns.map((c) => c.label),
    strings.text('Absences / holiday'),
  ];
  List<String> cells(ReportRow row) => [
    for (final c in columns) localizedCell(row.cells[c.id]!),
    [
      if (row.calendar.publicHolidayName != null)
        holiday(row.calendar.publicHolidayName!),
      ...{
        for (final cell in row.cells.values)
          for (final e in cell.absencesByPhysician.entries)
            '${report.physicianLabels[e.key] ?? strings.text('Unknown physician')}: ${e.value.map((a) => strings.text(a.label)).join(', ')}',
      },
    ].join('\n'),
  ];
  String localizedCell(ReportCell cell) {
    if (report.request.layout == ReportLayout.physicians &&
        cell.absencesByPhysician.isNotEmpty) {
      return cell.absencesByPhysician.values
          .expand((a) => a)
          .map((a) => strings.text(a.label))
          .toSet()
          .join(', ');
    }
    return reportCellText(cell, report.request.layout);
  }

  String holiday(String name) => localizedHoliday(name, strings);
}

String localizedHoliday(String name, AdminStrings strings) =>
    strings.language == 'de'
    ? name
    : name
          .split('; ')
          .map(
            (n) =>
                const {
                  'Neujahr': "New Year's Day",
                  'Heilige Drei Könige': 'Epiphany',
                  'Staatsfeiertag': 'State Holiday',
                  'Mariä Himmelfahrt': 'Assumption Day',
                  'Nationalfeiertag': 'National Day',
                  'Allerheiligen': "All Saints' Day",
                  'Mariä Empfängnis': 'Immaculate Conception',
                  'Christtag': 'Christmas Day',
                  'Stefanitag': "St Stephen's Day",
                  'Ostermontag': 'Easter Monday',
                  'Christi Himmelfahrt': 'Ascension Day',
                  'Pfingstmontag': 'Whit Monday',
                  'Fronleichnam': 'Corpus Christi',
                }[n] ??
                n,
          )
          .join('; ');

String europeanReportDate(HospitalDate d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
String reportWeekday(HospitalDate d, String language) => (language == 'de'
    ? const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
    : const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ])[d.asDateOnlyUtc.weekday - 1];
