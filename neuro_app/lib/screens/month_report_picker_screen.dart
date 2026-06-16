import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../services/supabase_roster_service.dart';
import 'month_report_screen.dart';

class MonthReportPickerScreen extends StatefulWidget {
  final List<Doctor> doctors;

  const MonthReportPickerScreen({super.key, required this.doctors});

  @override
  State<MonthReportPickerScreen> createState() =>
      _MonthReportPickerScreenState();
}

class _MonthReportPickerScreenState extends State<MonthReportPickerScreen> {
  late Future<List<RosterSummary>> _rostersFuture;
  MonthReportLayout _layout = MonthReportLayout.roles;

  @override
  void initState() {
    super.initState();
    _rostersFuture = SupabaseRosterService().listRosters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly report')),
      body: FutureBuilder<List<RosterSummary>>(
        future: _rostersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ReportPickerErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final rosters = snapshot.data ?? [];

          if (rosters.isEmpty) {
            return const Center(child: Text('No generated rosters yet.'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: SegmentedButton<MonthReportLayout>(
                  segments: const [
                    ButtonSegment(
                      value: MonthReportLayout.roles,
                      icon: Icon(Icons.view_column),
                      label: Text('Roles'),
                    ),
                    ButtonSegment(
                      value: MonthReportLayout.physicians,
                      icon: Icon(Icons.badge),
                      label: Text('Physicians'),
                    ),
                  ],
                  selected: {_layout},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _layout = selection.first;
                    });
                  },
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: rosters.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final roster = rosters[index];

                    return ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: Text('${_monthName(roster.month)} ${roster.year}'),
                      subtitle: Text(_phaseLabel(roster.phase)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openReport(roster),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reload() {
    setState(() {
      _rostersFuture = SupabaseRosterService().listRosters();
    });
  }

  Future<void> _openReport(RosterSummary summary) async {
    final service = SupabaseRosterService();
    final reportRoles = await service.listReportRoles(onlyPrintable: true);
    final roster = await service.loadRoster(
      year: summary.year,
      month: summary.month,
      doctors: widget.doctors,
    );

    if (!mounted) {
      return;
    }

    if (roster == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Roster could not be loaded.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonthReportScreen(
          roster: roster,
          doctors: widget.doctors,
          reportRoles: reportRoles,
          layout: _layout,
        ),
      ),
    );
  }
}

class _ReportPickerErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ReportPickerErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _phaseLabel(RosterPhase phase) {
  switch (phase) {
    case RosterPhase.draft:
      return 'Draft';
    case RosterPhase.openForSelection:
      return 'Open for selection';
    case RosterPhase.locked:
      return 'Locked';
    case RosterPhase.published:
      return 'Published';
  }
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
