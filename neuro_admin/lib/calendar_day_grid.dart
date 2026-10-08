import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calendar_selection.dart';

/// Mouse selection is captured by the whole grid, including moves outside it.
/// Selection is the rectangle between anchor and current cell, not pointer path.
class CalendarDayGrid extends StatefulWidget {
  final int year;
  final int month;
  final CalendarSelection selection;
  final VoidCallback onChanged;
  final Widget Function(DateTime date, bool selected) cellBuilder;

  const CalendarDayGrid({
    super.key,
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
  static const _rowHeight = 68.0;
  final _gridKey = GlobalKey();
  int? _pointer;

  int get _offset => DateTime.utc(widget.year, widget.month).weekday - 1;
  int get _count => DateTime.utc(widget.year, widget.month + 1, 0).day;

  @override
  void didUpdateWidget(CalendarDayGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    widget.selection.select(date);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Listener(
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
              for (var week = 0; week < (_offset + _count + 6) ~/ 7; week++)
                Row(
                  children: [
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(child: _cell(week * 7 + weekday - _offset + 1)),
                  ],
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _cell(int day) {
    if (day < 1 || day > _count) return const SizedBox(height: _rowHeight);
    final date = _date(day);
    final selected = widget.selection.dates.contains(date);
    return SizedBox(
      height: _rowHeight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Semantics(
          key: ValueKey(date),
          button: true,
          selected: selected,
          label: date.toIso8601String().split('T').first,
          onTap: () => _select(date),
          child: _KeyboardDay(
            onActivate: () => _select(date),
            child: widget.cellBuilder(date, selected),
          ),
        ),
      ),
    );
  }
}

class _KeyboardDay extends StatefulWidget {
  final VoidCallback onActivate;
  final Widget child;
  const _KeyboardDay({required this.onActivate, required this.child});

  @override
  State<_KeyboardDay> createState() => _KeyboardDayState();
}

class _KeyboardDayState extends State<_KeyboardDay> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    onShowFocusHighlight: (value) => setState(() => _focused = value),
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onActivate();
          return null;
        },
      ),
    },
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: _focused
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.child,
    ),
  );
}
