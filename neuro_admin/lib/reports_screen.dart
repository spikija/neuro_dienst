import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'report_table.dart';
import 'report_export.dart';
import 'report_pdf.dart';
import 'report_print_layout.dart';
import 'localization.dart';
import 'report_print_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

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

  Future<void> export() async {
    final data = report!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportExportDialog(
        report: data,
        orientation: ReportOrientation.portrait,
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
        IconButton(
          onPressed: report != null && !busy && !failed ? export : null,
          tooltip: AdminStrings.of(context).text('Print / PDF'),
          icon: const Icon(Icons.print),
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
  bool busy = false, failed = false, loading = true;
  String? printError;
  late ReportOrientation orientation = widget.orientation;
  Set<String> selected = {};
  final preferences = const ReportPrintPreferences();
  bool get monthly => widget.report.request.layout == ReportLayout.roles;
  bool get canExport => !busy && !loading && (!monthly || selected.isNotEmpty);

  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final value = monthly
        ? await preferences.restore(widget.report)
        : <String>{};
    if (mounted) {
      setState(() {
        selected = value;
        loading = false;
      });
    }
  }

  Future<void> run(bool? print) async {
    if (!canExport) return;
    final strings = AdminStrings.of(context);
    final ids = monthly ? Set<String>.unmodifiable(selected) : null;
    setState(() {
      busy = true;
      failed = false;
      printError = null;
    });
    try {
      if (print == null) {
        final pdf = await buildReportPdf(
          widget.report,
          orientation,
          strings,
          selectedRoleIds: ids,
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const AdminText('Preview'),
            content: SizedBox(
              width: 900,
              height: 650,
              child: PdfPreview(
                initialPageFormat: orientation == ReportOrientation.portrait
                    ? PdfPageFormat.a4
                    : PdfPageFormat.a4.landscape,
                build: (_) async => pdf.bytes,
                allowPrinting: false,
                allowSharing: false,
                canChangePageFormat: false,
                canChangeOrientation: false,
                canDebug: false,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const AdminText('Close'),
              ),
            ],
          ),
        );
      } else {
        await widget.exporter.export(
          widget.report,
          orientation,
          strings,
          print: print,
          selectedRoleIds: ids,
        );
      }
      if (monthly) {
        try {
          await preferences.save(widget.report, ids!);
        } catch (_) {
          if (mounted) {
            setState(() {
              failed = true;
              printError = 'Could not remember print columns locally.';
            });
          }
          return;
        }
      }
      if (mounted && print != null) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          printError = e is ReportPrintLayoutException ? e.message : null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const AdminText('Print / PDF'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<ReportOrientation>(
                key: const ValueKey('print-orientation'),
                initialValue: orientation,
                decoration: InputDecoration(
                  labelText: AdminStrings.of(context).text('Orientation'),
                ),
                items: [
                  for (final value in ReportOrientation.values)
                    DropdownMenuItem(
                      value: value,
                      child: AdminText(
                        value == ReportOrientation.portrait
                            ? 'A4 Portrait'
                            : 'A4 Landscape',
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => orientation = value);
                      },
              ),
              if (loading) const LinearProgressIndicator(),
              if (monthly && !loading) ...[
                const SizedBox(height: 12),
                AdminText(
                  '{selected} of {total} roles',
                  args: {
                    'selected': selected.length,
                    'total': widget.report.availableRoleColumns.length,
                  },
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(
                              () => selected = widget
                                  .report
                                  .availableRoleColumns
                                  .map((c) => c.id)
                                  .toSet(),
                            ),
                      child: const AdminText('Select all'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => selected = {}),
                      child: const AdminText('Select none'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(
                              () => selected = usedReportRoleIds(widget.report),
                            ),
                      child: const AdminText('Only roles used this month'),
                    ),
                  ],
                ),
                for (final column in widget.report.availableRoleColumns)
                  CheckboxListTile(
                    key: ValueKey('print-role-${column.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(column.label),
                    value: selected.contains(column.id),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            if (value == true) {
                              selected.add(column.id);
                            } else {
                              selected.remove(column.id);
                            }
                          }),
                  ),
                if (selected.isEmpty)
                  const AdminText('Select at least one role to export.'),
              ],
              if (failed)
                AdminText(
                  printError ??
                      'Operation failed. Check your access and connection.',
                ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const AdminText('Cancel'),
        ),
        TextButton(
          onPressed: canExport ? () => run(null) : null,
          child: const AdminText('Preview'),
        ),
        FilledButton.icon(
          onPressed: canExport ? () => run(false) : null,
          icon: const Icon(Icons.picture_as_pdf),
          label: const AdminText('Save PDF'),
        ),
        FilledButton.icon(
          onPressed: canExport ? () => run(true) : null,
          icon: const Icon(Icons.print),
          label: const AdminText('Print'),
        ),
      ],
    ),
  );
}
