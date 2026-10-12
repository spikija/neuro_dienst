import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'localization.dart';

String roleGroupLabel(RoleGroup group) => switch (group) {
  RoleGroup.stationary => 'Stationary',
  RoleGroup.ambulatory => 'Ambulatory / Other',
};

Color roleDisplayColor(BuildContext context, String roleId, [String? key]) {
  final palette = roleColor(roleId, key);
  return Color(
    Theme.of(context).brightness == Brightness.dark
        ? palette.darkArgb
        : palette.lightArgb,
  );
}

String roleStaffingLabel(BuildContext context, RoleStaffing staffing) {
  final strings = AdminStrings.of(context);
  return staffing.state == RoleStaffingState.unscheduled
      ? strings.text('{role} - not scheduled', {'role': staffing.role.name})
      : strings.text('{role} - {assigned}/{capacity} staffed', {
          'role': staffing.role.name,
          'assigned': staffing.assigned,
          'capacity': staffing.capacity,
        });
}

class RoleStatusIndicator extends StatelessWidget {
  final RoleStaffing staffing;
  final double size;
  const RoleStatusIndicator({
    super.key,
    required this.staffing,
    this.size = 12,
  });
  @override
  Widget build(BuildContext context) {
    final label = roleStaffingLabel(context, staffing);
    final color = staffing.state == RoleStaffingState.unscheduled
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xffbdbdbd)
              : const Color(0xff616161))
        : roleDisplayColor(context, staffing.role.id, staffing.role.colorKey);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: RoleStatusPainter(staffing.state, color)),
        ),
      ),
    );
  }
}

class RoleStatusPainter extends CustomPainter {
  final RoleStaffingState state;
  final Color color;
  const RoleStatusPainter(this.state, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.5);
    final fill = Paint()..color = color;
    if (state == RoleStaffingState.staffed) canvas.drawOval(rect, fill);
    if (state == RoleStaffingState.partial) {
      canvas.drawArc(rect, -math.pi / 2, math.pi, true, fill);
    }
    canvas.drawOval(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7,
    );
  }

  @override
  bool shouldRepaint(RoleStatusPainter old) =>
      old.state != state || old.color != color;
}

/// Same ordered prefix in every cell. Overflow is explicit and describes ALL
/// remaining roles; no role silently disappears at small window sizes.
class CalendarRoleIndicators extends StatelessWidget {
  final List<StoredRole> roles;
  final StoredDay? day;
  const CalendarRoleIndicators({
    super.key,
    required this.roles,
    required this.day,
  });
  @override
  Widget build(BuildContext context) {
    final groups = {
      for (final group in RoleGroup.values)
        group: roles.where((r) => r.group == group).toList()
          ..sort(compareRoleOrder),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in RoleGroup.values)
          if (groups[group]!.isNotEmpty) ...[
            if (group == RoleGroup.ambulatory &&
                groups[RoleGroup.stationary]!.isNotEmpty)
              const SizedBox(width: 4),
            SizedBox(
              key: ValueKey('calendar-role-group-${group.name}'),
              width: group == RoleGroup.stationary ? 12 : 26,
              child: Semantics(
                label: AdminStrings.of(context).text(roleGroupLabel(group)),
                child: _RoleIndicatorGrid(
                  roles: groups[group]!,
                  day: day,
                  columns: group == RoleGroup.stationary ? 1 : 2,
                ),
              ),
            ),
          ],
      ],
    );
  }
}

class _RoleIndicatorGrid extends StatelessWidget {
  final List<StoredRole> roles;
  final StoredDay? day;
  final int columns;
  const _RoleIndicatorGrid({
    required this.roles,
    required this.day,
    required this.columns,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rows = constraints.hasBoundedHeight
          ? math.max(1, ((constraints.maxHeight + 2) / 14).floor())
          : (roles.length / columns).ceil();
      final count = columns * rows;
      final visible = roles.length <= count
          ? roles.length
          : math.max(0, count - 1);
      final remaining = roles
          .skip(visible)
          .map((role) => RoleStaffing.forDay(role, day))
          .toList();
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: columns * 14 - 2,
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final role in roles.take(visible))
                RoleStatusIndicator(
                  key: ValueKey('role-status-${role.id}'),
                  staffing: RoleStaffing.forDay(role, day),
                ),
              if (remaining.isNotEmpty)
                Tooltip(
                  message: remaining
                      .map((s) => roleStaffingLabel(context, s))
                      .join('\n'),
                  child: Semantics(
                    label: AdminStrings.of(
                      context,
                    ).text('{count} more roles', {'count': remaining.length}),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: FittedBox(
                        child: Text(
                          '+${remaining.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
