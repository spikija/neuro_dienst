import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/translations.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin/workspace_dialogs.dart';
import 'package:neuro_admin/main.dart';
import 'package:neuro_admin/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../neuro_admin_services/test/support/preview_fixture.dart';
import 'assignment_preview_test.dart' show PreviewReader;
import 'workspace_test.dart' show TestWorkspace;

void main() {
  testWidgets('language menu changes and persists desktop preference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const NeuroAdminApp(
        config: SupabaseConfig(url: '', publishableKey: ''),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(find.text('Dienstplankalender'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('admin_language'),
      'de',
    );
    await tester.tap(find.byTooltip('Sprache'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Roster calendar'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getString('admin_language'),
      'en',
    );
  });
  test('all named translation placeholders are retained', () {
    Set<String> parameters(String s) =>
        RegExp(r'\{\w+\}').allMatches(s).map((m) => m[0]!).toSet();
    for (final e in german.entries) {
      expect(parameters(e.value), parameters(e.key), reason: e.key);
    }
  });
  for (final locale in ['en', 'de']) {
    testWidgets('workspace and generation dialog in $locale', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('de'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: RosterDashboard(
            reader: PreviewReader(previewFixture()),
            generation: TestWorkspace(),
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final s = AdminStrings(locale);
      expect(find.text(s.text('Daily roster')), findsOneWidget);
      await tester.tap(find.byTooltip(s.text('Roster actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.text('Create month roster')));
      await tester.pumpAndSettle();
      expect(find.byType(GenerationDialog), findsOneWidget);
      expect(find.text(s.text('Create roster')), findsOneWidget);
      await tester.tap(find.text(s.text('Preview')));
      await tester.pumpAndSettle();
      if (locale == 'de') {
        expect(find.textContaining('Kalendertage'), findsOneWidget);
        expect(find.textContaining('calendar days'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
