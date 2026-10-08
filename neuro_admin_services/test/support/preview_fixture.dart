import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

const leader = StoredRole(
  'sul',
  'SUL',
  'Stroke Unit Leadership',
  allowedRanks: {DoctorRank.consultant},
  requiredCapabilities: {Capability.canLead},
  isActive: true,
);
const ambulance = StoredRole(
  'amb',
  'AMB',
  'Ambulance',
  allowedRanks: {DoctorRank.consultant, DoctorRank.resident},
  requiredCapabilities: {},
  isActive: true,
);
const icb = StoredRole(
  'icb',
  'ICB',
  'Other clinic',
  allowedRanks: {DoctorRank.consultant, DoctorRank.resident},
  requiredCapabilities: {},
  isActive: true,
);

Doctor ana({List<AvailabilityPeriod> absences = const []}) => Doctor(
  id: 'ana',
  firstName: 'Ana',
  lastName: 'Example',
  rank: DoctorRank.consultant,
  capabilities: {Capability.canLead},
  availabilities: absences,
);
Doctor ben() => Doctor(
  id: 'ben',
  firstName: 'Ben',
  lastName: 'Example',
  rank: DoctorRank.resident,
);

StoredDuty duty(
  int day, {
  StoredRole role = leader,
  String? id,
  int capacity = 1,
  int start = 8,
  int end = 12,
}) => StoredDuty(
  id ?? '${role.id}-$day',
  DateTime.utc(2026, 10, day),
  role,
  DateTime.utc(2026, 10, day, start),
  DateTime.utc(2026, 10, day, end),
  capacity,
);

RosterSnapshot previewFixture({
  RosterPhase phase = RosterPhase.draft,
  List<Doctor>? doctors,
  List<StoredDuty>? slots,
  List<StoredRole>? roles,
  List<AssignmentFact> facts = const [],
  Set<String> inactive = const {},
  bool coverage = true,
  bool history = true,
  int? contentVersion,
}) {
  final duties =
      slots ??
      [
        for (var i = 1; i <= 3; i++) duty(i),
        duty(2, role: ambulance),
        duty(3, role: icb),
      ];
  return RosterSnapshot(
    RosterChoice('october', 2026, 10, phase),
    [
      for (var i = 1; i <= 31; i++)
        StoredDay(
          CalendarDayInfo(
            date: DateTime.utc(2026, 10, i),
            isWeekend: DateTime.utc(2026, 10, i).weekday >= 6,
            isPublicHoliday: false,
          ),
          duties.where((s) => s.date == DateTime.utc(2026, 10, i)).toList(),
          facts.where((a) => a.duty.date == DateTime.utc(2026, 10, i)).toList(),
        ),
    ],
    doctors ?? [ana(), ben()],
    inactive,
    facts,
    {
      if (history)
        for (var i = 1; i <= 90; i++)
          DateTime.utc(2026, 10, 1).subtract(Duration(days: i)),
    },
    roles: roles ?? [leader, ambulance, icb],
    hasOverlapCoverage: coverage,
    contentVersion: contentVersion,
  );
}

Future<AssignmentPreview> validate(
  RosterSnapshot snapshot, {
  List<int> dates = const [1],
  String physician = 'ana',
  String role = 'sul',
  String? slotId,
  String? reason,
}) => SnapshotAssignmentValidationService(snapshot).preview(
  AssignmentValidationRequest(
    roster: RosterVersion.unversioned(snapshot.month.id),
    roleId: role,
    physicianId: physician,
    targets: [
      for (final date in dates)
        AssignmentTarget(HospitalDate(2026, 10, date), slotId: slotId),
    ],
    correctionReason: reason,
  ),
);
