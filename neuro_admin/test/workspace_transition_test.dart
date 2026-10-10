import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'workspace_test.dart' show TestWorkspace, display;

class TransitionReader implements RosterReader {
  final initial = previewFixture(contentVersion: 1);
  Completer<List<RosterChoice>>? pending;
  @override
  Future<List<RosterChoice>> listMonths() async =>
      pending == null ? [initial.month] : pending!.future;
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) async =>
      month.id == initial.month.id
      ? initial
      : RosterSnapshot(
          month,
          [],
          initial.doctors,
          {},
          [],
          {},
          contentVersion: 1,
        );
}

void main() {
  testWidgets('refresh keeps calendar mounted and failure stays local', (
    tester,
  ) async {
    final reader = TransitionReader();
    await display(
      tester,
      RosterDashboard(reader: reader, onSignOut: () async {}),
    );
    final calendar = tester.element(find.byType(CalendarDayGrid));
    reader.pending = Completer();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.byType(CalendarDayGrid), findsOneWidget);
    expect(tester.element(find.byType(CalendarDayGrid)), same(calendar));
    reader.pending!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDayGrid), findsOneWidget);
    expect(find.textContaining('Could not load roster data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new roster waits for atomic month and snapshot transition', (
    tester,
  ) async {
    final reader = TransitionReader();
    final service = TestWorkspace();
    await display(
      tester,
      RosterDashboard(
        reader: reader,
        generation: service,
        onSignOut: () async {},
      ),
    );
    await tester.tap(find.byTooltip('Roster actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create month roster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    reader.pending = Completer();
    await tester.tap(find.text('Create roster'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarDayGrid), findsOneWidget);
    final request = service.generated.single.plan.request;
    reader.pending!.complete([
      RosterChoice('new', request.year, request.month, RosterPhase.draft),
      reader.initial.month,
    ]);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('month-selector')),
          )
          .value,
      'new',
    );
    expect(tester.takeException(), isNull);
  });
}
