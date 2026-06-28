import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('monthlyReport'))),
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
            return Center(child: Text(l10n.t('noGeneratedRostersYet')));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: SegmentedButton<MonthReportLayout>(
                  segments: [
                    ButtonSegment(
                      value: MonthReportLayout.roles,
                      icon: const Icon(Icons.view_column),
                      label: Text(l10n.t('roles')),
                    ),
                    ButtonSegment(
                      value: MonthReportLayout.physicians,
                      icon: const Icon(Icons.badge),
                      label: Text(l10n.t('physicians')),
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
                      title: Text(
                        '${_monthName(roster.month, l10n)} ${roster.year}',
                      ),
                      subtitle: Text(_phaseLabel(roster.phase, l10n)),
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
        SnackBar(
          content: Text(
            AppLocalizations.of(context).t('rosterCouldNotBeLoaded'),
          ),
        ),
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
              label: Text(AppLocalizations.of(context).t('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

String _phaseLabel(RosterPhase phase, AppLocalizations l10n) {
  switch (phase) {
    case RosterPhase.draft:
      return l10n.t('phaseDraft');
    case RosterPhase.openForSelection:
      return l10n.t('phaseOpenForSelection');
    case RosterPhase.locked:
      return l10n.t('phaseLocked');
    case RosterPhase.published:
      return l10n.t('phasePublished');
  }
}

String _monthName(int month, AppLocalizations l10n) {
  if (month < 1 || month > 12) {
    return l10n.fill('monthNumber', {'month': month});
  }

  return l10n.t('month.$month');
}
