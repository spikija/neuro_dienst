import 'package:neuro_core/neuro_core.dart';
import 'admin_contracts.dart';
import 'directory.dart';
import 'read_models.dart';

/// Exact configured identities; never collapse custom roles into DutyRole.
final class ConfiguredRole {
  final String id, code, name, updatedAt;
  final String? colorKey;
  final RoleGroup group;
  final bool active, printInReport;
  final int capacity, displayOrder;
  final Set<DoctorRank> ranks;
  final Set<Capability> capabilities;
  ConfiguredRole(Map<String, dynamic> r)
    : group = RoleGroup.fromDatabase(r['ui_group']),
      colorKey = r['color_key'],
      id = r['id'],
      code = r['code'],
      name = r['name'],
      updatedAt = r['updated_at'],
      active = r['is_active'],
      printInReport = r['print_in_report'],
      capacity = r['max_doctors'],
      displayOrder = r['display_order'],
      ranks = Set.unmodifiable(
        (r['allowed_ranks'] as List).map(
          (v) => directoryEnum(DoctorRank.values, v),
        ),
      ),
      capabilities = Set.unmodifiable(
        (r['required_capabilities'] as List).map(
          (v) => directoryEnum(Capability.values, v),
        ),
      );
}

final class ConfiguredTemplate {
  final String id, roleId, updatedAt, start, end;
  final bool active, monthly;
  final int? day, capacity;
  final Set<int> weekdays;
  ConfiguredTemplate(Map<String, dynamic> t)
    : id = t['id'],
      roleId = t['role_id'],
      updatedAt = t['updated_at'],
      start = t['start_time'],
      end = t['end_time'],
      active = t['is_active'],
      monthly = t['weekday_rule'] == 'monthly_day',
      day = t['monthly_day'],
      capacity = t['capacity'],
      weekdays = Set.unmodifiable(
        t['weekdays'] == null
            ? switch (t['weekday_rule']) {
                'monday_only' => [1],
                'tuesday_only' => [2],
                'wednesday_only' => [3],
                'thursday_only' => [4],
                'friday_only' => [5],
                'monthly_day' => <int>[],
                _ => [1, 2, 3, 4, 5],
              }
            : (t['weekdays'] as List).cast<int>(),
      );
}

final class ConfigurationSnapshot {
  final List<ConfiguredRole> roles;
  final List<ConfiguredTemplate> templates;
  ConfigurationSnapshot.fromJson(Map<String, dynamic> data)
    : roles = List.unmodifiable(
        (data['roles'] as List).map(
          (v) => ConfiguredRole(Map<String, dynamic>.from(v)),
        ),
      ),
      templates = List.unmodifiable(
        (data['templates'] as List).map(
          (v) => ConfiguredTemplate(Map<String, dynamic>.from(v)),
        ),
      );
}

final class ConfigurationChange {
  final AdminWriteIntent operation;
  final String kind, id;
  final String? updatedAt;
  final bool delete;
  final Map<String, Object?> values;
  ConfigurationChange({
    required this.operation,
    required this.kind,
    required this.id,
    this.updatedAt,
    this.delete = false,
    required Map<String, Object?> values,
  }) : values = Map.unmodifiable(
         values.map(
           (key, value) => MapEntry(
             key,
             value is List ? List<Object?>.unmodifiable(value) : value,
           ),
         ),
       );
}

abstract interface class ConfigurationAdministrationService {
  Future<ConfigurationSnapshot> configuration();
  Future<void> saveConfiguration(ConfigurationChange request);
}
