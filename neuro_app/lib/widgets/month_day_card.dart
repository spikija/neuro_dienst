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
    final theme = Theme.of(context);
    final isDisabled =
        day.calendarInfo.isPublicHoliday || day.calendarInfo.isWeekend;

    final myAssignmentsToday = RosterStatisticsService()
        .countAssignmentsForDoctorInDay(day: day, doctor: currentDoctor);

    final hasMyAssignment = myAssignmentsToday > 0;
    final myRoleLabel = _myRoleLabel();
    final absence = currentDoctor.absenceOn(day.date);
    final isAbsent = absence != null;
    final roleRows = _roleRows();
    final isFullyAssigned = _isFullyAssigned();
    final hasAnyAssignment = day.assignments.isNotEmpty;
    final color = _backgroundColor(
      context: context,
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
              color: _borderColor(context, hasConflict: hasConflict),
              width: isSelected || hasConflict ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(dense ? 1 : 3),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fontSize = _dayNumberFontSize(constraints.biggest);

                      return Align(
                        alignment: dense
                            ? Alignment.center
                            : Alignment.centerRight,
                        child: Text(
                          '${day.date.day}',
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900,
                            color:
                                (isDisabled
                                        ? theme.colorScheme.onSurface
                                        : _dayNumberColor(context, color))
                                    .withAlpha(dense ? 80 : 52),
                            height: 0.85,
                          ),
                        ),
                      );
                    },
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
                    context: context,
                    isAbsent: isAbsent,
                    hasMyAssignment: hasMyAssignment,
                    hasAnyAssignment: hasAnyAssignment,
                    isFullyAssigned: isFullyAssigned,
                    myRoleLabel: myRoleLabel,
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
    required BuildContext context,
    required bool isAbsent,
    required bool hasMyAssignment,
    required bool hasAnyAssignment,
    required bool isFullyAssigned,
    required String? myRoleLabel,
  }) {
    final label = _stateLabel(
      isAbsent: isAbsent,
      hasMyAssignment: hasMyAssignment,
      hasAnyAssignment: hasAnyAssignment,
      isFullyAssigned: isFullyAssigned,
      myRoleLabel: myRoleLabel,
    );

    if (label == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: dense ? Alignment.bottomCenter : Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: dense ? 9 : 18,
              fontWeight: FontWeight.w900,
              height: 1,
              color: _labelColor(context),
            ),
          ),
        ),
      ),
    );
  }

  String _shortWeekday(DateTime date) {
    return date.weekday == DateTime.saturday ? 'Sat' : 'Sun';
  }

  double _dayNumberFontSize(Size size) {
    final shortestSide = size.shortestSide;

    if (shortestSide <= 0) {
      return dense ? 12 : 20;
    }

    final sizeFactor = dense ? 0.74 : 0.82;
    final rawSize = shortestSide * sizeFactor;

    return rawSize.clamp(dense ? 12.0 : 22.0, dense ? 22.0 : 54.0);
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
    required BuildContext context,
    required bool isAbsent,
    required bool isDisabled,
    required bool hasMyAssignment,
    required bool hasAnyAssignment,
    required bool isFullyAssigned,
  }) {
    if (isSelected) {
      return Colors.yellow.shade200;
    }

    if (isAbsent) {
      return Colors.purple.shade300;
    }

    if (isDisabled) {
      return Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2B2F33)
          : const Color(0xFFE1E5EA);
    }

    if (isEditorMode && day.slots.isNotEmpty && !isFullyAssigned) {
      return Colors.red.shade300;
    }

    if (isFullyAssigned) {
      return Colors.blue.shade800;
    }

    if (hasMyAssignment) {
      return Colors.cyan.shade300;
    }

    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF14171A)
        : Colors.white;
  }

  Color _dayNumberColor(BuildContext context, Color? backgroundColor) {
    if (backgroundColor == Colors.blue.shade800 ||
        backgroundColor == Colors.purple.shade300) {
      return Colors.white;
    }

    return Theme.of(context).colorScheme.onSurface;
  }

  Color _labelColor(BuildContext context) {
    if (_isFullyAssigned() || currentDoctor.absenceOn(day.date) != null) {
      return Colors.white;
    }

    return Theme.of(context).colorScheme.onSurface;
  }

  Color _borderColor(BuildContext context, {required bool hasConflict}) {
    if (isSelected) {
      return Colors.black;
    }

    if (hasConflict) {
      return Colors.red.shade900;
    }

    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF6D747C)
        : const Color(0xFF2F3842);
  }

  String? _stateLabel({
    required bool isAbsent,
    required bool hasMyAssignment,
    required bool hasAnyAssignment,
    required bool isFullyAssigned,
    required String? myRoleLabel,
  }) {
    if (isAbsent) {
      return 'VAC';
    }

    if (hasMyAssignment) {
      return myRoleLabel ?? 'ME';
    }

    if (isFullyAssigned) {
      return 'FULL';
    }

    if (isEditorMode && hasAnyAssignment) {
      return 'PART';
    }

    return null;
  }

  String? _myRoleLabel() {
    final labels = day.assignments
        .where((assignment) => assignment.doctor.id == currentDoctor.id)
        .map(
          (assignment) => _slotKindAbbreviation(assignment.slot.template.kind),
        )
        .toSet()
        .toList();

    if (labels.isEmpty) {
      return null;
    }

    labels.sort();
    return labels.join('+');
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
