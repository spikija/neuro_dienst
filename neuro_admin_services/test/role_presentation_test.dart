import 'package:test/test.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'support/preview_fixture.dart';

void main() {
  const custom = StoredRole(
    'custom-id',
    'CUSTOM',
    'Custom',
    displayOrder: -10,
    colorKey: 'teal',
    isActive: true,
  );
  test(
    'fulfillment uses exact slot ID, actual capacity, provisional and confirmed facts',
    () {
      final slot = duty(1, role: custom, capacity: 2);
      for (final count in [0, 1, 2, 3]) {
        final facts = [
          for (var i = 0; i < count; i++)
            AssignmentFact(
              'a$i',
              ana(),
              slot,
              i == 0 ? AssignmentState.provisional : AssignmentState.confirmed,
              RosterPhase.draft,
            ),
        ];
        final snap = previewFixture(slots: [slot], facts: facts);
        final result = RoleStaffing.forDay(custom, snap.days.first);
        expect(result.assigned, count);
        expect(result.capacity, 2);
        expect(
          result.state,
          count == 0
              ? RoleStaffingState.vacant
              : count == 1
              ? RoleStaffingState.partial
              : RoleStaffingState.staffed,
        );
        expect(
          RoleStaffing.forDay(icb, snap.days.first).state,
          RoleStaffingState.unscheduled,
        );
      }
    },
  );
  test(
    'one overstaffed slot cannot hide another vacant slot for the same role',
    () {
      final first = duty(1, role: custom, id: 'first');
      final second = duty(1, role: custom, id: 'second');
      final snap = previewFixture(
        slots: [first, second],
        facts: [
          for (var i = 0; i < 2; i++)
            AssignmentFact(
              'a$i',
              ana(),
              first,
              AssignmentState.confirmed,
              RosterPhase.draft,
            ),
        ],
      );
      expect(
        RoleStaffing.forDay(custom, snap.days.first).state,
        RoleStaffingState.partial,
      );
    },
  );
  test(
    'stable configured ordering retains inactive historical facts, excludes unused inactive roles',
    () {
      const retired = StoredRole(
        'retired',
        'OLD',
        'Historical',
        isActive: false,
        displayOrder: 99,
      );
      const hidden = StoredRole('hidden', 'HIDE', 'Unused', isActive: false);
      final snap = previewFixture(
        roles: [hidden, icb, custom, leader, retired],
        slots: [duty(1, role: retired)],
      );
      expect(calendarRoles(snap).map((r) => r.id), [
        'custom-id',
        'icb',
        'sul',
        'retired',
      ]);
      for (final day in snap.days) {
        expect(
          calendarRoles(snap).map((r) => RoleStaffing.forDay(r, day).role.id),
          ['custom-id', 'icb', 'sul', 'retired'],
        );
      }
    },
  );
  test(
    'palette deterministic across reconstructed roles and configured overrides',
    () {
      expect(
        roleColor('custom-id').key,
        roleColor(String.fromCharCodes('custom-id'.codeUnits)).key,
      );
      expect(roleColor('custom-id', 'teal').key, 'teal');
      expect(roleColor('new-id', 'teal').key, 'teal');
      expect(roleColor('custom-id', 'invalid').key, roleColor('custom-id').key);
    },
  );
}
