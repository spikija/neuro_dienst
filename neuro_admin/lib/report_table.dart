import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';

/// One report, with a fixed corner/header and a date rail sharing the body's
/// vertical viewport. Only the header's horizontal position needs mirroring.
class ReportTable extends StatefulWidget {
  final ReportDocument report;
  const ReportTable({super.key, required this.report});
  @override
  State<ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<ReportTable> {
  final _horizontal = ScrollController();
  final _header = ScrollController();
  final _vertical = ScrollController();
  bool _syncing = false;
  @override
  void initState() {
    super.initState();
    _horizontal.addListener(() => _sync(_horizontal, _header));
    _header.addListener(() => _sync(_header, _horizontal));
  }

  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _header.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final style = Theme.of(context).textTheme.bodyMedium!;
    final labels = [
      ...report.columns.map((c) => c.label),
      'Absences / holiday',
    ];
    final widths = [...report.columns.map((_) => 180.0), 260.0];
    final values = [
      for (final row in report.rows)
        [
          for (final c in report.columns)
            reportCellText(row.cells[c.id]!, report.request.layout),
          reportNotes(report, row),
        ],
    ];
    double height(List<String> texts) {
      var result = 48.0;
      for (var i = 0; i < texts.length; i++) {
        final painter = TextPainter(
          text: TextSpan(text: texts[i], style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: widths[i] - 20);
        result = math.max(result, painter.height + 20);
        painter.dispose();
      }
      return result;
    }

    final heights = values.map(height).toList();
    final headerHeight = height(labels);
    Widget cell(
      String text,
      double width,
      double height, {
      Key? key,
      bool heading = false,
      String? tooltip,
    }) => Container(
      key: key,
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: heading
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : null,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Tooltip(
        message: tooltip ?? text,
        child: Text(text, style: style),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            cell(
              'Date',
              120,
              headerHeight,
              key: const ValueKey('report-corner'),
              heading: true,
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('report-header'),
                controller: _header,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      cell(labels[i], widths[i], headerHeight, heading: true),
                  ],
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Scrollbar(
                controller: _vertical,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
                child: SingleChildScrollView(
                  controller: _vertical,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          for (var r = 0; r < report.rows.length; r++)
                            cell(
                              '${report.rows[r].date}',
                              120,
                              heights[r],
                              key: ValueKey('report-date-$r'),
                            ),
                        ],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          key: const ValueKey('report-body'),
                          child: Column(
                            children: [
                              for (var r = 0; r < values.length; r++)
                                Row(
                                  children: [
                                    for (var c = 0; c < widths.length; c++)
                                      cell(
                                        values[r][c],
                                        widths[c],
                                        heights[r],
                                        key: ValueKey('report-cell-$r-$c'),
                                        tooltip: c < report.columns.length
                                            ? report
                                                  .rows[r]
                                                  .cells[report.columns[c].id]!
                                                  .assignments
                                                  .map(
                                                    (a) =>
                                                        '${a.doctor.fullName}: ${a.duty.role.name} (${a.state.name})',
                                                  )
                                                  .join('\n')
                                            : null,
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String reportNotes(ReportDocument report, ReportRow row) => [
  if (row.calendar.publicHolidayName != null) row.calendar.publicHolidayName!,
  ...{
    for (final cell in row.cells.values)
      for (final entry in cell.absencesByPhysician.entries)
        '${report.physicianLabels[entry.key] ?? "Unknown physician"}: ${entry.value.map((a) => a.label).join(', ')}',
  },
].join('\n');
