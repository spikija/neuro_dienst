import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../l10n/app_localizations.dart';
import '../services/supabase_roster_service.dart';

enum MonthReportLayout { roles, physicians }

class MonthReportScreen extends StatelessWidget {
  static const List<SlotKind> _displayedSlotKinds = [
    SlotKind.strokeUnitLeader,
    SlotKind.strokeUnitTeam1,
    SlotKind.strokeUnitTeam2,
    SlotKind.ambulance,
    SlotKind.neurosonology,
    SlotKind.neurovascularBoard,
    SlotKind.ofoBoard,
  ];

  final RosterMonth roster;
  final List<Doctor> doctors;
  final List<ReportRole>? reportRoles;
  final MonthReportLayout layout;

  const MonthReportScreen({
    super.key,
    required this.roster,
    required this.doctors,
    this.reportRoles,
    this.layout = MonthReportLayout.roles,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.fill('printPreviewForMonth', {
            'month': roster.month,
            'year': roster.year,
          }),
        ),
        actions: [
          IconButton(
            tooltip: l10n.t('printExportComesNext'),
            onPressed: null,
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: ColoredBox(
        color: Colors.grey.shade300,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _A4PortraitPage(
                child: _ReportContent(
                  roster: roster,
                  doctors: doctors,
                  reportRoles: reportRoles,
                  layout: layout,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _A4PortraitPage extends StatelessWidget {
  final Widget child;

  const _A4PortraitPage({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1120,
      height: 1584,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade500),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ReportContent extends StatelessWidget {
  final RosterMonth roster;
  final List<Doctor> doctors;
  final List<ReportRole>? reportRoles;
  final MonthReportLayout layout;

  const _ReportContent({
    required this.roster,
    required this.doctors,
    required this.reportRoles,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(roster: roster),
        const SizedBox(height: 12),
        Expanded(
          child: layout == MonthReportLayout.roles
              ? _ReportTable(
                  roster: roster,
                  doctors: doctors,
                  reportRoles: reportRoles,
                )
              : _PhysicianReportTable(
                  roster: roster,
                  doctors: doctors,
                  reportRoles: reportRoles,
                ),
        ),
        const SizedBox(height: 8),
        _ReportFooter(doctors: doctors),
      ],
    );
  }
}

class _ReportFooter extends StatelessWidget {
  final List<Doctor> doctors;

  const _ReportFooter({required this.doctors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final doctorLegend = doctors
        .map((doctor) => '${_doctorInitials(doctor)} ${doctor.fullName}')
        .join('   ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.t('reportRoleLegend'), style: const TextStyle(fontSize: 9)),
        const SizedBox(height: 3),
        Text(
          l10n.fill('reportDoctorLegend', {'doctors': doctorLegend}),
          style: const TextStyle(fontSize: 9),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ReportHeader extends StatelessWidget {
  final RosterMonth roster;

  const _ReportHeader({required this.roster});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('reportTitle'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_monthName(roster.month, l10n)} ${roster.year}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        Text(
          l10n.fill('reportGenerated', {
            'date': '${now.day}.${now.month}.${now.year}',
          }),
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  String _monthName(int month, AppLocalizations l10n) {
    if (month < 1 || month > 12) {
      return l10n.fill('monthNumber', {'month': month});
    }

    return l10n.t('month.$month');
  }
}

class _ReportTable extends StatelessWidget {
  final RosterMonth roster;
  final List<Doctor> doctors;
  final List<ReportRole>? reportRoles;

  const _ReportTable({
    required this.roster,
    required this.doctors,
    required this.reportRoles,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roleColumns = _roleColumns();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 1350.0;
        final headerHeight = _reportHeaderRowHeight(availableHeight);
        final rowUnitHeight = _reportBodyRowUnitHeight(
          availableHeight: availableHeight,
          headerHeight: headerHeight,
          days: roster.days,
        );
        final columnWidths = <int, TableColumnWidth>{
          0: const FixedColumnWidth(50),
          1: const FixedColumnWidth(36),
          for (var i = 0; i < roleColumns.length; i++)
            i + 2: const FlexColumnWidth(),
          roleColumns.length + 2: const FixedColumnWidth(64),
          roleColumns.length + 3: const FixedColumnWidth(110),
        };

        return Table(
          columnWidths: columnWidths,
          border: TableBorder.all(color: Colors.grey.shade600, width: 0.6),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _headerRow(headerHeight, roleColumns, l10n),
            for (final day in roster.days)
              _dayRow(
                day,
                rowUnitHeight * _reportRowWeight(day),
                roleColumns,
                l10n,
              ),
          ],
        );
      },
    );
  }

  TableRow _headerRow(
    double rowHeight,
    List<_ReportRoleColumn> roleColumns,
    AppLocalizations l10n,
  ) {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      children: [
        _cell(l10n.t('reportDate'), height: rowHeight, bold: true),
        _cell(l10n.t('reportDay'), height: rowHeight, bold: true),
        for (final role in roleColumns)
          _cell(
            _roleHeaderLabel(role, l10n),
            height: rowHeight,
            bold: true,
            maxLines: 2,
            fontSize: _reportHeaderFontSize(rowHeight, role.name),
          ),
        _cell(l10n.t('reportAbsenceShort'), height: rowHeight, bold: true),
        _cell(l10n.t('reportNotes'), height: rowHeight, bold: true),
      ],
    );
  }

  TableRow _dayRow(
    RosterDay day,
    double rowHeight,
    List<_ReportRoleColumn> roleColumns,
    AppLocalizations l10n,
  ) {
    return TableRow(
      decoration: BoxDecoration(color: _rowColor(day)),
      children: [
        _cell(
          '${day.date.day}.${day.date.month}.',
          height: rowHeight,
          bold: true,
        ),
        _cell(_weekdayAbbreviation(day.date, l10n), height: rowHeight),
        for (final role in roleColumns)
          _cell(_assignmentText(day, role), height: rowHeight),
        _cell(_absenceText(day), height: rowHeight),
        _cell(_notes(day, l10n), height: rowHeight),
      ],
    );
  }

  Widget _cell(
    String text, {
    required double height,
    bool bold = false,
    int maxLines = 1,
    double? fontSize,
  }) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize ?? _reportCellFontSize(height, bold: bold),
              height: height < 28 ? 0.95 : 1,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  String _roleHeaderLabel(_ReportRoleColumn role, AppLocalizations l10n) {
    final localizedName = l10n.t('reportRole.${role.code.toUpperCase()}');

    if (!localizedName.startsWith('reportRole.')) {
      return localizedName;
    }

    final name = role.name.trim();
    return name.isEmpty ? role.code : name;
  }

  List<_ReportRoleColumn> _roleColumns() {
    final roles = reportRoles;

    if (roles != null && roles.isNotEmpty) {
      return [
        for (final role in roles)
          _ReportRoleColumn(id: role.id, code: role.code, name: role.name),
      ];
    }

    return [
      for (final kind in MonthReportScreen._displayedSlotKinds)
        _ReportRoleColumn(
          id: kind.name,
          code: _slotAbbreviation(kind),
          name: _slotAbbreviation(kind),
          kind: kind,
        ),
    ];
  }

  String _assignmentText(RosterDay day, _ReportRoleColumn role) {
    final slot = _firstSlotForRole(day, role);

    if (slot == null) {
      return '';
    }

    final doctors =
        day.assignments
            .where((assignment) => assignment.slot.id == slot.id)
            .map((assignment) => _doctorSurname(assignment.doctor))
            .toList()
          ..sort();

    if (doctors.isEmpty) {
      return '-';
    }

    return doctors.join(', ');
  }

  DailySlot? _firstSlotForRole(RosterDay day, _ReportRoleColumn role) {
    for (final slot in day.slots) {
      if (slot.template.id == role.id) {
        return slot;
      }
    }

    final kind = role.kind ?? _slotKindFromReportCode(role.code);

    if (kind != null) {
      return _firstSlotForKind(day, kind);
    }

    return null;
  }

  DailySlot? _firstSlotForKind(RosterDay day, SlotKind kind) {
    for (final slot in day.slots) {
      if (slot.template.kind == kind) {
        return slot;
      }
    }

    return null;
  }

  String _absenceText(RosterDay day) {
    final absentDoctors =
        doctors
            .where((doctor) => doctor.absenceOn(day.date) != null)
            .map(_doctorInitials)
            .toList()
          ..sort();

    return absentDoctors.join(', ');
  }

  String _notes(RosterDay day, AppLocalizations l10n) {
    if (day.calendarInfo.isPublicHoliday) {
      return day.calendarInfo.publicHolidayName ?? l10n.t('holiday');
    }

    if (day.calendarInfo.isWeekend) {
      return l10n.t('weekend');
    }

    return '';
  }

  Color _rowColor(RosterDay day) {
    if (day.calendarInfo.isPublicHoliday) {
      return const Color(0xFFFFECEF);
    }

    if (day.calendarInfo.isWeekend) {
      return const Color(0xFFEFF4FA);
    }

    return Colors.white;
  }

  String _weekdayAbbreviation(DateTime date, AppLocalizations l10n) {
    switch (date.weekday) {
      case DateTime.monday:
        return l10n.t('weekday.mon');
      case DateTime.tuesday:
        return l10n.t('weekday.tue');
      case DateTime.wednesday:
        return l10n.t('weekday.wed');
      case DateTime.thursday:
        return l10n.t('weekday.thu');
      case DateTime.friday:
        return l10n.t('weekday.fri');
      case DateTime.saturday:
        return l10n.t('weekday.sat');
      case DateTime.sunday:
        return l10n.t('weekday.sun');
    }

    return '';
  }

  String _slotAbbreviation(SlotKind kind) {
    switch (kind) {
      case SlotKind.science:
        return 'SCI';
      case SlotKind.strokeUnitLeader:
        return 'SUL';
      case SlotKind.strokeUnitTeam1:
        return 'SU1';
      case SlotKind.strokeUnitTeam2:
        return 'SU2';
      case SlotKind.ambulance:
        return 'AMB';
      case SlotKind.neurosonology:
        return 'SON';
      case SlotKind.neurovascularBoard:
        return 'NVB';
      case SlotKind.ofoBoard:
        return 'OFO';
    }
  }
}

class _PhysicianReportTable extends StatelessWidget {
  final RosterMonth roster;
  final List<Doctor> doctors;
  final List<ReportRole>? reportRoles;

  const _PhysicianReportTable({
    required this.roster,
    required this.doctors,
    required this.reportRoles,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reportDoctors = _orderedDoctors();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 1350.0;
        final headerHeight = _reportHeaderRowHeight(availableHeight);
        final rowUnitHeight = _reportBodyRowUnitHeight(
          availableHeight: availableHeight,
          headerHeight: headerHeight,
          days: roster.days,
        );
        final columnWidths = <int, TableColumnWidth>{
          0: const FixedColumnWidth(50),
          1: const FixedColumnWidth(36),
          for (var i = 0; i < reportDoctors.length; i++)
            i + 2: const FlexColumnWidth(),
          reportDoctors.length + 2: const FixedColumnWidth(110),
        };

        return Table(
          columnWidths: columnWidths,
          border: TableBorder.all(color: Colors.grey.shade600, width: 0.6),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _headerRow(headerHeight, reportDoctors, l10n),
            for (final day in roster.days)
              _dayRow(
                day,
                rowUnitHeight * _reportRowWeight(day),
                reportDoctors,
                l10n,
              ),
          ],
        );
      },
    );
  }

  TableRow _headerRow(
    double rowHeight,
    List<Doctor> reportDoctors,
    AppLocalizations l10n,
  ) {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      children: [
        _cell(l10n.t('reportDate'), height: rowHeight, bold: true),
        _cell(l10n.t('reportDay'), height: rowHeight, bold: true),
        for (final doctor in reportDoctors)
          _cell(_doctorSurname(doctor), height: rowHeight, bold: true),
        _cell(l10n.t('reportNotes'), height: rowHeight, bold: true),
      ],
    );
  }

  TableRow _dayRow(
    RosterDay day,
    double rowHeight,
    List<Doctor> reportDoctors,
    AppLocalizations l10n,
  ) {
    return TableRow(
      decoration: BoxDecoration(color: _rowColor(day)),
      children: [
        _cell(
          '${day.date.day}.${day.date.month}.',
          height: rowHeight,
          bold: true,
        ),
        _cell(_weekdayAbbreviation(day.date, l10n), height: rowHeight),
        for (final doctor in reportDoctors)
          _cell(_doctorDayText(day, doctor, l10n), height: rowHeight),
        _cell(_notes(day, l10n), height: rowHeight),
      ],
    );
  }

  Widget _cell(String text, {required double height, bool bold = false}) {
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _reportCellFontSize(height, bold: bold),
              height: height < 28 ? 0.95 : 1,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  List<Doctor> _orderedDoctors() {
    final ordered = [...doctors]
      ..sort((a, b) {
        final printOrderCompare = a.printOrder.compareTo(b.printOrder);

        if (printOrderCompare != 0) {
          return printOrderCompare;
        }

        final rankCompare = _rankSortValue(
          a.rank,
        ).compareTo(_rankSortValue(b.rank));

        if (rankCompare != 0) {
          return rankCompare;
        }

        final lastCompare = a.lastName.compareTo(b.lastName);
        if (lastCompare != 0) {
          return lastCompare;
        }

        return a.firstName.compareTo(b.firstName);
      });

    return ordered;
  }

  String _doctorDayText(RosterDay day, Doctor doctor, AppLocalizations l10n) {
    final absence = doctor.absenceOn(day.date);

    if (absence != null) {
      return l10n.t('reportVacationShort');
    }

    final roleIds = reportRoles?.map((role) => role.id).toSet();
    final rows = day.assignments
        .where((assignment) => assignment.doctor.id == doctor.id)
        .where(
          (assignment) =>
              roleIds == null || roleIds.contains(assignment.slot.template.id),
        )
        .map((assignment) => _slotCode(assignment.slot))
        .toList();

    rows.sort((a, b) => _roleSortValue(a).compareTo(_roleSortValue(b)));

    return rows.join(', ');
  }

  String _slotCode(DailySlot slot) {
    ReportRole? role;

    for (final candidate in reportRoles ?? const <ReportRole>[]) {
      if (candidate.id == slot.template.id) {
        role = candidate;
        break;
      }
    }

    if (role != null) {
      return role.code;
    }

    return _slotKindAbbreviation(slot.template.kind);
  }

  Color _rowColor(RosterDay day) {
    if (day.calendarInfo.isPublicHoliday) {
      return const Color(0xFFFFECEF);
    }

    if (day.calendarInfo.isWeekend) {
      return const Color(0xFFEFF4FA);
    }

    return Colors.white;
  }

  String _notes(RosterDay day, AppLocalizations l10n) {
    if (day.calendarInfo.isPublicHoliday) {
      return day.calendarInfo.publicHolidayName ?? l10n.t('holiday');
    }

    if (day.calendarInfo.isWeekend) {
      return l10n.t('weekend');
    }

    return '';
  }

  String _weekdayAbbreviation(DateTime date, AppLocalizations l10n) {
    switch (date.weekday) {
      case DateTime.monday:
        return l10n.t('weekday.mon');
      case DateTime.tuesday:
        return l10n.t('weekday.tue');
      case DateTime.wednesday:
        return l10n.t('weekday.wed');
      case DateTime.thursday:
        return l10n.t('weekday.thu');
      case DateTime.friday:
        return l10n.t('weekday.fri');
      case DateTime.saturday:
        return l10n.t('weekday.sat');
      case DateTime.sunday:
        return l10n.t('weekday.sun');
    }

    return '';
  }
}

class _ReportRoleColumn {
  final String id;
  final String code;
  final String name;
  final SlotKind? kind;

  const _ReportRoleColumn({
    required this.id,
    required this.code,
    required this.name,
    this.kind,
  });
}

double _reportHeaderRowHeight(double availableHeight) {
  return availableHeight < 900 ? 34 : 42;
}

double _reportBodyRowUnitHeight({
  required double availableHeight,
  required double headerHeight,
  required List<RosterDay> days,
}) {
  if (days.isEmpty) {
    return 0;
  }

  final bodyHeight = (availableHeight - headerHeight).clamp(0, availableHeight);
  final totalWeight = days.fold<double>(
    0,
    (sum, day) => sum + _reportRowWeight(day),
  );

  if (totalWeight <= 0) {
    return 0;
  }

  return bodyHeight / totalWeight;
}

double _reportRowWeight(RosterDay day) {
  if (day.calendarInfo.isWeekend) {
    return 0.45;
  }

  if (day.calendarInfo.isPublicHoliday) {
    return 0.65;
  }

  return 1;
}

double _reportCellFontSize(double height, {required bool bold}) {
  if (height < 24) {
    return bold ? 10 : 10.5;
  }

  if (height < 34) {
    return bold ? 12 : 13;
  }

  return bold ? 14 : 15;
}

double _reportHeaderFontSize(double height, String text) {
  if (height < 36) {
    return text.length > 18 ? 9.5 : 10.5;
  }

  if (text.length > 22) {
    return 10;
  }

  if (text.length > 16) {
    return 11;
  }

  return 12;
}

SlotKind? _slotKindFromReportCode(String code) {
  switch (code.toUpperCase()) {
    case 'SCI':
      return SlotKind.science;
    case 'SUL':
      return SlotKind.strokeUnitLeader;
    case 'SU1':
      return SlotKind.strokeUnitTeam1;
    case 'SU2':
      return SlotKind.strokeUnitTeam2;
    case 'AMB':
    case 'ICB':
      return SlotKind.ambulance;
    case 'SON':
      return SlotKind.neurosonology;
    case 'NVB':
      return SlotKind.neurovascularBoard;
    case 'OFO':
      return SlotKind.ofoBoard;
  }

  return null;
}

int _rankSortValue(DoctorRank rank) {
  switch (rank) {
    case DoctorRank.head:
      return 0;
    case DoctorRank.consultant:
      return 1;
    case DoctorRank.seniorSpecialist:
      return 2;
    case DoctorRank.specialist:
      return 3;
    case DoctorRank.resident:
      return 4;
  }
}

int _roleSortValue(String code) {
  switch (code.toUpperCase()) {
    case 'SUL':
      return 0;
    case 'SU1':
      return 1;
    case 'SU2':
      return 2;
    case 'AMB':
      return 3;
    case 'ICB':
      return 4;
    case 'SON':
      return 5;
    case 'NVB':
      return 6;
    case 'OFO':
      return 7;
    case 'SCI':
      return 8;
  }

  return 99;
}

String _slotKindAbbreviation(SlotKind kind) {
  switch (kind) {
    case SlotKind.science:
      return 'SCI';
    case SlotKind.strokeUnitLeader:
      return 'SUL';
    case SlotKind.strokeUnitTeam1:
      return 'SU1';
    case SlotKind.strokeUnitTeam2:
      return 'SU2';
    case SlotKind.ambulance:
      return 'AMB';
    case SlotKind.neurosonology:
      return 'SON';
    case SlotKind.neurovascularBoard:
      return 'NVB';
    case SlotKind.ofoBoard:
      return 'OFO';
  }
}

String _doctorInitials(Doctor doctor) {
  final firstInitial = doctor.firstName.isEmpty ? '' : doctor.firstName[0];
  final lastInitial = doctor.lastName.isEmpty ? '' : doctor.lastName[0];
  return '$firstInitial$lastInitial'.toUpperCase();
}

String _doctorSurname(Doctor doctor) {
  if (doctor.lastName.isNotEmpty) {
    return doctor.lastName;
  }

  return _doctorInitials(doctor);
}
