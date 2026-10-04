import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../extensions/time_formatting.dart';
import '../l10n/app_localizations.dart';
import '../services/supabase_doctor_service.dart';
import '../services/supabase_roster_service.dart';

class ViewerRosterData {
  final List<RosterSummary> rosters;
  final String? selectedId;
  final RosterMonth? roster;

  const ViewerRosterData({
    required this.rosters,
    required this.selectedId,
    required this.roster,
  });
}

/// A separate read-only route: no physician impersonation or editing callbacks.
class ViewerRosterScreen extends StatefulWidget {
  final Future<ViewerRosterData> Function(String? rosterId)? loadData;
  final VoidCallback? onSignOut;

  const ViewerRosterScreen({super.key, this.loadData, this.onSignOut});

  @override
  State<ViewerRosterScreen> createState() => _ViewerRosterScreenState();
}

class _ViewerRosterScreenState extends State<ViewerRosterScreen> {
  late Future<ViewerRosterData> _future;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ViewerRosterData> _load() async {
    if (widget.loadData != null) return widget.loadData!(_selectedId);
    final service = SupabaseRosterService();
    final rosters = await service.listRosters();
    if (rosters.isEmpty) {
      return const ViewerRosterData(
        rosters: [],
        selectedId: null,
        roster: null,
      );
    }
    final now = DateTime.now();
    final selected =
        rosters.where((r) => r.id == _selectedId).firstOrNull ??
        rosters
            .where((r) => r.year == now.year && r.month == now.month)
            .firstOrNull ??
        rosters.first;
    final doctors = await SupabaseDoctorService().loadActiveDoctors();
    final roster = await service.loadRoster(
      year: selected.year,
      month: selected.month,
      doctors: doctors,
    );
    return ViewerRosterData(
      rosters: rosters,
      selectedId: selected.id,
      roster: roster,
    );
  }

  void _reload([String? selectedId]) {
    setState(() {
      if (selectedId != null) _selectedId = selectedId;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('viewerRoster')),
        actions: [
          IconButton(
            tooltip: l10n.t('refreshCalendar'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: l10n.t('signOut'),
            onPressed:
                widget.onSignOut ??
                () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.t('viewerReadOnly')),
          ),
          Expanded(
            child: FutureBuilder<ViewerRosterData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.t('rosterCouldNotBeLoaded')),
                        OutlinedButton(
                          onPressed: _reload,
                          child: Text(l10n.t('retry')),
                        ),
                      ],
                    ),
                  );
                }
                final data = snapshot.data!;
                if (data.rosters.isEmpty) {
                  return Center(child: Text(l10n.t('noGeneratedRostersYet')));
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: data.selectedId,
                        items: [
                          for (final summary in data.rosters)
                            DropdownMenuItem(
                              value: summary.id,
                              child: Text(
                                '${l10n.t('month.${summary.month}')} ${summary.year}',
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _reload(value);
                        },
                      ),
                    ),
                    Expanded(
                      child: data.roster == null
                          ? Center(
                              child: Text(l10n.t('rosterCouldNotBeLoaded')),
                            )
                          : ListView.builder(
                              key: ValueKey(data.selectedId),
                              itemCount: data.roster!.days.length,
                              itemBuilder: (_, index) {
                                final day = data.roster!.days[index];
                                return ExpansionTile(
                                  key: ValueKey(day.date),
                                  title: Text(
                                    '${day.date.day}.${day.date.month}.${day.date.year}',
                                  ),
                                  subtitle: Text(
                                    day.calendarInfo.publicHolidayName ??
                                        (day.calendarInfo.isWeekend
                                            ? l10n.t('weekend')
                                            : ''),
                                  ),
                                  children: [
                                    if (day.slots.isEmpty)
                                      ListTile(
                                        title: Text(l10n.t('viewerNoDuties')),
                                      ),
                                    for (final slot in day.slots)
                                      ListTile(
                                        title: Text(slot.template.name),
                                        subtitle: Text(
                                          [
                                            slot.template.timeRange.display,
                                            _assignedNames(day, slot, l10n),
                                          ].join('\n'),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _assignedNames(RosterDay day, DailySlot slot, AppLocalizations l10n) {
    final names =
        day.assignments
            .where((assignment) => assignment.slot.id == slot.id)
            .map((assignment) => assignment.doctor.fullName)
            .toList()
          ..sort();
    return names.isEmpty ? l10n.t('viewerUnassigned') : names.join(', ');
  }
}
