import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/physician_table.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_preview_test.dart' show PreviewReader, chooseRole;
import 'workspace_test.dart' show display;

const pikija = Doctor(
  id: 'pikija',
  firstName: 'John',
  lastName: 'Pikija',
  rank: DoctorRank.consultant,
  capabilities: {Capability.canLead},
);
const zimmer = Doctor(
  id: 'zimmer',
  firstName: 'Zoe',
  lastName: 'Zimmer',
  rank: DoctorRank.resident,
);

void main() {
  testWidgets('month changes refresh slot totals and retain the search', (
    tester,
  ) async {
    await display(
      tester,
      RosterDashboard(
        reader: PreviewReader(
          previewFixture(
            doctors: [pikija, zimmer],
            facts: [
              AssignmentFact(
                'a',
                pikija,
                duty(1),
                AssignmentState.provisional,
                RosterPhase.draft,
              ),
            ],
          ),
        ),
        onSignOut: () async {},
      ),
    );
    final table = find.byType(PhysicianTable);
    await tester.enterText(
      find.byKey(const ValueKey('physician-search')),
      'Pik',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: table, matching: find.text('1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('previous-month')));
    await tester.pumpAndSettle();
    expect(find.text('John Pikija'), findsOneWidget);
    expect(find.text('Zoe Zimmer'), findsNothing);
    expect(
      find.descendant(of: table, matching: find.text('0')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial name search, all sort columns and selected details', (
    tester,
  ) async {
    final snapshot = previewFixture(
      doctors: [zimmer, pikija],
      facts: [
        for (var i = 1; i <= 12; i++)
          AssignmentFact(
            'p-$i',
            pikija,
            duty(i),
            AssignmentState.confirmed,
            RosterPhase.draft,
          ),
        for (var i = 1; i <= 2; i++)
          AssignmentFact(
            'z-$i',
            zimmer,
            duty(i),
            AssignmentState.provisional,
            RosterPhase.draft,
          ),
        AssignmentFact(
          'old',
          zimmer,
          StoredDuty(
            'old',
            DateTime.utc(2026, 9, 1),
            leader,
            DateTime.utc(2026, 9, 1, 8),
            DateTime.utc(2026, 9, 1, 12),
            1,
          ),
          AssignmentState.confirmed,
          RosterPhase.published,
        ),
      ],
    );
    String? selected;
    await display(
      tester,
      SizedBox(
        width: 400,
        child: StatefulBuilder(
          builder: (context, setState) => PhysicianTable(
            snapshot: snapshot,
            doctors: snapshot.doctors,
            selectedId: selected,
            onSelected: (id) => setState(() => selected = id),
            detailsBuilder: (_) => const Text('Expanded workload'),
          ),
        ),
      ),
    );
    final p = find.byKey(const ValueKey('candidate-pikija'));
    final z = find.byKey(const ValueKey('candidate-zimmer'));
    void expectFirst(Finder first, Finder second) => expect(
      tester.getTopLeft(first).dy,
      lessThan(tester.getTopLeft(second).dy),
    );
    expectFirst(p, z);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Consultant · Leadership'), findsOneWidget);
    expect(find.text('Expanded workload'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('physician-search')), '');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.byKey(const ValueKey('physician-sort-0')));
    await tester.pumpAndSettle();
    expectFirst(z, p);
    await tester.tap(find.byKey(const ValueKey('physician-sort-1')));
    await tester.pumpAndSettle();
    expectFirst(p, z);
    await tester.tap(find.byKey(const ValueKey('physician-sort-1')));
    await tester.pumpAndSettle();
    expectFirst(z, p);
    await tester.tap(find.byKey(const ValueKey('physician-sort-2')));
    await tester.pumpAndSettle();
    expectFirst(z, p);
    await tester.tap(find.byKey(const ValueKey('physician-sort-2')));
    await tester.pumpAndSettle();
    expectFirst(p, z);
    await tester.enterText(
      find.byKey(const ValueKey('physician-search')),
      ' pIK ',
    );
    await tester.pumpAndSettle();
    expect(p, findsOneWidget);
    expect(z, findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(selected, 'pikija');
    expect(find.text('Expanded workload'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('physician-search')),
      'absent',
    );
    await tester.pumpAndSettle();
    expect(find.text('No physicians match this filter.'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(selected, 'pikija');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(p, findsOneWidget);
    expect(z, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard dividers resize adjacent panes and keep physician search in preview',
    (tester) async {
      await display(
        tester,
        RosterDashboard(
          reader: PreviewReader(previewFixture(doctors: [pikija, zimmer])),
          onSignOut: () async {},
        ),
      );
      final first = find.byKey(const ValueKey('calendar-physicians-divider'));
      final second = find.byKey(const ValueKey('physicians-roster-divider'));
      final daily = find.byKey(const ValueKey('daily-roster-pane'));
      final physicians = find.byType(PhysicianTable);
      final original = tester.getSize(daily).width;
      final originalPhysicians = tester.getSize(physicians).width;
      await tester.drag(first, const Offset(40, 0));
      await tester.pumpAndSettle();
      final afterFirst = tester.getSize(daily).width;
      expect(afterFirst, closeTo(original, 1));
      expect(tester.getSize(physicians).width, lessThan(originalPhysicians));
      await tester.drag(second, const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(daily).width, greaterThan(afterFirst));
      await chooseRole(tester, leader);
      expect(find.byType(PhysicianTable), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('physician-search')),
        'Pik',
      );
      await tester.pumpAndSettle();
      expect(find.text('John Pikija'), findsOneWidget);
      expect(find.text('Zoe Zimmer'), findsNothing);
      // Minimum pane widths remain safe even after a very large drag.
      await tester.drag(second, const Offset(1200, 0));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1280, 720);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
