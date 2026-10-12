import 'read_models.dart';

/// Stable presentation tokens, independent of departments and scheduling rules.
/// Light/dark variants keep the same hue on the respective surface colors.
final class RolePaletteColor {
  final String key, label;
  final int lightArgb, darkArgb;
  const RolePaletteColor(this.key, this.label, this.lightArgb, this.darkArgb);
}

const rolePalette = [
  RolePaletteColor('blue', 'Blue', 0xff1565c0, 0xff90caf9),
  RolePaletteColor('teal', 'Teal', 0xff00695c, 0xff80cbc4),
  RolePaletteColor('purple', 'Purple', 0xff6a1b9a, 0xffce93d8),
  RolePaletteColor('orange', 'Orange', 0xffa34800, 0xffffb74d),
  RolePaletteColor('rose', 'Rose', 0xffad1457, 0xfff48fb1),
  RolePaletteColor('indigo', 'Indigo', 0xff283593, 0xff9fa8da),
  RolePaletteColor('green', 'Green', 0xff2e7d32, 0xffa5d6a7),
  RolePaletteColor('brown', 'Brown', 0xff6d4c41, 0xffbcaaa4),
];

RolePaletteColor roleColor(String roleId, [String? configuredKey]) {
  for (final color in rolePalette) {
    if (color.key == configuredKey) return color;
  }
  // Explicit FNV-1a, never String.hashCode (not stable across runtimes).
  var hash = 0x811c9dc5;
  for (final unit in roleId.codeUnits) {
    hash =
        (((hash ^ unit) * 0x193) + (((hash ^ unit) & 0xff) << 24)) & 0xffffffff;
  }
  return rolePalette[hash % rolePalette.length];
}

int compareRoleOrder(StoredRole a, StoredRole b) {
  final order = a.displayOrder.compareTo(b.displayOrder);
  if (order != 0) return order;
  final code = a.code.compareTo(b.code);
  return code != 0 ? code : a.id.compareTo(b.id);
}

/// Include active/reportable configuration and every exact role with month facts.
/// Inactive, unreferenced roles do not crowd current planning.
List<StoredRole> calendarRoles(RosterSnapshot snapshot) {
  final scheduled = {
    for (final day in snapshot.days)
      for (final slot in day.slots) slot.role.id: slot.role,
  };
  final roles = {...scheduled};
  for (final role in snapshot.roles) {
    if (role.isActive != false || scheduled.containsKey(role.id)) {
      roles[role.id] = role;
    }
  }
  return roles.values.toList()..sort(compareRoleOrder);
}

enum RoleStaffingState { unscheduled, vacant, partial, staffed }

/// Counts provisional and confirmed assignment facts; capacity is from each slot,
/// not role defaults. Excess staffing on one shift cannot fill another shift.
final class RoleStaffing {
  final StoredRole role;
  final List<StoredDuty> slots;
  final int assigned, capacity, coveredCapacity;
  RoleStaffing._(
    this.role,
    this.slots,
    this.assigned,
    this.capacity,
    this.coveredCapacity,
  );
  factory RoleStaffing.forDay(StoredRole role, StoredDay? day) {
    final slots =
        day?.slots.where((s) => s.role.id == role.id).toList() ??
        <StoredDuty>[];
    var assigned = 0, capacity = 0, covered = 0;
    for (final slot in slots) {
      final count = day!.assignments
          .where((a) => a.duty.id == slot.id)
          .map((a) => a.id)
          .toSet()
          .length;
      assigned += count;
      capacity += slot.capacity;
      covered += count.clamp(0, slot.capacity);
    }
    return RoleStaffing._(
      role,
      List.unmodifiable(slots),
      assigned,
      capacity,
      covered,
    );
  }
  RoleStaffingState get state => slots.isEmpty
      ? RoleStaffingState.unscheduled
      : assigned == 0
      ? RoleStaffingState.vacant
      : coveredCapacity >= capacity
      ? RoleStaffingState.staffed
      : RoleStaffingState.partial;
}
