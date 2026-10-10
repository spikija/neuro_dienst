import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'report_table.dart';
import 'report_export.dart';
import 'report_pdf.dart';
import 'localization.dart';

class ReportsScreen extends StatefulWidget {
  final ReportingService service;
  final RosterVersion roster;
  final ReportExportService exporter;
  const ReportsScreen({
    super.key,
    required this.service,
    required this.roster,
    this.exporter = const DesktopReportExport(),
  });
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportLayout layout = ReportLayout.roles;
  ReportDocument? report;
  bool busy = true, failed = false;
  int request = 0;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final current = ++request;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final result = await widget.service.load(
        ReportRequest(widget.roster, layout),
      );
      if (mounted && current == request) setState(() => report = result);
    } catch (_) {
      if (mounted && current == request) setState(() => failed = true);
    } finally {
      if (mounted && current == request) setState(() => busy = false);
    }
  }

  Future<void> export(ReportOrientation orientation) async {
    final data = report!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportExportDialog(
        report: data,
        orientation: orientation,
        exporter: widget.exporter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AdminText('Reports'),
      actions: [
        const LanguageButton(),
        PopupMenuButton<ReportOrientation>(
          enabled: report != null && !busy && !failed,
          tooltip: AdminStrings.of(context).text('Print / PDF'),
          icon: const Icon(Icons.print),
          onSelected: export,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: ReportOrientation.portrait,
              child: AdminText('A4 Portrait'),
            ),
            PopupMenuItem(
              value: ReportOrientation.landscape,
              child: AdminText('A4 Landscape'),
            ),
          ],
        ),
        IconButton(
          onPressed: busy ? null : reload,
          icon: const Icon(Icons.refresh),
          tooltip: AdminStrings.of(context).text('Reload report'),
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
                label: AdminText(
                  mode == ReportLayout.roles ? 'By role' : 'By physician',
                ),
                selected: layout == mode,
                onSelected: busy
                    ? null
                    : (_) {
                        layout = mode;
                        reload();
                      },
              ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (failed)
          MaterialBanner(
            content: const AdminText(
              'Report unavailable or changed. Retry (reload roster if changed).',
            ),
            actions: [
              TextButton(onPressed: reload, child: const AdminText('Retry')),
            ],
          ),
        if (report != null)
          Expanded(
            child: ReportTable(
              key: ValueKey(report!.request.layout),
              report: report!,
            ),
          ),
      ],
    ),
  );
}

class ReportExportDialog extends StatefulWidget {
  final ReportDocument report;
  final ReportOrientation orientation;
  final ReportExportService exporter;
  const ReportExportDialog({
    super.key,
    required this.report,
    required this.orientation,
    required this.exporter,
  });
  @override
  State<ReportExportDialog> createState() => _ReportExportDialogState();
}

class _ReportExportDialogState extends State<ReportExportDialog> {
  bool busy = false, failed = false;
  Future<void> run(bool print) async {
    final strings = AdminStrings.of(context);
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      await widget.exporter.export(
        widget.report,
        widget.orientation,
        strings,
        print: print,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: AdminText(
        widget.orientation == ReportOrientation.portrait
            ? 'A4 Portrait'
            : 'A4 Landscape',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed)
            const AdminText(
              'Operation failed. Check your access and connection.',
            ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const AdminText('Close'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => run(false),
          icon: const Icon(Icons.picture_as_pdf),
          label: const AdminText('Save PDF'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => run(true),
          icon: const Icon(Icons.print),
          label: const AdminText('Print'),
        ),
      ],
    ),
  );
}
