import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/auth/session_gate.dart';
import 'package:neuro_admin/data/roster_reader.dart';
import 'package:neuro_admin/data/workload.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const month = RosterChoice('month', 2026, 10, RosterPhase.draft);

RosterSnapshot fixture({
  bool missingDoctor = false,
  String phase = 'published',
}) => decodeRoster(
  month,
  doctors: [
    {
      'id': 'doctor',
      'first_name': 'Ada',
      'last_name': 'Test',
      'rank': 'consultant',
      'is_active': false,
      'capabilities': [],
    },
  ],
  rosterRows: [
    {'id': 'month', 'phase': phase},
    {'id': 'old', 'phase': 'locked'},
  ],
  days: [
    {
      'id': 'day',
      'roster_id': 'month',
      'date': '2026-10-01',
      'is_weekend': false,
      'is_public_holiday': false,
    },
    {
      'id': 'history',
      'roster_id': 'old',
      'date': '2026-09-05',
      'is_weekend': true,
      'is_public_holiday': false,
    },
  ],
  roles: [
    {'id': 'custom', 'code': 'CUSTOM', 'name': 'Custom duty'},
  ],
  slots: [
    {
      'id': 'slot',
      'roster_day_id': 'day',
      'role_id': 'custom',
      'starts_at': '2026-10-01T20:00:00Z',
      'ends_at': '2026-10-02T08:00:00Z',
      'max_doctors': 1,
    },
    for (final id in ['old1', 'old2'])
      {
        'id': id,
        'roster_day_id': 'history',
        'role_id': 'custom',
        'starts_at': '2026-09-05T08:00:00Z',
        'ends_at': '2026-09-05T10:00:00Z',
        'max_doctors': 1,
      },
  ],
  assignments: [
    {
      'id': 'a',
      'doctor_id': missingDoctor ? null : 'doctor',
      'roster_slot_id': 'slot',
      'state': 'provisional',
    },
    for (final id in ['old1', 'old2'])
      {
        'id': id,
        'doctor_id': 'doctor',
        'roster_slot_id': id,
        'state': 'confirmed',
      },
  ],
  absences: [
    {
      'doctor_id': 'doctor',
      'type': 'duty_24',
      'starts_on': '2026-09-05',
      'ends_on': '2026-09-06',
    },
    {
      'doctor_id': 'doctor',
      'type': 'duty_24',
      'starts_on': '2026-09-05',
      'ends_on': '2026-09-05',
    },
    {
      'doctor_id': 'doctor',
      'type': 'duty_24',
      'starts_on': '2026-10-01',
      'ends_on': '2026-10-01',
    },
    {
      'doctor_id': 'doctor',
      'type': 'duty_24',
      'starts_on': '2026-07-01',
      'ends_on': '2026-07-03',
    },
  ],
);

class FakeReader implements RosterReader {
  int calls = 0;
  bool fail = false;
  bool empty = false;
  final selected = <String>[];
  @override
  Future<List<RosterChoice>> listMonths() async {
    calls++;
    if (fail) throw StateError('offline');
    return empty
        ? []
        : [month, const RosterChoice('previous', 2026, 9, RosterPhase.locked)];
  }

  @override
  Future<RosterSnapshot> loadMonth(RosterChoice choice) async {
    selected.add(choice.id);
    final data = fixture();
    return RosterSnapshot(
      choice,
      data.days,
      data.doctors,
      data.inactiveDoctorIds,
      data.facts,
      data.loadedHistoryDates,
    );
  }
}

class FakeGateway implements SessionGateway {
  final events = StreamController<void>.broadcast();
  bool signedIn = false;
  AccessCheck access = const AccessCheck(
    AccessLevel.requiresMfa,
    factors: [('factor', 'Test authenticator')],
  );
  Completer<AccessCheck>? pending;
  @override
  bool get isSignedIn => signedIn;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<AccessCheck> checkAccess() async =>
      pending == null ? access : await pending!.future;
  @override
  Future<void> signIn(String email, String password) async {
    signedIn = true;
    events.add(null);
  }

  @override
  Future<void> verify(String factorId, String code) async {
    if (code != '123456') throw const AuthException('Invalid code');
    access = const AccessCheck(AccessLevel.ready);
    events.add(null);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    events.add(null);
  }
}

void main() {
  test(
    'retains inactive physician, exact custom role, UTC timestamps, overnight duty and phases',
    () {
      final data = fixture();
      expect(data.inactiveDoctorIds, {'doctor'});
      expect(data.days.single.assignments.single.doctor.fullName, 'Ada Test');
      expect(data.days.single.slots.single.role.code, 'CUSTOM');
      expect(
        data.days.single.slots.single.endsAt.difference(
          data.days.single.slots.single.startsAt,
        ),
        const Duration(hours: 12),
      );
      expect(data.days.single.slots.single.startsAt.isUtc, isTrue);
      expect(data.days.single.date, DateTime.utc(2026, 10, 1));
      expect(data.month.phase, RosterPhase.published);
      expect(data.facts.first.state, AssignmentState.provisional);
      expect(data.facts.last.phase, RosterPhase.locked);
      expect(() => fixture(missingDoctor: true), throwsFormatException);
      expect(() => fixture(phase: 'unknown'), throwsFormatException);
      expect(
        fixture(phase: 'open_for_selection').month.phase,
        RosterPhase.openForSelection,
      );
    },
  );

  test(
    '90-day date window clips and deduplicates duty markers; role days differ from assignments',
    () {
      final data = fixture();
      expect(data.historyStart, DateTime.utc(2026, 7, 3));
      final workload = workloadFor(
        data,
        data.doctors.single,
        WorkloadWindow(data.historyStart, data.historyEnd),
      );
      expect(workload.assignments, 2);
      expect(workload.assignedDays, 1);
      expect(workload.confirmed, 2);
      expect(workload.provisional, 0);
      expect(workload.roles.single.days, 1);
      expect(workload.roles.single.role.code, 'CUSTOM');
      expect(workload.recordedDuty24Days, 3);
      expect(workload.recordedWeekendDuty24Days, 2);
      final current = workloadFor(
        data,
        data.doctors.single,
        WorkloadWindow(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 1)),
      );
      expect(current.assignments, 1);
      expect(current.provisional, 1);
      expect(current.recordedDuty24Days, 1);
    },
  );

  testWidgets(
    'sign-in then MFA; invalid code does not load data; sign-out removes dashboard',
    (tester) async {
      final gateway = FakeGateway();
      final reader = FakeReader();
      addTearDown(gateway.events.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(gateway: gateway, reader: reader),
        ),
      );
      expect(find.text('Administrator sign-in'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'test@example.invalid',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'test-password',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Two-factor verification'), findsOneWidget);
      expect(reader.calls, 0);
      await tester.enterText(
        find.widgetWithText(TextField, 'Authenticator code'),
        '000000',
      );
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid code'), findsOneWidget);
      expect(reader.calls, 0);
      await tester.enterText(
        find.widgetWithText(TextField, 'Authenticator code'),
        '123456',
      );
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.byType(RosterDashboard), findsOneWidget);
      expect(reader.calls, greaterThan(0));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byType(RosterDashboard), findsNothing);
    },
  );

  testWidgets(
    'denied access never invokes roster reader; pending recheck hides previous dashboard',
    (tester) async {
      final gateway = FakeGateway()
        ..signedIn = true
        ..access = const AccessCheck(AccessLevel.denied);
      final reader = FakeReader();
      addTearDown(gateway.events.close);
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGate(gateway: gateway, reader: reader),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Administrator access required'),
        findsOneWidget,
      );
      expect(reader.calls, 0);
      gateway.access = const AccessCheck(AccessLevel.ready);
      gateway.events.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(RosterDashboard), findsOneWidget);
      gateway.pending = Completer<AccessCheck>();
      gateway.events.add(null);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RosterDashboard), findsNothing);
      gateway.pending!.complete(const AccessCheck(AccessLevel.denied));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Administrator access required'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'dashboard supports month switching, exact roles, physician details and failed refresh retry',
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
      expect(find.text('CUSTOM: Custom duty'), findsOneWidget);
      expect(find.textContaining('1.10. 22:00 - 2.10. 10:00'), findsOneWidget);
      expect(find.textContaining('Times use Europe/Vienna'), findsOneWidget);
      await tester.tap(find.text('Ada Test (inactive)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Previous 90 days:'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('month-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-09').last);
      await tester.pumpAndSettle();
      expect(reader.selected.last, 'previous');
      reader.fail = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load roster data'), findsOneWidget);
      expect(
        find.text('Ada Test (inactive)'),
        findsOneWidget,
      ); // Preserve snapshot on reload failure.
      reader.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Ada Test (inactive)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
