import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_app/extensions/time_formatting.dart';
import '../widgets/month_day_card.dart';
import 'day_screen.dart';
import 'doctor_profile_screen.dart';
import 'doctor_selector_screen.dart';
import 'month_report_screen.dart';
import '../widgets/doctor_selector_bar.dart';

class MonthScreen extends StatefulWidget {
  final RosterMonth roster;
  final Doctor currentDoctor;
  final ValueChanged<Doctor> onDoctorChanged;
  final ValueChanged<Doctor> onDoctorUpdated;
  final List<Doctor> doctors;

  const MonthScreen({
    super.key,
    required this.roster,
    required this.currentDoctor,
    required this.doctors,
    required this.onDoctorChanged,
    required this.onDoctorUpdated,
  });

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  static const int _weekdayColumns = 5;
  static const double _gridSpacing = 4;
  static const double _gridPadding = 8;
  static const double _weekendColumnWidthFactor = 0.58;

  late RosterMonth currentRoster;
  final Set<String> _selectedDateKeys = {};
  int? _pointerDownIndex;
  bool _isRangeSelecting = false;
  String? _statusMessage;
  bool _editorMode = false;
  Doctor? _editorDoctor;
  SlotKind? _editorSlotKind;

  int _myAssignmentsThisMonthCount() {
    return currentRoster.days
        .expand((day) => day.assignments)
        .where((assignment) => assignment.doctor.id == widget.currentDoctor.id)
        .length;
  }

  @override
  void initState() {
    super.initState();
    currentRoster = widget.roster;
    _editorDoctor = widget.currentDoctor;
  }

  @override
  Widget build(BuildContext context) {
    final monthView = MonthViewService().getMonthView(currentRoster);
    final conflictsByDate = _buildConflictsByDate();
    final conflictCount = conflictsByDate.values.fold<int>(
      0,
      (total, conflicts) => total + conflicts.length,
    );

    final myAssignmentsThisMonth = _myAssignmentsThisMonthCount();

    final statistics = RosterStatisticsService();

    final coverage = statistics.coveragePercentage(roster: currentRoster);

    final openSlots = statistics.countOpenSlots(roster: currentRoster);

    final assignedSlots = statistics.countAssignedSlots(roster: currentRoster);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${currentRoster.month}/${currentRoster.year}'),
            Text(
              widget.currentDoctor.fullName,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_account),
            onPressed: () async {
              final selectedDoctor = await Navigator.push<Doctor>(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorSelectorScreen(doctors: widget.doctors),
                ),
              );

              if (selectedDoctor != null) {
                widget.onDoctorChanged(selectedDoctor);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showMyAssignmentsDialog,
          ),
          IconButton(
            tooltip: 'Monthly report',
            icon: const Icon(Icons.print),
            onPressed: _openMonthlyReport,
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DoctorProfileScreen(doctor: widget.currentDoctor),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          DoctorSelectorBar(
            doctors: widget.doctors,
            selectedDoctor: widget.currentDoctor,
            onSelected: widget.onDoctorChanged,
          ),
          _buildModeBar(),
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text('Open'),
                      Text(
                        '$openSlots',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Assigned'),
                      Text(
                        '$assignedSlots',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Mine'),
                      Text(
                        '$myAssignmentsThisMonth',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Coverage'),
                      Text(
                        '${coverage.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_editorMode)
                    InkWell(
                      onTap: conflictCount > 0
                          ? () => _showConflictsDialog(conflictsByDate)
                          : null,
                      child: Column(
                        children: [
                          const Text('Warnings'),
                          Text(
                            '$conflictCount',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: conflictCount > 0
                                  ? Colors.orange.shade900
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _buildMonthGrid(monthView, conflictsByDate),
                if (_statusMessage != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: _selectedDateKeys.isNotEmpty ? 76 : 16,
                    child: _buildStatusStrip(),
                  ),
                if (_selectedDateKeys.isNotEmpty)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _buildBulkActionBar(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.person),
                label: Text('Doctor'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.edit_calendar),
                label: Text('Editor'),
              ),
            ],
            selected: {_editorMode},
            onSelectionChanged: (selection) {
              setState(() {
                _editorMode = selection.first;
                _editorDoctor ??= widget.currentDoctor;
              });
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _editorMode
                  ? 'Bulk edits can assign any doctor.'
                  : 'Personal planning for ${widget.currentDoctor.firstName}.',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(
    List<MonthDayViewModel> monthView,
    Map<String, List<Conflict>> conflictsByDate,
  ) {
    final weekRows = _buildWeekRows();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: (event) {
            _handleGridPointerDown(event.localPosition, constraints.biggest);
          },
          onPointerMove: (event) {
            _handleGridPointerMove(event.localPosition, constraints.biggest);
          },
          onPointerUp: (event) {
            _handleGridPointerUp(event.localPosition, constraints.biggest);
          },
          onPointerCancel: (_) => _resetPointerSelection(),
          child: Padding(
            padding: const EdgeInsets.all(_gridPadding),
            child: Column(
              children: [
                for (var row = 0; row < weekRows.length; row++) ...[
                  Expanded(
                    child: Row(
                      children: [
                        for (
                          var weekday = 0;
                          weekday < _weekdayColumns;
                          weekday++
                        ) ...[
                          Expanded(
                            child: _buildDayCell(
                              weekRows[row][weekday],
                              monthView,
                              conflictsByDate: conflictsByDate,
                            ),
                          ),
                          const SizedBox(width: _gridSpacing),
                        ],
                        SizedBox(
                          width: _weekendColumnWidth(constraints.maxWidth),
                          child: Column(
                            children: [
                              Expanded(
                                child: _buildDayCell(
                                  weekRows[row][DateTime.saturday - 1],
                                  monthView,
                                  conflictsByDate: conflictsByDate,
                                  dense: true,
                                ),
                              ),
                              const SizedBox(height: _gridSpacing),
                              Expanded(
                                child: _buildDayCell(
                                  weekRows[row][DateTime.sunday - 1],
                                  monthView,
                                  conflictsByDate: conflictsByDate,
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row < weekRows.length - 1)
                    const SizedBox(height: _gridSpacing),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayCell(
    int? index,
    List<MonthDayViewModel> monthView, {
    required Map<String, List<Conflict>> conflictsByDate,
    bool dense = false,
  }) {
    if (index == null) {
      return const SizedBox.shrink();
    }

    final day = currentRoster.days[index];
    final dayView = monthView[index];

    return MonthDayCard(
      day: day,
      dayView: dayView,
      currentDoctor: widget.currentDoctor,
      isSelected: _selectedDateKeys.contains(_dateKey(day.date)),
      onTap: null,
      dense: dense,
      hasConflict:
          _editorMode &&
          (conflictsByDate[_dateKey(day.date)]?.isNotEmpty ?? false),
    );
  }

  Map<String, List<Conflict>> _buildConflictsByDate() {
    final conflictsByDate = <String, List<Conflict>>{};
    final validator = RosterValidator();

    for (final day in currentRoster.days) {
      final conflicts = [
        ...validator.validateDay(day),
        ..._validateAbsenceConflicts(day),
      ];

      if (conflicts.isNotEmpty) {
        conflictsByDate[_dateKey(day.date)] = conflicts;
      }
    }

    return conflictsByDate;
  }

  List<Conflict> _validateAbsenceConflicts(RosterDay day) {
    final conflicts = <Conflict>[];

    for (final assignment in day.assignments) {
      final absence = assignment.doctor.absenceOn(day.date);

      if (absence != null) {
        conflicts.add(
          Conflict(
            '${assignment.doctor.fullName} assigned to '
            '${assignment.slot.template.name} while absent '
            '(${absence.label})',
          ),
        );
      }
    }

    return conflicts;
  }

  void _showConflictsDialog(Map<String, List<Conflict>> conflictsByDate) {
    final entries = conflictsByDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Roster warnings'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in entries) ...[
                Text(
                  _formatDateKey(entry.key),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (final conflict in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text('- ${conflict.message}'),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  List<List<int?>> _buildWeekRows() {
    final firstWeekday = currentRoster.days.first.date.weekday;
    final leadingEmptyCells = firstWeekday - DateTime.monday;
    final totalCells = leadingEmptyCells + currentRoster.days.length;
    final weekCount = (totalCells / DateTime.daysPerWeek).ceil();

    final rows = List.generate(
      weekCount,
      (_) => List<int?>.filled(DateTime.daysPerWeek, null),
    );

    for (var index = 0; index < currentRoster.days.length; index++) {
      final cell = leadingEmptyCells + index;
      final row = cell ~/ DateTime.daysPerWeek;
      final weekday = cell % DateTime.daysPerWeek;
      rows[row][weekday] = index;
    }

    return rows;
  }

  double _weekendColumnWidth(double gridWidth) {
    final contentWidth = gridWidth - (_gridPadding * 2);
    final normalCellWidth =
        (contentWidth - (_gridSpacing * _weekdayColumns)) /
        (_weekdayColumns + _weekendColumnWidthFactor);

    return normalCellWidth * _weekendColumnWidthFactor;
  }

  Widget _buildBulkActionBar() {
    final selectedCount = _selectedDateKeys.length;
    final editorDoctor = _editorDoctor ?? widget.currentDoctor;

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$selectedCount day${selectedCount == 1 ? '' : 's'} selected',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              onPressed: _clearDateSelection,
              icon: const Icon(Icons.deselect),
              label: const Text('Deselect'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _setSelectedDatesAsVacation,
              icon: const Icon(Icons.beach_access),
              label: const Text('Vacation'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _removeVacationFromSelectedDates,
              icon: const Icon(Icons.event_available),
              label: const Text('Remove vacation'),
            ),
            const SizedBox(width: 8),
            if (_editorMode) ...[
              OutlinedButton.icon(
                onPressed: _setEditorDoctor,
                icon: const Icon(Icons.person),
                label: Text(editorDoctor.firstName),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _setEditorRole,
                icon: const Icon(Icons.assignment_ind),
                label: Text(
                  _editorSlotKind == null
                      ? 'Role'
                      : _slotKindLabel(_editorSlotKind!),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _editorSlotKind == null
                    ? null
                    : () => _assignSelectedDatesToSlotKind(
                        slotKind: _editorSlotKind!,
                        doctor: editorDoctor,
                      ),
                icon: const Icon(Icons.check),
                label: const Text('Apply'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _chooseRoleForSelectedDates,
                icon: const Icon(Icons.assignment_ind),
                label: const Text('Role'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStrip() {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _clearStatusMessage,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  void _handleGridPointerDown(Offset position, Size gridSize) {
    _pointerDownIndex = _indexForGridPosition(position, gridSize);
    _isRangeSelecting = false;
  }

  void _handleGridPointerMove(Offset position, Size gridSize) {
    final startIndex = _pointerDownIndex;
    final currentIndex = _indexForGridPosition(position, gridSize);

    if (startIndex == null || currentIndex == null) {
      return;
    }

    if (currentIndex == startIndex && !_isRangeSelecting) {
      return;
    }

    _isRangeSelecting = true;
    _selectDateRange(startIndex, currentIndex);
  }

  void _handleGridPointerUp(Offset position, Size gridSize) {
    final startIndex = _pointerDownIndex;
    final endIndex = _indexForGridPosition(position, gridSize);
    final openedByTap =
        !_isRangeSelecting && startIndex != null && startIndex == endIndex;

    _resetPointerSelection();

    if (openedByTap) {
      _openDay(currentRoster.days[startIndex]);
    }
  }

  void _resetPointerSelection() {
    _pointerDownIndex = null;
    _isRangeSelecting = false;
  }

  int? _indexForGridPosition(Offset position, Size gridSize) {
    final weekRows = _buildWeekRows();
    final contentWidth = gridSize.width - (_gridPadding * 2);
    final contentHeight = gridSize.height - (_gridPadding * 2);

    if (weekRows.isEmpty || contentWidth <= 0 || contentHeight <= 0) {
      return null;
    }

    final normalCellWidth =
        (contentWidth - (_gridSpacing * _weekdayColumns)) /
        (_weekdayColumns + _weekendColumnWidthFactor);
    final weekendColumnWidth = normalCellWidth * _weekendColumnWidthFactor;
    final rowHeight =
        (contentHeight - (_gridSpacing * (weekRows.length - 1))) /
        weekRows.length;

    final x = position.dx - _gridPadding;
    final y = position.dy - _gridPadding;

    if (x < 0 || y < 0) {
      return null;
    }

    final rowTrack = rowHeight + _gridSpacing;
    final row = y ~/ rowTrack;
    final yInsideRow = y - (row * rowTrack);

    if (row < 0 || row >= weekRows.length || yInsideRow > rowHeight) {
      return null;
    }

    final weekdayTrack = normalCellWidth + _gridSpacing;
    final weekendStart = _weekdayColumns * weekdayTrack;

    if (x < weekendStart) {
      final column = x ~/ weekdayTrack;
      final xInsideCell = x - (column * weekdayTrack);

      if (column < 0 ||
          column >= _weekdayColumns ||
          xInsideCell > normalCellWidth) {
        return null;
      }

      return weekRows[row][column];
    }

    final xInsideWeekend = x - weekendStart;

    if (xInsideWeekend < 0 || xInsideWeekend > weekendColumnWidth) {
      return null;
    }

    final weekendCellHeight = (rowHeight - _gridSpacing) / 2;

    if (yInsideRow <= weekendCellHeight) {
      return weekRows[row][DateTime.saturday - 1];
    }

    if (yInsideRow >= weekendCellHeight + _gridSpacing) {
      return weekRows[row][DateTime.sunday - 1];
    }

    return null;
  }

  void _selectDateRange(int startIndex, int endIndex) {
    final first = startIndex < endIndex ? startIndex : endIndex;
    final last = startIndex < endIndex ? endIndex : startIndex;

    setState(() {
      _selectedDateKeys
        ..clear()
        ..addAll(
          currentRoster.days
              .sublist(first, last + 1)
              .map((day) => _dateKey(day.date)),
        );
    });
  }

  Future<void> _openDay(RosterDay day) async {
    if (day.calendarInfo.isPublicHoliday || day.calendarInfo.isWeekend) {
      return;
    }

    final updatedDay = await Navigator.push<RosterDay>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DayScreen(day: day, currentDoctor: widget.currentDoctor),
      ),
    );

    if (updatedDay != null) {
      _replaceDay(updatedDay);
    }
  }

  void _openMonthlyReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MonthReportScreen(roster: currentRoster, doctors: widget.doctors),
      ),
    );
  }

  void _clearDateSelection() {
    setState(_selectedDateKeys.clear);
  }

  void _setStatusMessage(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _clearStatusMessage() {
    setState(() {
      _statusMessage = null;
    });
  }

  void _setSelectedDatesAsVacation() {
    final selectedDays = _selectedDays();

    if (selectedDays.isEmpty) {
      return;
    }

    final doctor = _currentDoctorFromList();
    final updatedDoctor = doctor.copyWith(
      availabilities: [
        ...doctor.availabilities,
        AvailabilityPeriod(
          start: selectedDays.first.date,
          end: selectedDays.last.date,
          type: AvailabilityType.vacation,
        ),
      ],
    );

    final selectedKeys = _selectedDateKeys.toSet();
    final updatedDays = currentRoster.days.map((day) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        return day;
      }

      return RosterDay(
        calendarInfo: day.calendarInfo,
        slots: day.slots,
        availabilities: day.availabilities,
        assignments: day.assignments
            .where((assignment) => assignment.doctor.id != doctor.id)
            .toList(),
      );
    }).toList();

    setState(() {
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
      _selectedDateKeys.clear();
      if (_editorDoctor?.id == updatedDoctor.id) {
        _editorDoctor = updatedDoctor;
      }
    });

    widget.onDoctorUpdated(updatedDoctor);

    _setStatusMessage(
      'Vacation set for ${selectedDays.length} day'
      '${selectedDays.length == 1 ? '' : 's'}',
    );
  }

  void _removeVacationFromSelectedDates() {
    final selectedDays = _selectedDays();

    if (selectedDays.isEmpty) {
      return;
    }

    final selectedKeys = _selectedDateKeys.toSet();
    final updatedAvailabilities = <AvailabilityPeriod>[];
    var removedDays = 0;
    final doctor = _currentDoctorFromList();

    for (final availability in doctor.availabilities) {
      if (availability.type != AvailabilityType.vacation) {
        updatedAvailabilities.add(availability);
        continue;
      }

      final retainedRanges = _removeSelectedDatesFromPeriod(
        availability,
        selectedKeys,
      );

      removedDays += _countSelectedDaysInPeriod(availability, selectedKeys);
      updatedAvailabilities.addAll(retainedRanges);
    }

    if (removedDays == 0) {
      _clearDateSelection();
      _setStatusMessage('No vacation found on selected days');
      return;
    }

    final updatedDoctor = doctor.copyWith(
      availabilities: updatedAvailabilities,
    );

    setState(() {
      _selectedDateKeys.clear();
      if (_editorDoctor?.id == updatedDoctor.id) {
        _editorDoctor = updatedDoctor;
      }
    });

    widget.onDoctorUpdated(updatedDoctor);

    _setStatusMessage(
      'Vacation removed from $removedDays day'
      '${removedDays == 1 ? '' : 's'}',
    );
  }

  List<AvailabilityPeriod> _removeSelectedDatesFromPeriod(
    AvailabilityPeriod period,
    Set<String> selectedKeys,
  ) {
    final retainedRanges = <AvailabilityPeriod>[];
    DateTime? rangeStart;
    DateTime? previousRetainedDate;

    for (
      var date = _dateOnly(period.start);
      !date.isAfter(_dateOnly(period.end));
      date = date.add(const Duration(days: 1))
    ) {
      final selected = selectedKeys.contains(_dateKey(date));

      if (selected) {
        if (rangeStart != null && previousRetainedDate != null) {
          retainedRanges.add(
            AvailabilityPeriod(
              start: rangeStart,
              end: previousRetainedDate,
              type: period.type,
            ),
          );
        }

        rangeStart = null;
        previousRetainedDate = null;
        continue;
      }

      rangeStart ??= date;
      previousRetainedDate = date;
    }

    if (rangeStart != null && previousRetainedDate != null) {
      retainedRanges.add(
        AvailabilityPeriod(
          start: rangeStart,
          end: previousRetainedDate,
          type: period.type,
        ),
      );
    }

    return retainedRanges;
  }

  int _countSelectedDaysInPeriod(
    AvailabilityPeriod period,
    Set<String> selectedKeys,
  ) {
    var count = 0;

    for (
      var date = _dateOnly(period.start);
      !date.isAfter(_dateOnly(period.end));
      date = date.add(const Duration(days: 1))
    ) {
      if (selectedKeys.contains(_dateKey(date))) {
        count++;
      }
    }

    return count;
  }

  Future<void> _chooseRoleForSelectedDates() async {
    final choices = _slotChoicesForSelectedDays();

    if (choices.isEmpty) {
      _setStatusMessage('No slots available on selected days');
      return;
    }

    final targetDoctor = _editorMode
        ? await _chooseDoctorForBulkAssignment()
        : widget.currentDoctor;

    if (!mounted) {
      return;
    }

    if (targetDoctor == null) {
      return;
    }

    final selectedKind = await _chooseSlotKindForBulkAssignment(choices);

    if (selectedKind == null) {
      return;
    }

    _assignSelectedDatesToSlotKind(
      slotKind: selectedKind,
      doctor: targetDoctor,
    );
  }

  Future<void> _setEditorDoctor() async {
    final doctor = await _chooseDoctorForBulkAssignment();

    if (!mounted || doctor == null) {
      return;
    }

    setState(() {
      _editorDoctor = doctor;
    });
  }

  Future<void> _setEditorRole() async {
    final choices = _slotChoicesForSelectedDays();

    if (choices.isEmpty) {
      _setStatusMessage('No slots available on selected days');
      return;
    }

    final slotKind = await _chooseSlotKindForBulkAssignment(choices);

    if (!mounted || slotKind == null) {
      return;
    }

    setState(() {
      _editorSlotKind = slotKind;
    });
  }

  Future<SlotKind?> _chooseSlotKindForBulkAssignment(
    List<_SlotChoice> choices,
  ) {
    return showModalBottomSheet<SlotKind>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Assign selected days to role')),
              for (final choice in choices)
                ListTile(
                  leading: const Icon(Icons.assignment_ind),
                  title: Text(choice.name),
                  subtitle: Text(choice.area),
                  selected: choice.kind == _editorSlotKind,
                  onTap: () => Navigator.pop(context, choice.kind),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Doctor?> _chooseDoctorForBulkAssignment() {
    return showModalBottomSheet<Doctor>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Assign doctor')),
              for (final doctor in widget.doctors)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(doctor.fullName),
                  subtitle: Text(doctor.rank.name),
                  selected: doctor.id == widget.currentDoctor.id,
                  onTap: () => Navigator.pop(context, doctor),
                ),
            ],
          ),
        );
      },
    );
  }

  String _slotKindLabel(SlotKind kind) {
    switch (kind) {
      case SlotKind.science:
        return 'Science';
      case SlotKind.strokeUnitLeader:
        return 'SUL';
      case SlotKind.strokeUnitTeam1:
        return 'SU1';
      case SlotKind.strokeUnitTeam2:
        return 'SU2';
      case SlotKind.ambulance:
        return 'Ambulance';
      case SlotKind.neurosonology:
        return 'Sono';
      case SlotKind.neurovascularBoard:
        return 'NVB';
      case SlotKind.ofoBoard:
        return 'OFO';
    }
  }

  void _assignSelectedDatesToSlotKind({
    required SlotKind slotKind,
    required Doctor doctor,
  }) {
    final selectedKeys = _selectedDateKeys.toSet();
    final updatedDays = <RosterDay>[];
    int assigned = 0;
    int skipped = 0;
    final failureReasons = <String>{};

    for (final day in currentRoster.days) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        updatedDays.add(day);
        continue;
      }

      final matchingSlots = day.slots.where(
        (slot) => slot.template.kind == slotKind,
      );

      if (matchingSlots.isEmpty) {
        skipped++;
        updatedDays.add(day);
        continue;
      }

      final targetSlot = matchingSlots.first;
      final dayWithRoleCleared = RosterDay(
        calendarInfo: day.calendarInfo,
        slots: day.slots,
        availabilities: day.availabilities,
        assignments: day.assignments
            .where(
              (assignment) =>
                  assignment.slot.id != targetSlot.id &&
                  !_isConflictingAssignmentForDoctor(
                    assignment,
                    targetSlot,
                    doctor,
                  ),
            )
            .toList(),
      );

      final result = AssignmentService().assignDoctorToSlot(
        doctor: doctor,
        slot: targetSlot,
        day: dayWithRoleCleared,
      );

      if (result.success) {
        assigned++;
        updatedDays.add(result.updatedDay!);
      } else {
        skipped++;
        failureReasons.add(result.reason ?? 'Assignment failed');
        updatedDays.add(day);
      }
    }

    setState(() {
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
      if (!_editorMode) {
        _selectedDateKeys.clear();
      }
    });

    final reasonSuffix = failureReasons.isEmpty
        ? ''
        : ' (${failureReasons.take(2).join('; ')})';

    _setStatusMessage(
      'Assigned ${doctor.firstName} on $assigned day'
      '${assigned == 1 ? '' : 's'}, '
      'skipped $skipped$reasonSuffix',
    );
  }

  bool _isConflictingAssignmentForDoctor(
    Assignment assignment,
    DailySlot targetSlot,
    Doctor doctor,
  ) {
    if (assignment.doctor.id != doctor.id) {
      return false;
    }

    final overlaps = assignment.slot.template.timeRange.overlaps(
      targetSlot.template.timeRange,
    );

    if (!overlaps) {
      return false;
    }

    return !DefaultOverlapRules.isAllowed(
      assignment.slot.template.kind,
      targetSlot.template.kind,
    );
  }

  List<_SlotChoice> _slotChoicesForSelectedDays() {
    final selectedKeys = _selectedDateKeys.toSet();
    final choicesByKind = <SlotKind, _SlotChoice>{};

    for (final day in currentRoster.days) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        continue;
      }

      for (final slot in day.slots) {
        choicesByKind.putIfAbsent(
          slot.template.kind,
          () => _SlotChoice(
            kind: slot.template.kind,
            name: slot.template.name,
            area: slot.template.area,
          ),
        );
      }
    }

    final choices = choicesByKind.values.toList();
    choices.sort((a, b) => a.name.compareTo(b.name));
    return choices;
  }

  List<RosterDay> _selectedDays() {
    final selectedKeys = _selectedDateKeys.toSet();
    final days = currentRoster.days
        .where((day) => selectedKeys.contains(_dateKey(day.date)))
        .toList();

    days.sort((a, b) => a.date.compareTo(b.date));
    return days;
  }

  Doctor _currentDoctorFromList() {
    for (final doctor in widget.doctors) {
      if (doctor.id == widget.currentDoctor.id) {
        return doctor;
      }
    }

    return widget.currentDoctor;
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }

  String _formatDateKey(String key) {
    final parts = key.split('-');

    if (parts.length != 3) {
      return key;
    }

    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  void _replaceDay(RosterDay updatedDay) {
    final updatedDays = currentRoster.days.map((day) {
      final sameDate =
          day.date.year == updatedDay.date.year &&
          day.date.month == updatedDay.date.month &&
          day.date.day == updatedDay.date.day;

      return sameDate ? updatedDay : day;
    }).toList();

    setState(() {
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
    });
  }

  // method
  void _showMyAssignmentsDialog() {
    final myAssignments = RosterStatisticsService()
        .getAssignmentsForDoctorInMonth(
          roster: currentRoster,
          doctor: widget.currentDoctor,
        );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('My slots this month'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (myAssignments.isEmpty) const Text('No slots assigned yet.'),
            for (final assignment in myAssignments)
              Text(
                '${assignment.slot.date.day}.${assignment.slot.date.month}. '
                '${assignment.slot.template.name} '
                '(${assignment.slot.template.timeRange.display})',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SlotChoice {
  final SlotKind kind;
  final String name;
  final String area;

  _SlotChoice({required this.kind, required this.name, required this.area});
}
