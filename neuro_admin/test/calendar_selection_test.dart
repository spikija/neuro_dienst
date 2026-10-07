import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/calendar_selection.dart';
import 'package:neuro_admin/roster_dashboard.dart';

import 'phase_one_test.dart' show FakeReader;

DateTime date(int day) => DateTime.utc(2026, 10, day);
Finder cell(int day) => find.byKey(ValueKey(date(day)));

void main() {
  test(
    'single selection replaces dates and normalizes wall-calendar components',
    () {
      final selection = CalendarSelection();
      selection.beginDrag(DateTime(2026, 10, 2, 23, 45));
      selection.enter(DateTime.utc(2026, 10, 2, 8));
      selection.enter(date(3));
      selection.enter(date(1));
      expect(selection.dates, {date(1), date(2), date(3)});
      expect(
        selection.dates.every((value) => value.isUtc && value.hour == 0),
        isTrue,
      );
      expect(() => selection.dates.add(date(7)), throwsUnsupportedError);
      selection.endDrag();
      selection.enter(date(4));
      expect(selection.isDragging, isFalse);
      expect(selection.dates, hasLength(3));
      selection.select(date(5));
      expect(selection.dates, {date(5)});
      selection.clear();
      expect(selection.dates, isEmpty);
      expect(selection.lastVisited, isNull);
      expect(selection.isDragging, isFalse);
    },
  );

  testWidgets(
    'mouse drag captures fast, backward and cross-week paths; release and cancel stop it',
    (tester) async {
      final selection = CalendarSelection();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Column(
                  children: [
                    CalendarDayGrid(
                      year: 2026,
                      month: 10,
                      selection: selection,
                      onChanged: () => setState(() {}),
                      cellBuilder: (date, selected) => Text('${date.day}'),
                    ),
                    const SizedBox(height: 1000),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(cell(2)));
      await mouse.down(tester.getCenter(cell(2)));
      await tester.pump();
      expect(selection.dates, {date(2)});
      expect(selection.isDragging, isTrue);
      final origin = tester.getTopLeft(cell(2));
      await mouse.moveTo(tester.getCenter(cell(4)));
      await tester.pump();
      expect(selection.dates, {date(2), date(3), date(4)});
      await mouse.moveTo(tester.getCenter(cell(11)));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(cell(8)));
      await tester.pump();
      expect(selection.dates, {
        date(2),
        date(3),
        date(4),
        date(8),
        date(9),
        date(10),
        date(11),
      });
      expect(
        tester.getTopLeft(cell(2)),
        origin,
        reason: 'Dragging must not scroll the calendar',
      );
      await mouse.moveTo(tester.getCenter(cell(11)));
      await mouse.moveTo(tester.getCenter(cell(8)));
      await tester.pump();
      expect(selection.dates, hasLength(7));
      await mouse.up();
      expect(selection.isDragging, isFalse);
      await mouse.moveTo(tester.getCenter(cell(20)));
      expect(selection.dates, hasLength(7));
      await mouse.down(tester.getCenter(cell(1)));
      await tester.pump();
      expect(selection.dates, {date(1)});
      await mouse.moveTo(Offset(tester.getCenter(cell(1)).dx, -20));
      await mouse.up();
      await tester.pump();
      expect(selection.isDragging, isFalse);
      await mouse.moveTo(tester.getCenter(cell(3)));
      expect(selection.dates, {date(1)});
      await mouse.down(tester.getCenter(cell(3)));
      await mouse.cancel();
      await tester.pump();
      expect(selection.isDragging, isFalse);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selection is local, survives physician selection, ignores right click, clears on month change',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final reader = FakeReader();
      await tester.pumpWidget(
        MaterialApp(
          home: RosterDashboard(reader: reader, onSignOut: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      final grid = tester.widget<CalendarDayGrid>(find.byType(CalendarDayGrid));
      final reads = reader.calls;
      final loads = List<String>.of(reader.selected);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(cell(1)));
      await mouse.down(tester.getCenter(cell(1)));
      await mouse.up();
      await tester.pump();
      expect(find.text('1 day selected'), findsOneWidget);
      expect(tester.widget<Semantics>(cell(1)).properties.selected, isTrue);
      await mouse.down(tester.getCenter(cell(2)));
      await mouse.moveTo(tester.getCenter(cell(4)));
      await mouse.up();
      await tester.pump();
      expect(grid.selection.dates, {date(2), date(3), date(4)});
      expect(find.text('3 days selected'), findsOneWidget);
      expect(tester.widget<Semantics>(cell(1)).properties.selected, isFalse);
      expect(
        find.text('No generated roster day for 2026-10-04.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ada Test (inactive)'));
      await tester.pumpAndSettle();
      expect(find.text('0 station-role days'), findsOneWidget);
      expect(find.text('1 other-role days'), findsOneWidget);
      expect(grid.selection.dates, {date(2), date(3), date(4)});
      final rightMouse = await tester.createGesture(
        pointer: 9,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await rightMouse.down(tester.getCenter(cell(7)));
      await rightMouse.up();
      await rightMouse.removePointer();
      await tester.pump();
      expect(grid.selection.dates, {date(2), date(3), date(4)});
      expect(reader.calls, reads);
      expect(
        reader.selected,
        loads,
        reason: 'Selection performs no backend calls',
      );
      await mouse.removePointer();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09').last);
      await tester.pumpAndSettle();
      expect(find.text('0 days selected'), findsOneWidget);
      expect(grid.selection.dates, isEmpty);
      expect(grid.selection.isDragging, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small desktop window scrolls normally after releasing a selection',
    (tester) async {
      tester.view.physicalSize = const Size(800, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: RosterDashboard(reader: FakeReader(), onSignOut: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(cell(1)));
      await mouse.down(tester.getCenter(cell(1)));
      await mouse.moveTo(tester.getCenter(cell(4)));
      await tester.pump();
      final calendar = tester.widget<ListView>(
        find.ancestor(
          of: find.byType(CalendarDayGrid),
          matching: find.byType(ListView),
        ),
      );
      expect(calendar.physics, isA<NeverScrollableScrollPhysics>());
      await mouse.up();
      await mouse.removePointer();
      await tester.pump();
      expect(find.text('4 days selected'), findsOneWidget);
      final beforeScroll = tester.getTopLeft(cell(1)).dy;
      await tester.dragFrom(tester.getCenter(cell(1)), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(cell(1)).dy, lessThan(beforeScroll));
      expect(tester.takeException(), isNull);
    },
  );
}
