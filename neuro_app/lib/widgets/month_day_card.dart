import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

class MonthDayCard extends StatelessWidget {
  static const List<SlotKind> _prioritySlotKinds = [
    SlotKind.strokeUnitLeader,
    SlotKind.strokeUnitTeam1,
    SlotKind.strokeUnitTeam2,
    SlotKind.ambulance,
  ];
  static const int _maxVisibleRoleRows = 6;

  final RosterDay day;
  final MonthDayViewModel dayView;
  final Doctor currentDoctor;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool dense;
  final bool hasConflict;

  const MonthDayCard({
    super.key,
    required this.day,
    required this.dayView,
    required this.currentDoctor,
    required this.onTap,
    this.isSelected = false,
    this.dense = false,
    this.hasConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled =
        day.calendarInfo.isPublicHoliday || day.calendarInfo.isWeekend;

    final myAssignmentsToday = RosterStatisticsService()
        .countAssignmentsForDoctorInDay(day: day, doctor: currentDoctor);

    final hasMyAssignment = myAssignmentsToday > 0;
    final absence = currentDoctor.absenceOn(day.date);
    final isAbsent = absence != null;
    final roleRows = _roleRows();

    return Tooltip(
      message: _tooltipMessage(roleRows),
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        child: Card(
          color: isSelected
              ? Colors.teal.shade100
              : isAbsent
              ? Colors.purple.shade100
              : day.calendarInfo.isPublicHoliday
              ? Colors.red.shade100
              : day.calendarInfo.isWeekend
              ? Colors.grey.shade300
              : hasMyAssignment
              ? Colors.blue.shade100
              : null,
          shape: isSelected
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Colors.teal.shade700, width: 2),
                )
              : hasConflict
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Colors.orange.shade800, width: 2),
                )
              : null,
          child: Padding(
            padding: EdgeInsets.all(dense ? 2 : 4),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${day.date.day}',
                    style: TextStyle(
                      fontSize: dense ? 22 : 52,
                      fontWeight: FontWeight.w900,
                      color: (isDisabled ? Colors.grey.shade700 : Colors.black)
                          .withAlpha(dense ? 42 : 26),
                      height: 0.9,
                    ),
                  ),
                ),
                if (isAbsent && !dense)
                  Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      'VAC',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade900,
                      ),
                    ),
                  ),
                if (hasConflict && !dense)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(
                      Icons.warning_amber,
                      size: 16,
                      color: Colors.orange.shade900,
                    ),
                  ),
                Positioned.fill(
                  child: _buildCellBody(
                    isAbsent: isAbsent,
                    absence: absence,
                    roleRows: roleRows,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCellBody({
    required bool isAbsent,
    required AvailabilityPeriod? absence,
    required List<String> roleRows,
  }) {
    if (dense) {
      return Align(
        alignment: Alignment.center,
        child: Text(
          isAbsent ? 'VAC' : _shortWeekday(day.date),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (day.calendarInfo.isPublicHoliday) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('Holiday', style: TextStyle(fontSize: 11)),
      );
    }

    if (day.calendarInfo.isWeekend) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('Weekend', style: TextStyle(fontSize: 11)),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in _visibleRoleRows(roleRows))
              Text(
                row,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.02,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortWeekday(DateTime date) {
    return date.weekday == DateTime.saturday ? 'Sat' : 'Sun';
  }

  List<String> _roleRows() {
    final rows = <String>[];
    final orderedKinds = _orderedSlotKinds();

    for (final kind in orderedKinds) {
      final slot = _firstSlotForKind(kind);

      if (slot == null) {
        rows.add('${_slotKindAbbreviation(kind)} ...');
        continue;
      }

      final initials = day.assignments
          .where((assignment) => assignment.slot.id == slot.id)
          .map((assignment) => _doctorInitials(assignment.doctor))
          .toList();

      initials.sort();

      rows.add(
        '${_slotKindAbbreviation(kind)} '
        '${initials.isEmpty ? '--' : initials.join(',')}',
      );
    }

    return rows;
  }

  List<String> _visibleRoleRows(List<String> roleRows) {
    if (roleRows.length <= _maxVisibleRoleRows) {
      return roleRows;
    }

    return [...roleRows.take(_maxVisibleRoleRows - 1), '...'];
  }

  List<SlotKind> _orderedSlotKinds() {
    final kinds = <SlotKind>[];

    for (final kind in _prioritySlotKinds) {
      if (_dayHasSlotKind(kind)) {
        kinds.add(kind);
      }
    }

    for (final slot in day.slots) {
      if (!kinds.contains(slot.template.kind)) {
        kinds.add(slot.template.kind);
      }
    }

    return kinds;
  }

  bool _dayHasSlotKind(SlotKind kind) {
    return day.slots.any((slot) => slot.template.kind == kind);
  }

  String _tooltipMessage(List<String> roleRows) {
    if (day.calendarInfo.isWeekend) {
      return '${day.date.day}: ${_shortWeekday(day.date)}';
    }

    if (day.calendarInfo.isPublicHoliday) {
      return '${day.date.day}: Holiday';
    }

    if (roleRows.isEmpty) {
      return '${day.date.day}: No roles';
    }

    return ['Day ${day.date.day}', ...roleRows].join('\n');
  }

  DailySlot? _firstSlotForKind(SlotKind kind) {
    for (final slot in day.slots) {
      if (slot.template.kind == kind) {
        return slot;
      }
    }

    return null;
  }

  String _doctorInitials(Doctor doctor) {
    final firstInitial = doctor.firstName.isEmpty ? '' : doctor.firstName[0];
    final lastInitial = doctor.lastName.isEmpty ? '' : doctor.lastName[0];
    return '$firstInitial$lastInitial'.toUpperCase();
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
}
