import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calendar_selection.dart';

/// Mouse selection is captured by the whole grid, including moves outside it.
/// Selection is the rectangle between anchor and current cell, not pointer path.
class CalendarDayGrid extends StatefulWidget {
  final DateTime? focusedDate;
  final ValueChanged<DateTime>? onFocusedDateChanged;
  final FocusNode? focusNode;
  final int year;
  final int month;
  final CalendarSelection selection;
  final VoidCallback onChanged;
  final Widget Function(DateTime date, bool selected) cellBuilder;

  const CalendarDayGrid({
    super.key,
    this.focusedDate,
    this.onFocusedDateChanged,
    this.focusNode,
    required this.year,
    required this.month,
    required this.selection,
    required this.onChanged,
    required this.cellBuilder,
  });

  @override
  State<CalendarDayGrid> createState() => _CalendarDayGridState();
}

class _CalendarDayGridState extends State<CalendarDayGrid> {
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode(debugLabel: 'Roster calendar');
  DateTime? _localFocused;
  final _dayKeys = <int, GlobalKey>{};
  void _revealFocusedDay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pointer != null || !_focusNode.hasFocus) return;
      if (_focused.year != widget.year || _focused.month != widget.month) {
        return;
      }
      final target = _dayKeys[_focused.day]?.currentContext;
      if (target == null) return;
      final scrollable = Scrollable.maybeOf(target, axis: Axis.vertical);
      final viewport = scrollable?.context.findRenderObject();
      final cell = target.findRenderObject();
      if (viewport is! RenderBox || cell is! RenderBox) return;
      final viewportTop = viewport.localToGlobal(Offset.zero).dy;
      final cellTop = cell.localToGlobal(Offset.zero).dy;
      if (cellTop < viewportTop ||
          cellTop + cell.size.height > viewportTop + viewport.size.height) {
        Scrollable.ensureVisible(target, alignment: .5);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _revealFocusedDay();
  }

  DateTime get _focused => widget.focusedDate ?? _localFocused ?? _date(1);
  void _focusDate(DateTime date) {
    _focusNode.requestFocus();
    setState(() => _localFocused = date);
    widget.onFocusedDateChanged?.call(date);
    _revealFocusedDay();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -7,
      LogicalKeyboardKey.arrowDown => 7,
      _ => 0,
    };
    if (delta != 0) {
      _focusDate(_focused.add(Duration(days: delta)));
      return KeyEventResult.handled;
    }
    // Enter/Space retain the existing selection action, scoped to this month.
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) &&
        _focused.year == widget.year &&
        _focused.month == widget.month) {
      _select(_focused);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double _rowHeight = 68.0;
  int get _weeks => (_offset + _count + 6) ~/ 7;
  final _gridKey = GlobalKey();
  int? _pointer;

  int get _offset => DateTime.utc(widget.year, widget.month).weekday - 1;
  int get _count => DateTime.utc(widget.year, widget.month + 1, 0).day;

  @override
  void didUpdateWidget(CalendarDayGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedDate != widget.focusedDate) _revealFocusedDay();
    if (oldWidget.year != widget.year ||
        oldWidget.month != widget.month ||
        oldWidget.selection != widget.selection) {
      oldWidget.selection.endDrag();
      _pointer = null;
    }
  }

  @override
  void dispose() {
    widget.selection.endDrag();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  RenderBox get _box =>
      _gridKey.currentContext!.findRenderObject()! as RenderBox;

  Rect _rect(int day) {
    final index = _offset + day - 1;
    final width = _box.size.width / 7;
    return Rect.fromLTWH(
      index % 7 * width,
      index ~/ 7 * _rowHeight,
      width,
      _rowHeight,
    ).deflate(2);
  }

  DateTime _date(int day) => DateTime.utc(widget.year, widget.month, day);

  void _down(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton ||
        _pointer != null) {
      return;
    }
    final position = _box.globalToLocal(event.position);
    for (var day = 1; day <= _count; day++) {
      if (_rect(day).contains(position)) {
        _focusDate(_date(day));
        _pointer = event.pointer;
        widget.selection.beginDrag(_date(day));
        widget.onChanged();
        return;
      }
    }
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if (event.buttons != kPrimaryMouseButton || !widget.selection.isDragging) {
      _end(event);
      return;
    }
    _extend(event.position);
  }

  void _extend(Offset globalPosition) {
    final position = _box.globalToLocal(globalPosition);
    // Outside the grid, retain the last rectangle. Padding is a valid endpoint
    // inside the grid but never contributes an out-of-month date.
    if (!(Offset.zero & _box.size).contains(position)) return;
    widget.selection.enterCell(
      (position.dy / _rowHeight).floor(),
      (position.dx / (_box.size.width / 7)).floor(),
    );
    final visited = CalendarGridMonth(widget.year, widget.month).dateAt(
      (position.dy / _rowHeight).floor(),
      (position.dx / (_box.size.width / 7)).floor(),
    );
    if (visited != null) _focusDate(visited);
    widget.onChanged();
  }

  void _end(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerUpEvent && widget.selection.isDragging) {
      _extend(event.position);
    }
    _pointer = null;
    widget.selection.endDrag();
    widget.onChanged();
  }

  void _select(DateTime date) {
    _focusDate(date);
    widget.selection.select(date);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focusNode,
    onKeyEvent: _key,
    child: LayoutBuilder(
      builder: (context, constraints) {
        _rowHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight / _weeks).clamp(68.0, double.infinity)
            : 68.0;
        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _end,
          onPointerCancel: _end,
          // Claim mouse pans so an enclosing scroll view does not move the grid.
          child: GestureDetector(
            supportedDevices: const {PointerDeviceKind.mouse},
            onPanStart: (_) {},
            onPanUpdate: (_) {},
            child: SelectionContainer.disabled(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Column(
                  key: _gridKey,
                  children: [
                    for (var week = 0; week < _weeks; week++)
                      Row(
                        children: [
                          for (var weekday = 0; weekday < 7; weekday++)
                            Expanded(
                              child: _cell(week * 7 + weekday - _offset + 1),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _cell(int day) {
    if (day < 1 || day > _count) return SizedBox(height: _rowHeight);
    final date = _date(day);
    final selected = widget.selection.dates.contains(date);
    return SizedBox(
      key: _dayKeys.putIfAbsent(day, () => GlobalKey()),
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          key: ValueKey(date),
          button: true,
          enabled: true,
          hint: widget.selection.canSelect(date)
              ? null
              : "Bulk selection unavailable",
          selected: selected,
          focused: calendarDate(_focused) == date,
          label: date.toIso8601String().split('T').first,
          onTap: () => _select(date),
          child: GestureDetector(
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
            },
            onTap: () => _select(date),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.cellBuilder(date, selected),
                if (calendarDate(_focused) == date)
                  IgnorePointer(
                    child: Container(
                      key: ValueKey(
                        'calendar-focus-${date.toIso8601String().split('T').first}',
                      ),
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      alignment: Alignment.topRight,
                      child: Icon(
                        Icons.center_focus_strong,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
