import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart'
    show ViennaSchedulingTime, HospitalDate, previewRoles;

import 'assignment_candidate_panel.dart';
import 'calendar_day_grid.dart';
import 'calendar_selection.dart';
import 'data/roster_reader.dart';
import 'data/workload.dart';
import 'data/workload_category.dart';

class RosterDashboard extends StatefulWidget {
  final RosterReader reader;
  final Future<void> Function() onSignOut;
  final PreviewServiceFactory? previewServiceFactory;

  const RosterDashboard({
    super.key,
    required this.reader,
    required this.onSignOut,
    this.previewServiceFactory,
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
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _snapshot = null;
    });
    try {
      final months = await widget.reader.listMonths();
      final selected =
          months.where((month) => month.id == _selected?.id).firstOrNull ??
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
        _detailDate = _selection.lastVisited ?? data?.days.firstOrNull?.date;
        if (data == null || !data.doctors.any((d) => d.id == _doctorId)) {
          _doctorId = null;
        }
        if (data == null || !previewRoles(data).any((r) => r.id == _roleId)) {
          _roleId = null;
        }
        _loading = false;
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
    setState(() {
      _selection.clear();
      _detailDate = null;
      _doctorId = null;
      _roleId = null;
      _selected = month;
    });
    await _refresh();
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
    return Scaffold(
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
                if (_selected != null) Text(_phaseMeaning(_selected!.phase)),
                const Text('Read-only: no roster changes can be made here.'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
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
                        final width = constraints.maxWidth < 760
                            ? 760.0
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
                                Expanded(flex: 3, child: _calendar(snapshot)),
                                const SizedBox(width: 16),
                                Expanded(
                                  flex: 2,
                                  child:
                                      _roleId != null &&
                                          _selection.dates.isNotEmpty
                                      ? AssignmentCandidatePanel(
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
                                          onPhysician: (id) =>
                                              setState(() => _doctorId = id),
                                          onCancel: () =>
                                              setState(() => _roleId = null),
                                          serviceFactory:
                                              widget.previewServiceFactory,
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
    );
  }

  Widget _calendar(RosterSnapshot snapshot) {
    final roster = snapshot.month;
    final days = {for (final day in snapshot.days) calendarDate(day.date): day};
    final selectedDay = days[_detailDate];
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          key: const ValueKey('roster-calendar-scroll'),
          physics: _selection.isDragging
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            Text(
              'Roster calendar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${_selection.dates.length} ${_selection.dates.length == 1 ? 'day' : 'days'} selected',
            ),
            const Text(
              'Click a day or drag a rectangle to select calendar days.',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selection.selectWorkingDays(roster.year, roster.month);
                    _detailDate = _selection.lastVisited;
                  }),
                  child: const Text('Select all working days'),
                ),
                TextButton(
                  onPressed: _selection.dates.isEmpty
                      ? null
                      : () => setState(() {
                          _selection.clear();
                          _detailDate = null;
                        }),
                  child: const Text('Clear selection'),
                ),
              ],
            ),
            const Text(
              'Monday–Friday only; public holidays may be included.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...[
              DropdownButtonFormField<String>(
                key: ValueKey('role-selector-$_roleId'),
                initialValue: _roleId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Duty role for preview',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final role in previewRoles(snapshot))
                    DropdownMenuItem(
                      value: role.id,
                      child: Text(
                        '${role.code}: ${role.name}${role.isActive == false ? ' (inactive)' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _selection.dates.isEmpty
                    ? null
                    : (id) => setState(() => _roleId = id),
              ),
              if (roster.phase == RosterPhase.published)
                const Text(
                  'Published rosters require a new revision before editing.',
                ),
              if (roster.phase == RosterPhase.locked)
                const Text(
                  'Locked roster: a correction reason would be required.',
                ),
              const SizedBox(height: 8),
            ],
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
            CalendarDayGrid(
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
    final assignments =
        day?.assignments
            .where((a) => _doctorId == null || a.doctor.id == _doctorId)
            .length ??
        0;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : day?.calendarInfo.isWeekend == true ||
                  day?.calendarInfo.isPublicHoliday == true
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${date.day}'),
              Text(
                day == null ? 'No roster day' : '$assignments duties',
                style: const TextStyle(fontSize: 10),
              ),
            ],
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
              onPressed: () => setState(() {
                _doctorId = null;
              }),
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
          onTap: () => setState(() {
            _doctorId = doctor.id;
          }),
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
