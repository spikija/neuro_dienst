import 'package:flutter/material.dart';

import 'localization.dart';

/// Two dividers resize adjacent panes, keeping each pane usable at its minimum.
class ResizableWorkspace extends StatefulWidget {
  final Widget calendar;
  final Widget dailyRoster;
  final Widget physicians;

  const ResizableWorkspace({
    super.key,
    required this.calendar,
    required this.dailyRoster,
    required this.physicians,
  });

  @override
  State<ResizableWorkspace> createState() => _ResizableWorkspaceState();
}

class _ResizableWorkspaceState extends State<ResizableWorkspace> {
  double _calendarShare = .48;
  double _physiciansShare = .29;
  static const _dividerWidth = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth - 2 * _dividerWidth;
      final calendar = (_calendarShare * available).clamp(
        520.0,
        available - 570.0,
      );
      final physicians = (_physiciansShare * available).clamp(
        320.0,
        available - calendar - 250.0,
      );
      final daily = available - calendar - physicians;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: calendar, child: widget.calendar),
          _divider('calendar-physicians-divider', (delta) {
            final next = (calendar + delta).clamp(
              520.0,
              calendar + physicians - 320.0,
            );
            setState(() {
              _calendarShare = next / available;
              _physiciansShare = (physicians + calendar - next) / available;
            });
          }),
          SizedBox(width: physicians, child: widget.physicians),
          _divider('physicians-roster-divider', (delta) {
            setState(() {
              _calendarShare = calendar / available;
              _physiciansShare =
                  (physicians + delta).clamp(
                    320.0,
                    daily + physicians - 250.0,
                  ) /
                  available;
            });
          }),
          SizedBox(width: daily, child: widget.dailyRoster),
        ],
      );
    },
  );

  Widget _divider(String id, ValueChanged<double> onDrag) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: Tooltip(
      message: AdminStrings.of(context).text('Drag to resize columns'),
      child: GestureDetector(
        key: ValueKey(id),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: _dividerWidth,
          child: Center(
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
