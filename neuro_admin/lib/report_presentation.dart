import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'localization.dart';

class ReportAbsenceEntry {
  final String surname;
  final List<AvailabilityPeriod> periods;
  const ReportAbsenceEntry(this.surname, this.periods);
}

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
      ...absences(row).map((entry) => entry.surname),
    ].join('\n'),
  ];
  String localizedCell(ReportCell cell) {
    if (report.request.layout == ReportLayout.physicians &&
        cell.absencesByPhysician.isNotEmpty) {
      return cellAbsences(cell).map((entry) => entry.surname).join('\n');
    }
    return reportCellText(cell, report.request.layout);
  }

  List<ReportAbsenceEntry> absences(ReportRow row) =>
      _absenceEntries(row.cells.values);

  List<ReportAbsenceEntry> cellAbsences(ReportCell cell) =>
      _absenceEntries([cell]);

  List<ReportAbsenceEntry> _absenceEntries(Iterable<ReportCell> cells) {
    final byPhysician = <String, Map<AvailabilityType, AvailabilityPeriod>>{};
    for (final cell in cells) {
      for (final entry in cell.absencesByPhysician.entries) {
        final types = byPhysician[entry.key] ??= {};
        for (final period in entry.value) {
          types[period.type] = period;
        }
      }
    }
    return [
      for (final entry in byPhysician.entries)
        ReportAbsenceEntry(
          report.physicianSurnames[entry.key] ??
              strings.text('Unknown physician'),
          entry.value.values.toList(),
        ),
    ];
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
