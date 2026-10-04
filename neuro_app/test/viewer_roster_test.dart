import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/demo/demo_roster.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/admin_invite_doctor_screen.dart';
import 'package:neuro_app/screens/viewer_roster_screen.dart';
import 'package:neuro_app/services/supabase_roster_service.dart';
import 'package:neuro_core/neuro_core.dart';

Widget app(Widget home) => MaterialApp(
  builder: (_, child) =>
      AppLocalizations(language: AppLanguage.english, child: child!),
  home: home,
);

const summaries = [
  RosterSummary(
    id: 'june',
    year: 2026,
    month: 6,
    phase: RosterPhase.draft,
    updatedAt: null,
  ),
  RosterSummary(
    id: 'july',
    year: 2026,
    month: 7,
    phase: RosterPhase.draft,
    updatedAt: null,
  ),
];

void main() {
  testWidgets(
    'viewer browses assignments and months without editing controls',
    (tester) async {
      final requests = <String?>[];
      var signedOut = false;
      await tester.pumpWidget(
        app(
          ViewerRosterScreen(
            loadData: (id) async {
              requests.add(id);
              return ViewerRosterData(
                rosters: summaries,
                selectedId: id ?? 'june',
                roster: DemoRoster.createJune2026(),
              );
            },
            onSignOut: () => signedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Read-only access'), findsOneWidget);
      await tester.tap(find.text('1.6.2026'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(DemoRoster.createOtherDoctor().fullName),
        findsWidgets,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
      expect(find.byIcon(Icons.edit_calendar), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('July 2026').last);
      await tester.pumpAndSettle();
      expect(requests.last, 'july');
      await tester.tap(find.byTooltip('Sign out'));
      expect(signedOut, isTrue);
    },
  );

  testWidgets('viewer can retry a failed load and see an empty roster list', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      app(
        ViewerRosterScreen(
          loadData: (_) async {
            if (attempts++ == 0) throw Exception('offline');
            return const ViewerRosterData(
              rosters: [],
              selectedId: null,
              roster: null,
            );
          },
          onSignOut: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer invitation does not ask for physician qualifications', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const AdminInviteDoctorScreen(readOnlyViewer: true)),
    );
    expect(find.text('Invite viewer'), findsOneWidget);
    expect(find.text('Rank'), findsNothing);
    expect(find.text('Capabilities'), findsNothing);
    expect(find.text('Create viewer and send link'), findsOneWidget);
    expect(find.text('Institutional email'), findsOneWidget);
  });
}
