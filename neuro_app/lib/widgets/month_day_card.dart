import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

class MonthDayCard extends StatelessWidget {
  static const List<SlotKind> _prioritySlotKinds = [
    SlotKind.strokeUnitLeader,
    SlotKind.strokeUnitTeam1,
    SlotKind.strokeUnitTeam2,
    SlotKind.ambulance,
  ];
  final RosterDay day;
  final MonthDayViewModel dayView;
  final Doctor currentDoctor;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool dense;
  final bool hasConflict;
  final bool isEditorMode;

  const MonthDayCard({
    super.key,
    required this.day,
    required this.dayView,
    required this.currentDoctor,
    required this.onTap,
    this.isSelected = false,
    this.dense = false,
    this.hasConflict = false,
    this.isEditorMode = false,
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
    final isFullyAssigned = _isFullyAssigned();
    final hasAnyAssignment = day.assignments.isNotEmpty;
    final color = _backgroundColor(
      isAbsent: isAbsent,
      isDisabled: isDisabled,
      hasMyAssignment: hasMyAssignment,
      hasAnyAssignment: hasAnyAssignment,
      isFullyAssigned: isFullyAssigned,
    );

    return Tooltip(
      message: _tooltipMessage(roleRows),
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        child: Card(
          margin: EdgeInsets.zero,
          color: color,
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
            padding: EdgeInsets.all(dense ? 2 : 6),
            child: Stack(
              children: [
                Align(
                  alignment: dense ? Alignment.center : Alignment.centerRight,
                  child: Text(
                    '${day.date.day}',
                    style: TextStyle(
                      fontSize: dense ? 18 : 34,
                      fontWeight: FontWeight.w900,
                      color:
                          (isDisabled
                                  ? Colors.grey.shade700
                                  : _dayNumberColor(color))
                              .withAlpha(dense ? 100 : 76),
                      height: 0.9,
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
                    hasMyAssignment: hasMyAssignment,
                    hasAnyAssignment: hasAnyAssignment,
                    isFullyAssigned: isFullyAssigned,
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
    required bool hasMyAssignment,
    required bool hasAnyAssignment,
    required bool isFullyAssigned,
  }) {
    final label = _stateLabel(
      isAbsent: isAbsent,
      hasMyAssignment: hasMyAssignment,
      hasAnyAssignment: hasAnyAssignment,
      isFullyAssigned: isFullyAssigned,
    );

    if (label == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: dense ? Alignment.bottomCenter : Alignment.topLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(20),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: dense ? 8 : 10,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
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

  Color? _backgroundColor({
    required bool isAbsent,
    required bool isDisabled,
    required bool hasMyAssignment,
    required bool hasAnyAssignment,
    required bool isFullyAssigned,
  }) {
    if (isSelected) {
      return Colors.teal.shade100;
    }

    if (isAbsent) {
      return Colors.purple.shade100;
    }

    if (isDisabled) {
      return Colors.grey.shade300;
    }

    if (isEditorMode && day.slots.isNotEmpty && !isFullyAssigned) {
      return Colors.red.shade100;
    }

    if (isFullyAssigned) {
      return Colors.blue.shade700;
    }

    if (hasMyAssignment) {
      return Colors.lightBlue.shade100;
    }

    return null;
  }

  Color _dayNumberColor(Color? backgroundColor) {
    if (backgroundColor == Colors.blue.shade700) {
      return Colors.white;
    }

    return Colors.black;
  }

  String? _stateLabel({
    required bool isAbsent,
    required bool hasMyAssignment,
    required bool hasAnyAssignment,
    required bool isFullyAssigned,
  }) {
    if (isAbsent) {
      return 'VAC';
    }

    if (isFullyAssigned) {
      return 'FULL';
    }

    if (hasMyAssignment) {
      return 'ME';
    }

    if (isEditorMode && hasAnyAssignment) {
      return 'PART';
    }

    return null;
  }

  bool _isFullyAssigned() {
    if (day.slots.isEmpty) {
      return false;
    }

    for (final slot in day.slots) {
      final assignmentsForSlot = day.assignments
          .where((assignment) => assignment.slot.id == slot.id)
          .length;

      if (assignmentsForSlot < slot.template.maxDoctors) {
        return false;
      }
    }

    return true;
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
