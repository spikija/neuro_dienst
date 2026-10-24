import 'package:neuro_core/neuro_core.dart';

import 'admin_contracts.dart';
import 'directory.dart';
import 'lifecycle.dart';
import 'scheduling_time.dart';

/// Removes one physician's selected absence/marker type on one date.
final class AbsenceDayRemovalRequest {
  final RosterVersion roster;
  final String physicianId;
  final HospitalDate date;
  final AvailabilityType type;
  final AdminWriteIntent operation;

  AbsenceDayRemovalRequest({
    required this.roster,
    required this.physicianId,
    required this.date,
    required this.type,
    required this.operation,
  }) {
    if (roster.contentVersion == null ||
        roster.contentVersion! < 1 ||
        physicianId.trim().isEmpty) {
      throw ArgumentError('A versioned roster and physician are required');
    }
  }
  String get databaseType => switch (type) {
    AvailabilityType.externalRoatation => 'external_rotation',
    AvailabilityType.duty24 => 'duty_24',
    _ => databaseEnum(type),
  };
}

abstract interface class AbsenceDayRemovalService {
  Future<void> removeDay(AbsenceDayRemovalRequest request);
}
