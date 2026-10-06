import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import 'data/roster_reader.dart';
import 'data/workload.dart';

class RosterDashboard extends StatefulWidget {
  final RosterReader reader;
  final Future<void> Function() onSignOut;

  const RosterDashboard({
    super.key,
    required this.reader,
    required this.onSignOut,
  });

  @override
  State<RosterDashboard> createState() => _RosterDashboardState();
}

class _RosterDashboardState extends State<RosterDashboard> {
  List<RosterChoice> _months = [];
  RosterChoice? _selected;
  RosterSnapshot? _snapshot;
  int? _day;
  String? _doctorId;
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
        _selected = data?.month ?? selected;
        _snapshot = data;
        _day = data?.days.firstOrNull?.date.day;
        _doctorId = null;
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
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            height: constraints.maxHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 2, child: _calendar(snapshot)),
                                const SizedBox(width: 16),
                                Expanded(child: _workload(snapshot)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Read-only totals include all roster phases. Times are local; calendar dates follow the stored roster day.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendar(RosterSnapshot snapshot) {
    final roster = snapshot.month;
    final days = {for (final day in snapshot.days) day.date.day: day};
    final offset = DateTime(roster.year, roster.month).weekday - 1;
    final dayCount = DateTime(roster.year, roster.month + 1, 0).day;
    final selectedDay = days[_day];
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: [
            Text(
              'Roster calendar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
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
            for (var week = 0; week < (offset + dayCount + 6) ~/ 7; week++)
              Row(
                children: [
                  for (var weekday = 0; weekday < 7; weekday++)
                    Expanded(
                      child: _dateCell(
                        week * 7 + weekday - offset + 1,
                        dayCount,
                        days,
                      ),
                    ),
                ],
              ),
            const Divider(height: 24),
            if (selectedDay == null)
              const Text('Select a generated day to inspect its duties.')
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

  Widget _dateCell(int number, int count, Map<int, StoredDay> days) {
    if (number < 1 || number > count) return const SizedBox(height: 64);
    final day = days[number];
    final assignments =
        day?.assignments
            .where((a) => _doctorId == null || a.doctor.id == _doctorId)
            .length ??
        0;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: SizedBox(
        height: 64,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(2),
            backgroundColor: _day == number
                ? Theme.of(context).colorScheme.secondaryContainer
                : day?.calendarInfo.isWeekend == true ||
                      day?.calendarInfo.isPublicHoliday == true
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: day == null
              ? null
              : () => setState(() {
                  _day = number;
                }),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$number'),
                Text(
                  '$assignments duties',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dutyTile(StoredDuty slot, StoredDay day) {
    final assignments = day.assignments
        .where((a) => a.duty.id == slot.id)
        .toList();
    final start = slot.startsAt.toLocal();
    final end = slot.endsAt.toLocal();
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
    final current = workloadFor(
      snapshot,
      doctor,
      WorkloadWindow(
        DateTime.utc(month.year, month.month),
        DateTime.utc(month.year, month.month + 1),
      ),
    );
    final selected = _doctorId == doctor.id;
    final history = workloadFor(
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
          const Text(
            '24-hour counts use recorded day markers, not duty-role assignments.',
          ),
          Text(
            '${history.confirmed} confirmed / ${history.provisional} provisional assignments',
          ),
          ..._roleTotals(history),
          const Text(
            'Grouped station/ambulance/science metrics await verified role classification.',
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
