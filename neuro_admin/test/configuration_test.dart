import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/configuration_screen.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'workspace_test.dart' show display;

class FakeConfiguration implements ConfigurationAdministrationService {
  final changes = <ConfigurationChange>[];
  final snapshot = ConfigurationSnapshot.fromJson({
    'roles': [
      {
        'id': 'custom',
        'code': 'ARBITRARY',
        'name': 'Custom clinic',
        'updated_at': '2026-10-11',
        'is_active': true,
        'print_in_report': true,
        'max_doctors': 2,
        'display_order': 0,
        'allowed_ranks': <String>[],
        'required_capabilities': <String>[],
      },
    ],
    'templates': <Object>[],
  });
  @override
  Future<ConfigurationSnapshot> configuration() async => snapshot;
  @override
  Future<void> saveConfiguration(ConfigurationChange r) async {
    changes.add(r);
  }
}

void main() {
  testWidgets('custom role form uses exact code, capacity and report fields', (
    tester,
  ) async {
    final service = FakeConfiguration();
    await display(tester, ConfigurationScreen(service: service));
    await tester.tap(find.text('Create role'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Code'),
      'GENERIC-17',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Any department role',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.changes.single.values['code'], 'GENERIC-17');
    expect(service.changes.single.values['max_doctors'], 1);
    expect(service.changes.single.kind, 'roles');
  });
  testWidgets(
    'template editor chooses arbitrary role and explicit weekday set',
    (tester) async {
      final service = FakeConfiguration();
      await display(tester, ConfigurationScreen(service: service));
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sat'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Capacity'),
        '3',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final r = service.changes.single;
      expect(r.kind, 'templates');
      expect(r.values['role_id'], 'custom');
      expect(r.values['weekdays'], [1, 2, 3, 4, 5, 6]);
      expect(r.values['start_time'], '08:00');
      expect(r.values['capacity'], 3);
    },
  );
}
