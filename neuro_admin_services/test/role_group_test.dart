import 'package:test/test.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_reader.dart';
import 'package:neuro_core/neuro_core.dart';

void main() {
  test(
    'stored grouping survives reload without deriving semantics from role codes',
    () {
      for (var reload = 0; reload < 2; reload++) {
        final snapshot = decodeRoster(
          const RosterChoice('month', 2026, 10, RosterPhase.draft),
          doctors: [],
          days: [],
          slots: [],
          assignments: [],
          absences: [],
          rosterRows: [
            {'id': 'month', 'phase': 'draft'},
          ],
          roles: [
            {
              'id': 'custom',
              'code': 'ANY',
              'name': 'Custom',
              'ui_group': 'stationary',
            },
            {
              'id': 'sul',
              'code': 'SUL',
              'name': 'Configured elsewhere',
              'ui_group': 'ambulatory',
            },
            {'id': 'legacy', 'code': 'SU1', 'name': 'Legacy'},
            {
              'id': 'future',
              'code': 'NEW',
              'name': 'Future',
              'ui_group': 'future-category',
            },
          ],
        );
        expect(snapshot.roles.map((r) => r.group), [
          RoleGroup.stationary,
          RoleGroup.ambulatory,
          RoleGroup.ambulatory,
          RoleGroup.ambulatory,
        ]);
        expect(snapshot.roles.map((r) => r.id), [
          'custom',
          'sul',
          'legacy',
          'future',
        ]);
      }
    },
  );
}
