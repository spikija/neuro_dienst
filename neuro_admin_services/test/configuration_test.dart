import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:test/test.dart';

void main() {
  test(
    'legacy and explicit templates retain recurrence and exact role identity',
    () {
      Map<String, dynamic> row(String rule) => {
        'id': 'template',
        'role_id': 'CUSTOM',
        'updated_at': 'stamp',
        'start_time': '08:00:00',
        'end_time': '16:00:00',
        'is_active': true,
        'weekday_rule': rule,
        'monthly_day': null,
        'capacity': null,
      };
      expect(ConfiguredTemplate(row('thursday_only')).weekdays, {4});
      final explicitTemplate = ConfiguredTemplate({
        ...row('every_weekday'),
        'weekdays': [2, 6, 7],
        'capacity': 3,
      });
      expect(explicitTemplate.roleId, 'CUSTOM');
      expect(explicitTemplate.weekdays, {2, 6, 7});
      expect(explicitTemplate.capacity, 3);
      expect(
        ConfiguredTemplate({...row('monthly_day'), 'monthly_day': 15}).monthly,
        true,
      );
    },
  );
}
