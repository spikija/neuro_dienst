import 'role_indicators.dart';
import 'report_presentation.dart';
import 'localization.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'absence_icons.dart';

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
    final presentation = ReportPresentation(report, AdminStrings.of(context));
    final labels = presentation.headings;
    final widths = [...report.columns.map((_) => 180.0), 260.0];
    final values = report.rows.map(presentation.cells).toList();
    InlineSpan absenceText(
      List<ReportAbsenceEntry> entries, {
      String? holiday,
    }) => TextSpan(
      children: [
        if (holiday != null) TextSpan(text: holiday),
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0 || holiday != null) const TextSpan(text: '\n'),
          TextSpan(text: entries[i].surname),
          for (final period in entries[i].periods) ...[
            const TextSpan(text: ' '),
            if (period.type == AvailabilityType.efDay)
              const TextSpan(text: 'EF')
            else
              TextSpan(
                text: String.fromCharCode(absenceIcon(period.type).codePoint),
                semanticsLabel: presentation.strings.text(period.label),
                style: TextStyle(
                  fontFamily: absenceIcon(period.type).fontFamily,
                  package: absenceIcon(period.type).fontPackage,
                ),
              ),
          ],
        ],
      ],
    );
    final contents = [
      for (var r = 0; r < report.rows.length; r++)
        [
          for (var c = 0; c < values[r].length; c++)
            if (c == report.columns.length)
              absenceText(
                presentation.absences(report.rows[r]),
                holiday: report.rows[r].calendar.publicHolidayName == null
                    ? null
                    : presentation.holiday(
                        report.rows[r].calendar.publicHolidayName!,
                      ),
              )
            else if (report.request.layout == ReportLayout.physicians &&
                report
                    .rows[r]
                    .cells[report.columns[c].id]!
                    .absencesByPhysician
                    .isNotEmpty)
              absenceText(
                presentation.cellAbsences(
                  report.rows[r].cells[report.columns[c].id]!,
                ),
              )
            else
              TextSpan(text: values[r][c]),
        ],
    ];
    double height(List<InlineSpan> texts) {
      var result = 48.0;
      for (var i = 0; i < texts.length; i++) {
        final painter = TextPainter(
          text: TextSpan(children: [texts[i]], style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: widths[i] - 20);
        result = math.max(result, painter.height + 20);
        painter.dispose();
      }
      return result;
    }

    final heights = contents.map(height).toList();
    final headerHeight = height([
      for (final label in labels) TextSpan(text: label),
    ]);
    Widget cell(
      String text,
      double width,
      double height, {
      Key? key,
      bool heading = false,
      String? tooltip,
      Color? roleColor,
      InlineSpan? content,
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
          bottom: BorderSide(
            color: roleColor ?? Theme.of(context).dividerColor,
            width: roleColor == null ? 1 : 2,
          ),
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Tooltip(
        message: tooltip ?? text,
        child: content == null
            ? Text(text, style: style)
            : Text.rich(content, style: style),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            cell(
              AdminStrings.of(context).text('Date'),
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
                      cell(
                        labels[i],
                        widths[i],
                        headerHeight,
                        heading: true,
                        roleColor:
                            report.request.layout == ReportLayout.roles &&
                                i < report.columns.length
                            ? roleDisplayColor(
                                context,
                                report.columns[i].id,
                                report.columns[i].colorKey,
                              )
                            : null,
                      ),
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
                              europeanReportDate(report.rows[r].date),
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
                                        content: contents[r][c],
                                        tooltip: c < report.columns.length
                                            ? report
                                                  .rows[r]
                                                  .cells[report.columns[c].id]!
                                                  .assignments
                                                  .map(
                                                    (a) =>
                                                        '${a.doctor.fullName}: ${a.duty.role.name} (${AdminStrings.of(context).text(a.state.name)})',
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
