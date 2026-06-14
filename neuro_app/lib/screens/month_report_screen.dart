import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../services/supabase_roster_service.dart';

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

  const MonthReportScreen({
    super.key,
    required this.roster,
    required this.doctors,
    this.reportRoles,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Print preview ${roster.month}/${roster.year}'),
        actions: [
          IconButton(
            tooltip: 'Print export comes next',
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

  const _ReportContent({
    required this.roster,
    required this.doctors,
    required this.reportRoles,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(roster: roster),
        const SizedBox(height: 12),
        Expanded(
          child: _ReportTable(
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
    final doctorLegend = doctors
        .map((doctor) => '${_doctorInitials(doctor)} ${doctor.fullName}')
        .join('   ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Roles: SUL Stroke Unit Leader, SU1/SU2 Stroke Unit Team, AMB Outpatient Clinic, '
          'SON Neurosonology, NVB Neurovascular Board, OFO OFO Board',
          style: TextStyle(fontSize: 9),
        ),
        const SizedBox(height: 3),
        Text(
          'Doctors: $doctorLegend',
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
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Neurology Department Duty Roster',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_monthName(roster.month)} ${roster.year}',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        Text(
          'Generated: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    if (month < 1 || month > 12) {
      return 'Month $month';
    }

    return names[month - 1];
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
    final roleColumns = _roleColumns();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 1350.0;
        final rowHeight = availableHeight / (roster.days.length + 1);
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
            _headerRow(rowHeight, roleColumns),
            for (final day in roster.days) _dayRow(day, rowHeight, roleColumns),
          ],
        );
      },
    );
  }

  TableRow _headerRow(double rowHeight, List<_ReportRoleColumn> roleColumns) {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      children: [
        _cell('Date', height: rowHeight, bold: true),
        _cell('Day', height: rowHeight, bold: true),
        for (final role in roleColumns)
          _cell(role.code, height: rowHeight, bold: true),
        _cell('Abs', height: rowHeight, bold: true),
        _cell('Notes', height: rowHeight, bold: true),
      ],
    );
  }

  TableRow _dayRow(
    RosterDay day,
    double rowHeight,
    List<_ReportRoleColumn> roleColumns,
  ) {
    return TableRow(
      decoration: BoxDecoration(color: _rowColor(day)),
      children: [
        _cell(
          '${day.date.day}.${day.date.month}.',
          height: rowHeight,
          bold: true,
        ),
        _cell(_weekdayAbbreviation(day.date), height: rowHeight),
        for (final role in roleColumns)
          _cell(_assignmentText(day, role), height: rowHeight),
        _cell(_absenceText(day), height: rowHeight),
        _cell(_notes(day), height: rowHeight),
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
              fontSize: bold ? 11 : 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
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

  String _notes(RosterDay day) {
    if (day.calendarInfo.isPublicHoliday) {
      return day.calendarInfo.publicHolidayName ?? 'Holiday';
    }

    if (day.calendarInfo.isWeekend) {
      return 'Weekend';
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

  String _weekdayAbbreviation(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Mo';
      case DateTime.tuesday:
        return 'Tu';
      case DateTime.wednesday:
        return 'We';
      case DateTime.thursday:
        return 'Th';
      case DateTime.friday:
        return 'Fr';
      case DateTime.saturday:
        return 'Sa';
      case DateTime.sunday:
        return 'Su';
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
