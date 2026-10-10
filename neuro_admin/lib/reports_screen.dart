import 'report_table.dart';
import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';

class ReportsScreen extends StatefulWidget {
  final ReportingService service;
  final RosterVersion roster;
  const ReportsScreen({super.key, required this.service, required this.roster});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportLayout layout = ReportLayout.roles;
  late Future<ReportDocument> data = widget.service.load(
    ReportRequest(widget.roster, layout),
  );
  void reload() => setState(() {
    data = widget.service.load(ReportRequest(widget.roster, layout));
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reports'),
      actions: [
        IconButton(
          onPressed: reload,
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload report',
        ),
      ],
    ),
    body: Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final mode in [ReportLayout.roles, ReportLayout.physicians])
              ChoiceChip(
                label: Text(
                  mode == ReportLayout.roles ? 'By role' : 'By physician',
                ),
                selected: layout == mode,
                onSelected: (_) {
                  layout = mode;
                  reload();
                },
              ),
          ],
        ),
        Expanded(
          child: FutureBuilder<ReportDocument>(
            future: data,
            builder: (context, state) {
              if (state.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: reload,
                    child: const Text(
                      'Report unavailable or changed. Retry (reload roster if changed).',
                    ),
                  ),
                );
              }
              if (!state.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final report = state.data!;
              return ReportTable(report: report);
            },
          ),
        ),
      ],
    ),
  );
}
