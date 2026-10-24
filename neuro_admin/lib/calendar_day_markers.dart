import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import 'localization.dart';
import 'absence_icons.dart';

class CalendarDayMarker {
  final AvailabilityType type;
  final String label;
  final List<Doctor> physicians;
  const CalendarDayMarker(this.type, this.label, this.physicians);

  String description(AdminStrings strings) =>
      '${strings.text(label)}: ${physicians.map((d) => d.fullName).join(', ')}';
}

/// One marker per recorded type, counting each physician only once even when
/// overlapping periods cover the date. A physician selection scopes the view.
List<CalendarDayMarker> calendarDayMarkers(
  List<Doctor> doctors,
  DateTime date, {
  String? physicianId,
}) {
  final groups = <AvailabilityType, Map<String, Doctor>>{};
  final labels = <AvailabilityType, String>{};
  for (final doctor in doctors) {
    if (physicianId != null && physicianId != doctor.id) continue;
    for (final period in doctor.availabilities.where((p) => p.includes(date))) {
      (groups[period.type] ??= {})[doctor.id] = doctor;
      labels[period.type] = period.label;
    }
  }
  // Keep the established EF marker visible before the other recorded types.
  return [
    for (final type in [
      AvailabilityType.efDay,
      ...AvailabilityType.values.where((t) => t != AvailabilityType.efDay),
    ])
      if (groups.containsKey(type))
        CalendarDayMarker(type, labels[type]!, groups[type]!.values.toList()),
  ];
}

class CalendarDayMarkerIndicators extends StatelessWidget {
  final HospitalDate date;
  final List<CalendarDayMarker> markers;
  const CalendarDayMarkerIndicators({
    super.key,
    required this.date,
    required this.markers,
  });

  @override
  Widget build(BuildContext context) {
    if (markers.isEmpty) return const SizedBox.shrink();
    final strings = AdminStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final capacity = (constraints.maxWidth / 18).floor().clamp(1, 6);
          final visible = markers.length <= capacity
              ? markers.length
              : capacity - 1;
          final remaining = markers.skip(visible).toList();
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final marker in markers.take(visible))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Tooltip(
                      message: marker.description(strings),
                      child: Semantics(
                        label: marker.description(strings),
                        child: marker.type == AvailabilityType.efDay
                            ? Text(
                                'EF',
                                key: ValueKey('calendar-ef-$date'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.primary,
                                ),
                              )
                            : Icon(
                                absenceIcon(marker.type),
                                key: ValueKey(
                                  'calendar-absence-${marker.type.name}-$date',
                                ),
                                size: 14,
                                color: marker.type == AvailabilityType.sickLeave
                                    ? scheme.error
                                    : marker.type == AvailabilityType.vacation
                                    ? scheme.tertiary
                                    : scheme.primary,
                              ),
                      ),
                    ),
                  ),
                if (remaining.isNotEmpty)
                  Tooltip(
                    message: remaining
                        .map((m) => m.description(strings))
                        .join('\n'),
                    child: Text(
                      '+${remaining.length}',
                      key: ValueKey('calendar-absence-overflow-$date'),
                      semanticsLabel: strings.text('{count} more day markers', {
                        'count': remaining.length,
                      }),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
