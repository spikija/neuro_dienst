import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'workspace_dialogs.dart';
import 'reports_screen.dart';

import 'assignment_candidate_panel.dart';
import 'calendar_day_grid.dart';
import 'calendar_selection.dart';
import 'calendar_theme.dart';

class RosterDashboard extends StatefulWidget {
  final AssignmentMutationService? mutations;
  final RosterReader reader;
  final RosterGenerationService? generation;
  final AssignmentRemovalService? removals;
  final ReportingService? reporting;
  final Future<void> Function() onSignOut;
  final PreviewServiceFactory? previewServiceFactory;

  const RosterDashboard({
    super.key,
    required this.reader,
    required this.onSignOut,
    this.previewServiceFactory,
    this.mutations,
    this.generation,
    this.removals,
    this.reporting,
  });

  @override
  State<RosterDashboard> createState() => _RosterDashboardState();
}

class _RosterDashboardState extends State<RosterDashboard> {
  List<RosterChoice> _months = [];
  RosterChoice? _selected;
  RosterSnapshot? _snapshot;
  final _selection = CalendarSelection();
  final WorkloadReadService _workloads = const RecordedWorkloadService();
  DateTime? _detailDate;
  String? _doctorId;
  String? _roleId;
  MonthAssignability? _assignability;
  bool _validityFailed = false;
  bool get _assignmentMode =>
      !_removalMode && _roleId != null && _doctorId != null;

  void _resetAssignability() {
    _assignability = null;
    _validityFailed = false;
    _selection.restrictTo(_assignmentMode ? <DateTime>[] : null);
  }

  void _choosePhysician(String? id) {
    if (_doctorId == id) return;
    setState(() {
      _doctorId = id;
      _removalMode = false;
      _resetAssignability();
    });
  }

  void _chooseRole(String? id) {
    if (_roleId == id) return;
    setState(() {
      _roleId = id;
      _resetAssignability();
    });
  }

  bool _removalMode = false;
  bool _loading = true;
  bool _applying = false;
  String? _error;
  int _request = 0;
  int _snapshotRevision = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({String? targetMonthId}) async {
    final request = ++_request;
    final requestedId = targetMonthId ?? _selected?.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final months = await widget.reader.listMonths();
      final selected =
          months.where((month) => month.id == requestedId).firstOrNull ??
          months.firstOrNull;
      final data = selected == null
          ? null
          : await widget.reader.loadMonth(selected);
      if (!mounted || request != _request) return;
      setState(() {
        _months = months;
        if (_selected?.id != data?.month.id) _selection.clear();
        _selected = data?.month ?? selected;
        _snapshot = data;
        _snapshotRevision++;
        _detailDate = _selection.lastVisited ?? data?.days.firstOrNull?.date;
        if (data == null || !data.doctors.any((d) => d.id == _doctorId)) {
          _doctorId = null;
        }
        if (data == null || !previewRoles(data).any((r) => r.id == _roleId)) {
          _roleId = null;
        }
        _loading = false;
        _resetAssignability();
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = error is FormatException
            ? error.message
            : 'Could not load roster data. Check your connection and access, then retry.';
      });
    }
  }

  Future<void> _chooseMonth(RosterChoice month) async {
    await _refresh(targetMonthId: month.id);
  }

  List<Widget> _toolbar() => [
    PopupMenuButton<String>(
      tooltip: 'Selection actions',
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Selection ?'),
      ),
      onSelected: (action) async {
        if (action == 'removeRole' || action == 'removeAll') {
          await _remove(action == 'removeAll');
          return;
        }
        setState(() {
          if (action == 'removal') {
            _removalMode = !_removalMode;
            _resetAssignability();
          }
          if (action == 'working' && _selected != null) {
            _selection.selectWorkingDays(_selected!.year, _selected!.month);
          }
          if (action == 'assignable') {
            _selection.replace(
              _assignability?.assignableDates.map((d) => d.asDateOnlyUtc) ?? [],
            );
          }
          if (action == 'clear') {
            _selection.clear();
            _detailDate = null;
          }
          _detailDate = _selection.lastVisited;
        });
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'working',
          enabled: _selected != null,
          child: const Text('Select all working days'),
        ),
        PopupMenuItem(
          value: 'assignable',
          enabled: _assignability != null && !_removalMode,
          child: const Text('Select all assignable days'),
        ),
        const PopupMenuItem(value: 'clear', child: Text('Clear selection')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'removal',
          checked: _removalMode,
          child: const Text('Select occupied days for removal'),
        ),
        PopupMenuItem(
          value: 'removeRole',
          enabled: _canRemove(false),
          child: const Text('Unassign selected role'),
        ),
        PopupMenuItem(
          value: 'removeAll',
          enabled: _canRemove(true),
          child: Text(
            'Unassign all roles on selected days',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    ),
    PopupMenuButton<String>(
      tooltip: 'Roster actions',
      child: const Padding(padding: EdgeInsets.all(8), child: Text('Roster ?')),
      onSelected: (a) => _generate(a == 'regenerate'),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'create',
          enabled: widget.generation != null && !_loading,
          child: const Text('Create month roster'),
        ),
        PopupMenuItem(
          value: 'regenerate',
          enabled:
              widget.generation != null &&
              _snapshot?.month.phase == RosterPhase.draft &&
              _snapshot?.contentVersion != null,
          child: const Text('Regenerate draft roster'),
        ),
      ],
    ),
    TextButton(
      onPressed: widget.reporting == null || _snapshot == null
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReportsScreen(
                  service: widget.reporting!,
                  roster: _snapshot!.contentVersion == null
                      ? RosterVersion.unversioned(_snapshot!.month.id)
                      : RosterVersion(
                          _snapshot!.month.id,
                          _snapshot!.contentVersion!,
                        ),
                ),
              ),
            ),
      child: const Text('Reports'),
    ),
    const Tooltip(
      message:
          'Click to select a day. Drag to select a range. In assignment mode, valid days toggle and drag adds valid days. Use removal selection to select occupied days.',
      child: Icon(Icons.help_outline, size: 20),
    ),
    if (_removalMode) const Chip(label: Text('Removal selection')),
  ];
  bool _canRemove(bool all) =>
      widget.removals != null &&
      _snapshot?.contentVersion != null &&
      _snapshot?.month.phase != RosterPhase.published &&
      _selection.dates.isNotEmpty &&
      (all || _roleId != null) &&
      _snapshot!.days
          .expand((d) => d.assignments)
          .any(
            (a) =>
                _selection.dates.contains(calendarDate(a.duty.date)) &&
                (all || a.duty.role.id == _roleId),
          );
  Future<void> _remove(bool all) async {
    final preview = AssignmentRemovalPreview(
      _snapshot!,
      _selection.dates.map(HospitalDate.fromCalendarComponents),
      scope: all ? RemovalScope.all : RemovalScope.role,
      roleId: all ? null : _roleId,
    );
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          RemovalDialog(preview: preview, service: widget.removals!),
    );
    if (mounted) await _refresh();
  }

  Future<void> _generate(bool regenerate) async {
    final result = await showDialog<RosterRevision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GenerationDialog(
        service: widget.generation!,
        existing: regenerate ? _snapshot : null,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      await _refresh(targetMonthId: result.version.rosterId);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.onSignOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not sign out. Please retry.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return AbsorbPointer(
      absorbing: _applying || (_loading && snapshot != null),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('NeuroDienst Admin'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_months.isNotEmpty)
                    DropdownButton<String>(
                      key: const ValueKey('month-selector'),
                      value: _selected?.id,
                      items: [
                        for (final month in _months)
                          DropdownMenuItem(
                            value: month.id,
                            child: Text(month.label),
                          ),
                      ],
                      onChanged: _loading
                          ? null
                          : (id) => _chooseMonth(
                              _months.firstWhere((month) => month.id == id),
                            ),
                    ),
                  if (_selected != null)
                    Chip(label: Text(_phaseLabel(_selected!.phase))),
                  if (_selected != null)
                    Tooltip(
                      message: _phaseMeaning(_selected!.phase),
                      child: const Icon(Icons.info_outline, size: 18),
                    ),
                  ..._toolbar(),
                ],
              ),
              const SizedBox(height: 12),
              if (_loading && snapshot != null) const LinearProgressIndicator(),
              if (_error != null && snapshot != null)
                MaterialBanner(
                  content: Text(_error!),
                  actions: [
                    TextButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              Expanded(
                child: _loading && snapshot == null
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null && snapshot == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _refresh,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : snapshot == null
                    ? const Center(
                        child: Text('No rosters have been generated yet.'),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          // Preserve a desktop split even in a narrow resized window.
                          final width = constraints.maxWidth < 1180
                              ? 1180.0
                              : constraints.maxWidth;
                          return SingleChildScrollView(
                            physics: _selection.isDragging
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: width,
                              height: constraints.maxHeight,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 10,
                                    child: _calendar(snapshot),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 5,
                                    child: _dailyRoster(snapshot),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 5,
                                    child: _roleId != null && !_removalMode
                                        ? AssignmentCandidatePanel(
                                            key: ValueKey(
                                              'assignment-preview-$_snapshotRevision',
                                            ),
                                            snapshot: snapshot,
                                            role: previewRoles(snapshot)
                                                .firstWhere(
                                                  (role) => role.id == _roleId,
                                                ),
                                            dates: _selection.dates
                                                .map(
                                                  HospitalDate
                                                      .fromCalendarComponents,
                                                )
                                                .toSet(),
                                            physicianId: _doctorId,
                                            onPhysician: _choosePhysician,
                                            onValidationFailed: () {
                                              if (mounted &&
                                                  identical(
                                                    _snapshot,
                                                    snapshot,
                                                  )) {
                                                setState(
                                                  () => _validityFailed = true,
                                                );
                                              }
                                            },
                                            onCancel: () => _chooseRole(null),
                                            onAssignability:
                                                (validity, preselect) {
                                                  if (!mounted ||
                                                      !identical(
                                                        _snapshot,
                                                        snapshot,
                                                      ) ||
                                                      validity
                                                              .preview
                                                              .request
                                                              .roleId !=
                                                          _roleId ||
                                                      validity
                                                              .preview
                                                              .request
                                                              .physicianId !=
                                                          _doctorId) {
                                                    return;
                                                  }
                                                  setState(() {
                                                    _assignability = validity;
                                                    _selection.restrictTo(
                                                      validity.assignableDates
                                                          .map(
                                                            (d) =>
                                                                d.asDateOnlyUtc,
                                                          ),
                                                      preselect: preselect,
                                                    );
                                                  });
                                                },
                                            serviceFactory:
                                                widget.previewServiceFactory,
                                            mutations: widget.mutations,
                                            onBusyChanged: (busy) {
                                              if (mounted) {
                                                setState(
                                                  () => _applying = busy,
                                                );
                                              }
                                            },
                                            onReload: (stale) async {
                                              await _refresh();
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(
                                                this.context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    _error != null
                                                        ? (stale
                                                              ? 'Roster changed; reload failed. Retry loading before previewing.'
                                                              : 'Assignments saved, but reload failed. Retry loading to refresh workload.')
                                                        : stale
                                                        ? 'Roster changed. Data reloaded; review the updated preview.'
                                                        : 'Assignments saved. Roster and workload refreshed.',
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        : _workload(snapshot),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Read-only totals include all roster phases. Times use Europe/Vienna; calendar dates follow the stored roster day.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _calendar(RosterSnapshot snapshot) {
    final roster = snapshot.month;
    final days = {for (final day in snapshot.days) calendarDate(day.date): day};
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: CustomScrollView(
          key: const ValueKey('roster-calendar-scroll'),
          physics: _selection.isDragging
              ? const NeverScrollableScrollPhysics()
              : null,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_assignmentMode)
                    Text(
                      _assignability == null
                          ? _validityFailed
                                ? 'Month validation failed. Reload to retry.'
                                : 'Checking month assignability...'
                          : '${_assignability!.assignableDates.length} assignable | ${_selection.dates.length} selected | ${_assignability!.blockedDates.length} blocked | ${_assignability!.warningDates.length} warning-only',
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final role in previewRoles(snapshot))
                        Tooltip(
                          message: role.name,
                          child: ChoiceChip(
                            key: ValueKey('role-chip-${role.id}'),
                            label: Text(role.code),
                            selected: _roleId == role.id,
                            onSelected: (selected) =>
                                _chooseRole(selected ? role.id : null),
                          ),
                        ),
                    ],
                  ),
                  if (roster.phase == RosterPhase.published)
                    const Text(
                      'Published roster requires a new revision before editing.',
                    ),
                  if (roster.phase == RosterPhase.locked)
                    const Text('Locked roster: corrections require a reason.'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final label in [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ])
                        Expanded(child: Center(child: Text(label))),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final weeks =
                    (DateTime.utc(roster.year, roster.month).weekday -
                        1 +
                        DateTime.utc(roster.year, roster.month + 1, 0).day +
                        6) ~/
                    7;
                final height =
                    (constraints.viewportMainAxisExtent -
                            constraints.precedingScrollExtent)
                        .clamp(weeks * 68.0, double.infinity);
                return SliverToBoxAdapter(
                  child: SizedBox(
                    height: height,
                    child: CalendarDayGrid(
                      key: ValueKey(roster.id),
                      year: roster.year,
                      month: roster.month,
                      selection: _selection,
                      onChanged: () => setState(() {
                        _detailDate = _selection.lastVisited;
                      }),
                      cellBuilder: (date, selected) =>
                          _dateCell(date, days[date], selected),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyRoster(RosterSnapshot snapshot) {
    final roster = snapshot.month;
    final days = {for (final day in snapshot.days) calendarDate(day.date): day};
    final selectedDay =
        days[_selection.dates.length == 1
            ? _selection.dates.single
            : _detailDate];
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          key: const ValueKey('daily-roster-pane'),
          children: [
            Text('Daily roster', style: Theme.of(context).textTheme.titleLarge),
            if (_selection.dates.length > 1)
              Text('${_selection.dates.length} target dates'),
            const Divider(height: 24),
            if (_roleId != null && _selection.dates.isNotEmpty) ...[
              const Text(
                'Current role occupants (no replacements)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final date in (_selection.dates.toList()..sort()))
                Text('${_dateLabel(date)}: ${_occupants(days[date])}'),
              const Divider(),
            ],
            if (selectedDay == null)
              Text(
                _detailDate == null
                    ? 'Select a generated day to inspect its duties.'
                    : 'No generated roster day for ${_dateLabel(_detailDate!)}.',
              )
            else ...[
              Text(
                '${selectedDay.date.day}.${roster.month}.${roster.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (selectedDay.calendarInfo.isPublicHoliday)
                Text(
                  selectedDay.calendarInfo.publicHolidayName ??
                      'Public holiday',
                ),
              if (selectedDay.slots.isEmpty)
                const Text('No duties on this day.'),
              for (final slot in selectedDay.slots)
                _dutyTile(slot, selectedDay),
              const Divider(),
              const Text('Absences / day markers'),
              for (final doctor in snapshot.doctors)
                for (final period in doctor.availabilities.where(
                  (p) => p.includes(selectedDay.date),
                ))
                  Text('${doctor.fullName}: ${period.label}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateCell(DateTime date, StoredDay? day, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    final colors =
        Theme.of(context).extension<CalendarColors>() ??
        CalendarColors.forScheme(scheme);
    final key = HospitalDate.fromCalendarComponents(date);
    final holiday = AustrianHolidays.day(key).publicHolidayName;
    final valid = _assignability?.assignableDates.contains(key) ?? false;
    final warning = _assignability?.warningDates.contains(key) ?? false;
    final blocked = _assignability?.blockedDates.contains(key) ?? false;
    final result = _assignability?.preview.results
        .where((r) => r.date == key)
        .firstOrNull;
    final occupants =
        day?.assignments
            .where((a) => _roleId == null || a.duty.role.id == _roleId)
            .toList() ??
        [];
    final status = blocked
        ? 'Blocked'
        : warning
        ? 'Assignable with warning'
        : valid
        ? 'Assignable'
        : _assignmentMode
        ? 'No matching slot or awaiting validation'
        : 'Calendar day';
    final assignments =
        day?.assignments
            .where((a) => _doctorId == null || a.doctor.id == _doctorId)
            .length ??
        0;
    return Tooltip(
      message: [
        status,
        ?holiday,
        if (selected) 'Selected',
        ...?result?.errors.map((e) => e.message),
        ...?result?.warnings.map((w) => w.message),
        if (occupants.isNotEmpty)
          'Current: ${occupants.map((a) => a.doctor.fullName).join(', ')}',
      ].join('\n'),
      child: Semantics(
        label: status,
        child: AnimatedContainer(
          key: ValueKey('assignability-$key'),
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: selected
                ? colors.selected
                : valid
                ? colors.tint
                : blocked ||
                      day?.calendarInfo.isWeekend == true ||
                      day?.calendarInfo.isPublicHoliday == true
                ? scheme.surfaceContainerHighest
                : scheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected || valid
                  ? colors.assignable
                  : scheme.outlineVariant,
              width: selected
                  ? 3
                  : valid
                  ? 2
                  : 1,
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: blocked
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                      if (holiday != null)
                        Icon(
                          Icons.celebration_outlined,
                          size: 14,
                          color: scheme.tertiary,
                        ),
                      if (selected)
                        Icon(Icons.check, size: 14, color: colors.assignable),
                      if (warning)
                        Icon(
                          Icons.warning_amber,
                          size: 14,
                          color: colors.warning,
                        ),
                      if (blocked)
                        Icon(Icons.block, size: 14, color: scheme.error),
                    ],
                  ),
                  Text(
                    day == null ? 'No roster day' : '$assignments duties',
                    style: const TextStyle(fontSize: 10),
                  ),
                  if (occupants.isNotEmpty)
                    Icon(
                      Icons.person_outline,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _occupants(StoredDay? day) {
    final slots =
        day?.slots.where((slot) => slot.role.id == _roleId).toList() ?? [];
    if (slots.isEmpty) return 'No slot';
    final people = day!.assignments
        .where((a) => a.duty.role.id == _roleId)
        .map((a) => a.doctor.fullName)
        .join(', ');
    return '${slots.length > 1 ? 'Multiple slots - ambiguous. ' : ''}${people.isEmpty ? 'Unassigned' : people}';
  }

  Widget _dutyTile(StoredDuty slot, StoredDay day) {
    final assignments = day.assignments
        .where((a) => a.duty.id == slot.id)
        .toList();
    final start = ViennaSchedulingTime.localTime(slot.startsAt);
    final end = ViennaSchedulingTime.localTime(slot.endsAt);
    final names = assignments
        .map((a) => '${a.doctor.fullName} (${a.state.name})')
        .join(', ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      selected: _roleId == slot.role.id,
      onTap: () => _chooseRole(slot.role.id),
      title: Text('${slot.role.code}: ${slot.role.name}'),
      subtitle: Text(
        '${_timestamp(start)} - ${_timestamp(end)}\n${names.isEmpty ? 'Unassigned' : names}',
      ),
      trailing: Text('${assignments.length}/${slot.capacity}'),
    );
  }

  Widget _workload(RosterSnapshot snapshot) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Physicians / workload',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('Select a physician to inspect workload by stored role.'),
          if (_doctorId != null)
            TextButton(
              onPressed: () => _choosePhysician(null),
              child: const Text('Clear physician selection'),
            ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [
                if (snapshot.doctors.isEmpty)
                  const Text('No physicians available.'),
                for (final doctor in snapshot.doctors)
                  _doctorTile(snapshot, doctor),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _doctorTile(RosterSnapshot snapshot, Doctor doctor) {
    final month = snapshot.month;
    final current = _workloads.forPhysician(
      snapshot,
      doctor,
      WorkloadWindow(
        DateTime.utc(month.year, month.month),
        DateTime.utc(month.year, month.month + 1),
      ),
    );
    final selected = _doctorId == doctor.id;
    final history = _workloads.forPhysician(
      snapshot,
      doctor,
      WorkloadWindow(snapshot.historyStart, snapshot.historyEnd),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          selected: selected,
          title: Text(
            '${doctor.fullName}${snapshot.inactiveDoctorIds.contains(doctor.id) ? ' (inactive)' : ''}',
          ),
          subtitle: Text(
            '${current.assignments} assignments / ${current.assignedDays} days',
          ),
          onTap: () => _choosePhysician(doctor.id),
        ),
        if (selected) ...[
          Text('Rank: ${doctor.rank.name}'),
          Text(
            'Current month: ${current.confirmed} confirmed / ${current.provisional} provisional',
          ),
          ..._roleTotals(current),
          const Divider(),
          Text(
            'Previous 90 days: ${_dateLabel(snapshot.historyStart)} to ${_dateLabel(snapshot.historyEnd.subtract(const Duration(days: 1)))}',
          ),
          Text(
            '${snapshot.loadedHistoryDates.length}/90 roster dates available. Missing dates may mean incomplete history.',
          ),
          Text('${history.recordedDuty24Days} recorded 24-hour duty days'),
          Text('${history.recordedWeekendDuty24Days} on Saturdays/Sundays'),
          Text(
            '${history.daysFor(WorkloadCategory.station)} station-role days',
          ),
          Text(
            '${history.daysFor(WorkloadCategory.ambulance)} ambulance-role days',
          ),
          Text(
            '${history.daysFor(WorkloadCategory.science)} science-role days',
          ),
          Text('${history.daysFor(WorkloadCategory.other)} other-role days'),
          const Text(
            '24-hour counts use recorded day markers, not duty-role assignments.',
          ),
          Text(
            '${history.confirmed} confirmed / ${history.provisional} provisional assignments',
          ),
          ..._roleTotals(history),
          const Text(
            'Categories use SUL/SU1/SU2, AMB and SCI. Other codes remain separate. All phases and assignment states are included.',
          ),
          const Divider(),
        ],
      ],
    );
  }

  List<Widget> _roleTotals(PhysicianWorkload workload) => [
    if (workload.roles.isEmpty) const Text('No recorded role assignments.'),
    for (final item in workload.roles)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '${item.role.code} - ${item.role.name}: ${item.days} days / ${item.assignments} assignments',
        ),
      ),
  ];
}

String _timestamp(DateTime value) =>
    '${value.day}.${value.month}. ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _dateLabel(DateTime value) => value.toIso8601String().split('T').first;

String _phaseLabel(RosterPhase phase) => switch (phase) {
  RosterPhase.draft => 'Draft',
  RosterPhase.openForSelection => 'Open for selection',
  RosterPhase.locked => 'Locked',
  RosterPhase.published => 'Published',
};

String _phaseMeaning(RosterPhase phase) => switch (phase) {
  RosterPhase.draft => 'Administrator working plan',
  RosterPhase.openForSelection => 'Selection period — not published',
  RosterPhase.locked => 'Selection closed — not published',
  RosterPhase.published => 'Authoritative roster for end users',
};
