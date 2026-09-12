import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/screens/vacation_import_screen.dart';
import 'package:neuro_app/services/device_calendar_import_service.dart';

class FakeImportService extends DeviceCalendarImportService {
  @override
  Future<CalendarVacationScan> loadVacationScan({
    required DateTime start,
    required DateTime end,
  }) async => CalendarVacationScan(
    sources: const [
      CalendarImportSource(id: 'a', name: 'Work', accountName: 'a@example.com'),
      CalendarImportSource(id: 'b', name: 'Work', accountName: 'b@example.com'),
      CalendarImportSource(id: 'empty', name: 'Empty calendar'),
    ],
    candidates: [
      for (final entry in [('a', 4), ('b', 8)])
        CalendarVacationCandidate(
          calendarId: entry.$1,
          calendarName: 'Work',
          accountName: '${entry.$1}@example.com',
          title: 'Vacation ${entry.$1}',
          start: DateTime(2026, 6, entry.$2),
          end: DateTime(2026, 6, entry.$2),
          allDay: true,
        ),
    ],
  );
}

void main() {
  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'source filtering imports only visible selections, identified by account',
    (tester) async {
      List<DateTime>? imported;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppLocalizations(language: AppLanguage.english, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                imported = await Navigator.push<List<DateTime>>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VacationImportScreen(
                      year: 2026,
                      month: 6,
                      importService: FakeImportService(),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Source calendar: Work · a@example.com'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Source calendar: Work · b@example.com'),
        findsOneWidget,
      );
      await choose(tester, 'Work · b@example.com');
      expect(find.text('Vacation a'), findsNothing);
      expect(find.text('Vacation b'), findsOneWidget);

      await choose(tester, 'Empty calendar');
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      await choose(tester, 'Work · a@example.com');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(imported, [DateTime(2026, 6, 4)]);
    },
  );
}
