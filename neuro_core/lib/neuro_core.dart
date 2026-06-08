enum DoctorRank {
  resident,
  specialist,
  seniorSpecialist,
  consultant,
  head,
}

enum Capability {
  canLead,
  canWorkOutpatientClinic,
  canDoNeurosonography,
  canDoNightDuty,
  canSupervise,
}
enum PhysicianCategory {
  junior,
  senior,
}
enum DutyRole {
  leader,
  subordinate,
  outpatientClinic,
  neurosonography,
  nightDuty,
  backup,
}

enum SlotStatus {
  open,
  filled,
}

enum RosterPhase {
  draft,
  openForSelection,
  locked,
  published,
}

enum AssignmentState {
  provisional,
  confirmed,
}

enum SlotRequirements {
  mandatory,
  optional,
}

enum WeekdayRule {
  everyWeekday,
  mondayOnly,
  tuesdayOnly,
  wednesdayOnly,
  thursdayOnly,
  fridayOnly,
}

enum SlotKind {
  science,
  strokeUnitLeader,
  strokeUnitTeam1,
  strokeUnitTeam2,
  ambulance,
  neurosonology,
  neurovascularBoard,
  ofoBoard,
}

enum AvailabilityType {
  available,
  vacation,
  sickLeave,
  conference,
  externalRoatation,
}

extension DailySlotStatusExtension on DailySlot {
  SlotStatus getStatus(
    List<Assignment> assignments,
  ) {
    final count = assignments
        .where((a) => a.slot.id == id)
        .length;

    return count >= template.maxDoctors
        ? SlotStatus.filled
        : SlotStatus.open;
  }
}

extension WeekdayRuleExtension on WeekdayRule {
  bool appliesTo(DateTime date) {
    switch (this) {
      case WeekdayRule.everyWeekday:
        return date.weekday >= DateTime.monday &&
            date.weekday <= DateTime.friday;
      case WeekdayRule.mondayOnly:
        return date.weekday == DateTime.monday;
      case WeekdayRule.tuesdayOnly:
        return date.weekday == DateTime.tuesday;
      case WeekdayRule.wednesdayOnly:
        return date.weekday == DateTime.wednesday;
      case WeekdayRule.thursdayOnly:
        return date.weekday == DateTime.thursday;
      case WeekdayRule.fridayOnly:
        return date.weekday == DateTime.friday;
    }
  }
}

enum SubmissionStatus {
  draft,
  submitted,
  locked,
}


// ***************************************************
// ABSTRACTIONS
// ***************************************************
abstract class HolidayProvider {
  CalendarDayInfo getDayInfo(DateTime date);
}

abstract class DoctorRepository {
  List<Doctor> getAllDoctors();

  Doctor? getDoctorById(String doctorId);
}
// ***************************************************
// CLASES
// ***************************************************
class InMemoryDoctorRepository implements DoctorRepository {
  final List<Doctor> doctors;

  InMemoryDoctorRepository({
    required this.doctors,
  });

  @override
  List<Doctor> getAllDoctors() {
    return List.unmodifiable(doctors);
  }

  @override
  Doctor? getDoctorById(String doctorId) {
    for (final doctor in doctors) {
      if (doctor.id == doctorId) {
        return doctor;
      }
    }

    return null;
  }
}

class AvailabilitySubmission {
  final String id;

  final Doctor doctor;

  final int year;
  final int month;

  final DateTime createdAt;
  final DateTime updatedAt;

  final SubmissionStatus status;

  final List<DoctorSlotAvailability> availabilities;

  AvailabilitySubmission({
    required this.id,
    required this.doctor,
    required this.year,
    required this.month,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    this.availabilities = const [],
  });
}

class AvailabilityPeriod {
  final DateTime start;
  final DateTime end;
  final AvailabilityType type;

  AvailabilityPeriod({
    required this.start,
    required this.end,
    required this.type,
  });
}

class LocalTime {
  final int hour;
  final int minute;

  LocalTime(this.hour, this.minute) {
    if (hour < 0 || hour > 23) {
      throw ArgumentError('Hour must be between 0 and 23.');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError('Minute must be between 0 and 59.');
    }
  }

  int get minutesSinceMidnight => hour * 60 + minute;
}

class TimeRange {
  final LocalTime start;
  final LocalTime end;

  TimeRange({
    required this.start,
    required this.end,
  }) {
    if (end.minutesSinceMidnight <= start.minutesSinceMidnight) {
      throw ArgumentError('End time must be after start time.');
    }
  }

  int get durationMinutes =>
      end.minutesSinceMidnight - start.minutesSinceMidnight;

  bool overlaps(TimeRange other) {
    return start.minutesSinceMidnight < other.end.minutesSinceMidnight &&
        other.start.minutesSinceMidnight < end.minutesSinceMidnight;
  }
}

class Doctor {
  final String id;
  final String firstName;
  final String lastName;
  final DoctorRank rank;
  final Set<Capability> capabilities;
  final List<AvailabilityPeriod> availabilities;
  PhysicianCategory get category {
    switch (rank) {
      case DoctorRank.resident:
        return PhysicianCategory.junior;

      case DoctorRank.specialist:
      case DoctorRank.seniorSpecialist:
      case DoctorRank.consultant:
      case DoctorRank.head:
        return PhysicianCategory.senior;
    }
  }

  const Doctor({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.rank,
    this.capabilities = const {},
    this.availabilities = const [],
  });

  String get fullName => '$firstName $lastName';
}

class SlotTemplate {
  
  final String id;
  final String name;
  final String area;
  final SlotKind kind;
  final TimeRange timeRange;
  final DutyRole role;
  final Set<DoctorRank> allowedRanks;
  final Set<Capability> requiredCapabilities;
  final int maxDoctors;
  final WeekdayRule weekdayRule;

  SlotTemplate({
      required this.id,
      required this.name,
      required this.area,
      required this.kind,
      required this.timeRange,
      required this.role,
      required this.allowedRanks,
      this.requiredCapabilities = const {},
      this.maxDoctors = 1,
      this.weekdayRule = WeekdayRule.everyWeekday,
  });


    bool canBeFilledBy(Doctor doctor) {
    final rankOk = allowedRanks.contains(doctor.rank);

    final capabilitiesOk = requiredCapabilities.every(
      doctor.capabilities.contains,
    );

    return rankOk && capabilitiesOk;
  }
}

class AllowedOverlapRule {
  final SlotKind first;
  final SlotKind second;

  AllowedOverlapRule(this.first, this.second);

  bool allows(SlotKind a, SlotKind b) {
    return (a==first && b==second) || (a == second && b== first);
  }
}

class DefaultOverlapRules {
  static final rules = [
    AllowedOverlapRule(
      SlotKind.neurosonology,
      SlotKind.neurovascularBoard,
    ),
    AllowedOverlapRule(
      SlotKind.neurosonology,
      SlotKind.ofoBoard,
    ),
    AllowedOverlapRule(
      SlotKind.strokeUnitLeader,
      SlotKind.ofoBoard,
    ),
    AllowedOverlapRule(
      SlotKind.strokeUnitLeader,
      SlotKind.neurovascularBoard,
    ),
 
  ];

  static bool isAllowed(SlotKind a, SlotKind b) {
    return rules.any((rule) => rule.allows(a, b));
  }
}

class DailySlot {
  final String id;
  final DateTime date;
  final SlotTemplate template;
  
  const DailySlot({
    required this.id,
    required this.date,
    required this.template,
  });
}


class RosterDay {
  final CalendarDayInfo calendarInfo;
  final List<DailySlot> slots;
  final List<DoctorSlotAvailability> availabilities;
  final List<Assignment> assignments;

  RosterDay({
    required this.calendarInfo,
    this.slots = const [],
    this.availabilities = const [],
    this.assignments = const [],
  });

  DateTime get date => calendarInfo.date;
}

class RosterMonth {
  final int year;
  final int month;
  final List<RosterDay> days;
  final RosterPhase phase;

  RosterMonth({
    required this.year,
    required this.month,
    required this.days,
    required this.phase,
  });
}

class RosterMonthFactory {
  final HolidayProvider holidayProvider;
  final SlotFactory slotFactory;

  RosterMonthFactory({
    required this.holidayProvider,
    required this.slotFactory,
  });

  RosterMonth generateMonth({
    required int year,
    required int month,
    required DepartmentTemplate departmentTemplate,
  }) {
    final days = <RosterDay>[];

    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);

    for (
      DateTime date = firstDay;
      !date.isAfter(lastDay);
      date = date.add(const Duration(days: 1))
    ) {
      final calendarInfo = holidayProvider.getDayInfo(date);

      final slots = slotFactory.generateSlots(
        date: date,
        departmentTemplate: departmentTemplate,
      );

      days.add(
        RosterDay(
          calendarInfo: calendarInfo,
          slots: slots,
          availabilities: [],
          assignments: [],
        ),
      );
    }

    return RosterMonth(
      year: year,
      month: month,
      phase: RosterPhase.draft,
      days: days,
    );
  }
}

class RosterPhaseService {
  bool canDoctorModifyRoster(
    RosterMonth roster,
  ) {
    return roster.phase ==
        RosterPhase.openForSelection;
  }
}

class Conflict {
  final String message;

  Conflict(this.message);

  @override
  String toString() => message;
}

class RosterValidator {
  List<Conflict> validateDay(RosterDay day) {
    final conflicts = <Conflict>[];

    conflicts.addAll(_validateDoctorEligibility(day));
    conflicts.addAll(_validateOverlappingAssignments(day));
    conflicts.addAll(_validateSlotCapacity(day));
    conflicts.addAll(_validateRequiredSlotsFilled(day));
    return conflicts;
  }

  List<Conflict> _validateDoctorEligibility(RosterDay day) {
    final conflicts = <Conflict>[];

    for (final assignment in day.assignments) {
      if (!assignment.isValidForSlot) {
        conflicts.add(
          Conflict(
            '${assignment.doctor.fullName} is not eligible for '
            '${assignment.slot.template.name}',
          ),
        );
      }
    }

    return conflicts;
  }

  List<Conflict> _validateOverlappingAssignments(RosterDay day) {
    final conflicts = <Conflict>[];

    for (var i = 0; i < day.assignments.length; i++) {
      for (var j = i + 1; j < day.assignments.length; j++) {
        final assignmentA = day.assignments[i];
        final assignmentB = day.assignments[j];

        final sameDoctor = assignmentA.doctor.id == assignmentB.doctor.id;

        final overlaps = assignmentA.slot.template.timeRange.overlaps(
          assignmentB.slot.template.timeRange,
        );

        final allowedOverlap = DefaultOverlapRules.isAllowed(
          assignmentA.slot.template.kind,
          assignmentB.slot.template.kind,
        );

        if (sameDoctor && overlaps && !allowedOverlap) {
          conflicts.add(
            Conflict(
              '${assignmentA.doctor.fullName} assigned to overlapping slots: '
              '${assignmentA.slot.template.name} and '
              '${assignmentB.slot.template.name}',
            ),
          );
        }
      }
    }

    return conflicts;
  }
  List<Conflict> _validateSlotCapacity(RosterDay day) {
    final conflicts = <Conflict>[];

    for (final slot in day.slots) {
      final assignmentsForSlot = day.assignments
          .where((assignment) => assignment.slot.id == slot.id)
          .toList();

      if (assignmentsForSlot.length > slot.template.maxDoctors) {
        conflicts.add(
          Conflict(
            '${slot.template.name} has too many assigned doctors: '
            '${assignmentsForSlot.length}/${slot.template.maxDoctors}',
          ),
        );
      }
    }

    return conflicts;
  }

  List<Conflict> _validateRequiredSlotsFilled(RosterDay day) {
    final conflicts = <Conflict>[];

    for (final slot in day.slots) {
      final assignmentsForSlot = day.assignments
          .where((assignment) => assignment.slot.id == slot.id)
          .toList();

      if (assignmentsForSlot.isEmpty && slot.template.kind != SlotKind.science) {
        conflicts.add(
          Conflict(
            '${slot.template.name} has no assigned doctor',
          ),
        );
      }
    }

    return conflicts;
  }

}

class DepartmentTemplate {
  final String id;
  final String name;
  final List<SlotTemplate> slotTemplates;

  DepartmentTemplate({
    required this.id,
    required this.name,
    required this.slotTemplates,
  });
}

class SlotFactory {
  List<DailySlot> generateSlots({
    required DateTime date,
    required DepartmentTemplate departmentTemplate,
  }) {
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;

    if (isWeekend) {
      return [];
    }

    final slots = <DailySlot>[];

    for (final template in departmentTemplate.slotTemplates) {
      if (!template.weekdayRule.appliesTo(date)) {
        continue;
      }

      slots.add(
        DailySlot(
          id: '${template.id}_${date.year}_${date.month}_${date.day}',
          date: date,
          template: template,
        ),
      );
    }

    return slots;
  }
}

class NeurologyDepartmentFactory {
  static DepartmentTemplate create() {
    return DepartmentTemplate(
      id: 'neurology',
      name: 'Neurology Department',
      slotTemplates: [
        SlotTemplate(
          id: 'science',
          name: 'Science Slot',
          area: 'Science',
          kind: SlotKind.science,
          timeRange: TimeRange(
            start: LocalTime(8, 0),
            end: LocalTime(16, 0),
          ),
          role: DutyRole.backup,
          allowedRanks: {
            DoctorRank.resident,
            DoctorRank.specialist,
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
          maxDoctors: 99,
        ),
        SlotTemplate(
          id: 'stroke_unit_leader',
          name: 'Stroke Unit Leader',
          area: 'Stroke Unit',
          kind: SlotKind.strokeUnitLeader,
          timeRange: TimeRange(
            start: LocalTime(7, 30),
            end: LocalTime(15, 30),
          ),
          role: DutyRole.leader,
          allowedRanks: {
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
          requiredCapabilities: {Capability.canLead},
        ),
        SlotTemplate(
          id: 'stroke_unit_team_1',
          name: 'Stroke Unit Team 1',
          area: 'Stroke Unit',
          kind: SlotKind.strokeUnitTeam1,
          timeRange: TimeRange(
            start: LocalTime(7, 30),
            end: LocalTime(15, 30),
          ),
          role: DutyRole.subordinate,
          allowedRanks: {
            DoctorRank.resident,
            DoctorRank.specialist,
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
        ),
        SlotTemplate(
          id: 'stroke_unit_team_2',
          name: 'Stroke Unit Team 2',
          area: 'Stroke Unit',
          kind: SlotKind.strokeUnitTeam2,
          timeRange: TimeRange(
            start: LocalTime(7, 30),
            end: LocalTime(15, 30),
          ),
          role: DutyRole.subordinate,
          allowedRanks: {
            DoctorRank.resident,
            DoctorRank.specialist,
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
        ),
        SlotTemplate(
          id: 'ambulance',
          name: 'Ambulance',
          area: 'Outpatient Clinic',
          kind: SlotKind.ambulance,
          timeRange: TimeRange(
            start: LocalTime(9, 0),
            end: LocalTime(13, 0),
          ),
          role: DutyRole.outpatientClinic,
          allowedRanks: {
            DoctorRank.resident,
            DoctorRank.specialist,
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
        ),
        SlotTemplate(
          id: 'neurosonology',
          name: 'Neurosonology',
          area: 'Neurosonology',
          kind: SlotKind.neurosonology,
          timeRange: TimeRange(
            start: LocalTime(8, 0),
            end: LocalTime(15, 30),
          ),
          role: DutyRole.neurosonography,
          allowedRanks: {
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
          requiredCapabilities: {Capability.canDoNeurosonography},
        ),
        SlotTemplate(
          id: 'neurovascular_board',
          name: 'Neurovascular Interdisciplinary Board',
          area: 'Board',
          kind: SlotKind.neurovascularBoard,
          timeRange: TimeRange(
            start: LocalTime(12, 30),
            end: LocalTime(13, 0),
          ),
          role: DutyRole.leader,
          allowedRanks: {
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
          weekdayRule: WeekdayRule.thursdayOnly,
        ),
        SlotTemplate(
          id: 'ofo_board',
          name: 'OFO Board',
          area: 'Board',
          kind: SlotKind.ofoBoard,
          timeRange: TimeRange(
            start: LocalTime(13, 0),
            end: LocalTime(14, 0),
          ),
          role: DutyRole.leader,
          allowedRanks: {
            DoctorRank.seniorSpecialist,
            DoctorRank.consultant,
            DoctorRank.head,
          },
          weekdayRule: WeekdayRule.wednesdayOnly,
        ),
      ],
    );
  }
}

class CalendarDayInfo {
  final DateTime date;
  final bool isWeekend;
  final bool isPublicHoliday;
  final String? publicHolidayName;

  CalendarDayInfo({
    required this.date,
    required this.isWeekend,
    required this.isPublicHoliday,
    this.publicHolidayName,
  });
}

class DoctorSlotAvailability {
  final Doctor doctor;
  final DailySlot slot;

  DoctorSlotAvailability({
    required this.doctor,
    required this.slot,
  });

  bool get isEligible {
    return slot.template.canBeFilledBy(doctor);
  }
}


class ManualHolidayProvider implements HolidayProvider {
  final Map<String, String> holidays;

  ManualHolidayProvider({
    this.holidays = const {},
  });

  @override
  CalendarDayInfo getDayInfo(DateTime date) {
    final key = _dateKey(date);
    final holidayName = holidays[key];

    return CalendarDayInfo(
      date: date,
      isWeekend: date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday,
      isPublicHoliday: holidayName != null,
      publicHolidayName: holidayName,
    );
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }
}


class AvailabilityValidator {
  List<Conflict> validateDay(RosterDay day) {
    final conflicts = <Conflict>[];

    conflicts.addAll(_validateEligibility(day));
    conflicts.addAll(_validateOverlappingAvailabilities(day));

    return conflicts;
  }

  List<Conflict> _validateEligibility(RosterDay day) {
    final conflicts = <Conflict>[];

    for (final availability in day.availabilities) {
      if (!availability.isEligible) {
        conflicts.add(
          Conflict(
            '${availability.doctor.fullName} is not eligible to choose '
            '${availability.slot.template.name}',
          ),
        );
      }
    }

    return conflicts;
  }

  List<Conflict> _validateOverlappingAvailabilities(RosterDay day) {
    final conflicts = <Conflict>[];

    for (var i = 0; i < day.availabilities.length; i++) {
      for (var j = i + 1; j < day.availabilities.length; j++) {
        final availabilityA = day.availabilities[i];
        final availabilityB = day.availabilities[j];

        final sameDoctor =
            availabilityA.doctor.id == availabilityB.doctor.id;

        final overlaps = availabilityA.slot.template.timeRange.overlaps(
          availabilityB.slot.template.timeRange,
        );

        final allowedOverlap = DefaultOverlapRules.isAllowed(
          availabilityA.slot.template.kind,
          availabilityB.slot.template.kind,
        );

        if (sameDoctor && overlaps && !allowedOverlap) {
          conflicts.add(
            Conflict(
              '${availabilityA.doctor.fullName} chose overlapping slots: '
              '${availabilityA.slot.template.name} and '
              '${availabilityB.slot.template.name}',
            ),
          );
        }
      }
    }

    return conflicts;
  }
}

class AvailabilityDecision {
  final bool accepted;
  final String? reason;

  AvailabilityDecision.accepted()
      : accepted = true,
        reason = null;

  AvailabilityDecision.rejected(this.reason) : accepted = false;
}

class AvailabilityService {
  AvailabilityDecision canDoctorChooseSlot({
    required Doctor doctor,
    required DailySlot slot,
    required RosterDay day,
  }) {
    final proposedAvailability = DoctorSlotAvailability(
      doctor: doctor,
      slot: slot,
    );

    if (!proposedAvailability.isEligible) {
      return AvailabilityDecision.rejected(
        '${doctor.fullName} is not eligible for ${slot.template.name}',
      );
    }

    final alreadyChosenSameSlot = day.availabilities.any(
      (availability) =>
          availability.doctor.id == doctor.id &&
          availability.slot.id == slot.id,
    );

    if (alreadyChosenSameSlot) {
      return AvailabilityDecision.rejected(
        '${doctor.fullName} has already chosen ${slot.template.name}',
      );
    }

    for (final existingAvailability in day.availabilities) {
      if (existingAvailability.doctor.id != doctor.id) {
        continue;
      }

      final overlaps = existingAvailability.slot.template.timeRange.overlaps(
        slot.template.timeRange,
      );

      final allowedOverlap = DefaultOverlapRules.isAllowed(
        existingAvailability.slot.template.kind,
        slot.template.kind,
      );

      if (overlaps && !allowedOverlap) {
        return AvailabilityDecision.rejected(
          '${doctor.fullName} already chose overlapping slot '
          '${existingAvailability.slot.template.name}',
        );
      }
    }

    return AvailabilityDecision.accepted();
  }
}

class SubmissionValidator {
  List<Conflict> validate(
    AvailabilitySubmission submission,
  ) {
    final conflicts = <Conflict>[];

    conflicts.addAll(
      _validateAvailabilitys(submission),
    );

    return conflicts;
  }

  List<Conflict> _validateAvailabilitys(
    AvailabilitySubmission submission,
  ) {
    final conflicts = <Conflict>[];

    final validator = AvailabilityValidator();

    final groupedByDay =
        <String, List<DoctorSlotAvailability>>{};

    for (final availability
        in submission.availabilities) {
      final date = availability.slot.date;

      final key =
          '${date.year}-${date.month}-${date.day}';

      groupedByDay.putIfAbsent(
        key,
        () => [],
      );

      groupedByDay[key]!.add(
        availability,
      );
    }

    for (final entry in groupedByDay.entries) {
      final dateParts = entry.key.split('-');

      final day = RosterDay(
        calendarInfo: CalendarDayInfo(
          date: DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          ),
          isWeekend: false,
          isPublicHoliday: false,
        ),
        slots: entry.value
            .map((a) => a.slot)
            .toList(),
        availabilities: entry.value,
      );

      conflicts.addAll(
        validator.validateDay(day),
      );
    }

    return conflicts;
  }
}


class AssignmentDecision {
  final bool accepted;
  final String? reason;

  AssignmentDecision.accepted()
      : accepted = true,
        reason = null;

  AssignmentDecision.rejected(this.reason) : accepted = false;
}

class AssignmentResult {
  final bool success;
  final String? reason;
  final RosterDay? updatedDay;

  AssignmentResult.success(this.updatedDay)
      : success = true,
        reason = null;

  AssignmentResult.failure(this.reason)
      : success = false,
        updatedDay = null;
}

class AssignmentService {
  AssignmentDecision canAssignDoctorToSlot({
    required Doctor doctor,
    required DailySlot slot,
    required RosterDay day,
  }) {
    final proposedAssignment = Assignment(
      doctor: doctor,
      slot: slot,
    );

    if (!proposedAssignment.isValidForSlot) {
      return AssignmentDecision.rejected(
        '${doctor.fullName} is not eligible for ${slot.template.name}',
      );
    }

    final alreadyAssignedSameSlot = day.assignments.any(
      (assignment) =>
          assignment.doctor.id == doctor.id &&
          assignment.slot.id == slot.id,
    );

    if (alreadyAssignedSameSlot) {
      return AssignmentDecision.rejected(
        '${doctor.fullName} is already assigned to ${slot.template.name}',
      );
    }

    final assignmentsForSlot = day.assignments
        .where((assignment) => assignment.slot.id == slot.id)
        .toList();

    if (assignmentsForSlot.length >= slot.template.maxDoctors) {
      return AssignmentDecision.rejected(
        '${slot.template.name} is already full',
      );
    }

    for (final existingAssignment in day.assignments) {
      if (existingAssignment.doctor.id != doctor.id) {
        continue;
      }

      final overlaps = existingAssignment.slot.template.timeRange.overlaps(
        slot.template.timeRange,
      );

      final allowedOverlap = DefaultOverlapRules.isAllowed(
        existingAssignment.slot.template.kind,
        slot.template.kind,
      );

      if (overlaps && !allowedOverlap) {
        return AssignmentDecision.rejected(
          '${doctor.fullName} is already assigned to overlapping slot '
          '${existingAssignment.slot.template.name}',
        );
      }
    }

    return AssignmentDecision.accepted();
  }

  AssignmentResult assignDoctorToSlot({
    required Doctor doctor,
    required DailySlot slot,
    required RosterDay day,
  }) {
    final decision = canAssignDoctorToSlot(
      doctor: doctor,
      slot: slot,
      day: day,
    );

    if (!decision.accepted) {
      return AssignmentResult.failure(decision.reason);
    }

    final updatedDay = RosterDay(
      calendarInfo: day.calendarInfo,
      slots: day.slots,
      availabilities: day.availabilities,
      assignments: [
        ...day.assignments,
        Assignment(
          doctor: doctor,
          slot: slot,
        ),
      ],
    );

    return AssignmentResult.success(updatedDay);
  }

  AssignmentResult removeDoctorFromSlot({
    required Doctor doctor,
    required DailySlot slot,
    required RosterDay day,
  }) {
    final assignmentExists = day.assignments.any(
      (assignment) =>
          assignment.doctor.id == doctor.id &&
          assignment.slot.id == slot.id,
    );

    if (!assignmentExists) {
      return AssignmentResult.failure(
        '${doctor.fullName} is not assigned to ${slot.template.name}',
      );
    }

    final updatedAssignments = day.assignments
        .where(
          (assignment) =>
              !(assignment.doctor.id == doctor.id &&
                  assignment.slot.id == slot.id),
        )
        .toList();

    final updatedDay = RosterDay(
      calendarInfo: day.calendarInfo,
      slots: day.slots,
      availabilities: day.availabilities,
      assignments: updatedAssignments,
    );

    return AssignmentResult.success(updatedDay);
  }
}

class Assignment {
  final Doctor doctor;
  final DailySlot slot;
  final AssignmentState state;

  Assignment({
    required this.doctor,
    required this.slot,
    this.state = AssignmentState.provisional,
  });

  bool get isValidForSlot {
    return slot.template.canBeFilledBy(doctor);
  }
}


class SlotViewModel {
  final DailySlot slot;
  final List<Assignment> assignments;
  final bool isOpen;

  SlotViewModel({
    required this.slot,
    required this.assignments,
    required this.isOpen,
  });

  List<String> get assignedDoctorNames {
    return assignments
        .map((assignment) => assignment.doctor.fullName)
        .toList();
  }
}
class DayViewService {
  List<SlotViewModel> getSlotViews(
    RosterDay day,
  ) {
    final views = <SlotViewModel>[];

    for (final slot in day.slots) {
      final assignments = day.assignments
          .where(
            (assignment) =>
                assignment.slot.id == slot.id,
          )
          .toList();

      views.add(
        SlotViewModel(
          slot: slot,
          assignments: assignments,
          isOpen: assignments.length <
              slot.template.maxDoctors,
        ),
      );
    }

    return views;
  }
}


class MonthDayViewModel {
  final DateTime date;

  final bool isWeekend;
  final bool isPublicHoliday;
  final String? holidayName;

  final int openSlots;
  final int filledSlots;

  MonthDayViewModel({
    required this.date,
    required this.isWeekend,
    required this.isPublicHoliday,
    required this.holidayName,
    required this.openSlots,
    required this.filledSlots,
  });
}

class MonthViewService {
  List<MonthDayViewModel> getMonthView(
    RosterMonth roster,
  ) {
    final result = <MonthDayViewModel>[];

    for (final day in roster.days) {
      int openSlots = 0;
      int filledSlots = 0;

      for (final slot in day.slots) {
        final assignmentCount = day.assignments
            .where(
              (a) => a.slot.id == slot.id,
            )
            .length;

        if (assignmentCount >=
            slot.template.maxDoctors) {
          filledSlots++;
        } else {
          openSlots++;
        }
      }

      result.add(
        MonthDayViewModel(
          date: day.date,
          isWeekend:
              day.calendarInfo.isWeekend,
          isPublicHoliday:
              day.calendarInfo.isPublicHoliday,
          holidayName:
              day.calendarInfo.publicHolidayName,
          openSlots: openSlots,
          filledSlots: filledSlots,
        ),
      );
    }

    return result;
  }
}

class DemoDataFactory {
  static List<Doctor> createDoctors() {
    return [
      Doctor(
        id: 'pikija',
        firstName: 'Slaven',
        lastName: 'Pikija',
        rank: DoctorRank.consultant,
        capabilities: {
          Capability.canLead,
          Capability.canDoNeurosonography,
        },
      ),

      Doctor(
        id: 'resident1',
        firstName: 'Anna',
        lastName: 'Resident',
        rank: DoctorRank.resident,
      ),
    ];
  }
}

class EligibilityResult {
  final bool eligible;
  final String? reason;

  EligibilityResult({
    required this.eligible,
    this.reason,
  });
}

class EligibilityService {
  EligibilityResult canTakeSlot({
    required Doctor doctor,
    required DailySlot slot,
    required RosterDay day,
  }) {
    final decision = AssignmentService().canAssignDoctorToSlot(
      doctor: doctor,
      slot: slot,
      day: day,
    );

    return EligibilityResult(
      eligible: decision.accepted,
      reason: decision.reason,
    );
  }
}

class SlotDisplayModel {
  final SlotViewModel slotView;
  final EligibilityResult eligibility;

  SlotDisplayModel({
    required this.slotView,
    required this.eligibility,
  });
}

class SlotDisplayService {
  List<SlotDisplayModel> buildSlotDisplayModels({
    required RosterDay day,
    required Doctor doctor,
  }) {
    final slotViews =
        DayViewService().getSlotViews(day);

    return slotViews.map((slotView) {
      return SlotDisplayModel(
        slotView: slotView,
        eligibility:
            EligibilityService().canTakeSlot(
          doctor: doctor,
          slot: slotView.slot,
          day: day,
        ),
      );
    }).toList();
  }
}

class RosterStatisticsService {

  double coveragePercentage({
    required RosterMonth roster,
  }) {
    int totalCapacity = 0;
    int assigned = 0;

    for (final day in roster.days) {
      for (final slot in day.slots) {
        totalCapacity += slot.template.maxDoctors;
      }

      assigned += day.assignments.length;
    }

    if (totalCapacity == 0) {
      return 0;
    }

    return assigned / totalCapacity * 100;
  }

  int countOpenSlots({
      required RosterMonth roster,
    }) {
      int count = 0;

      for (final day in roster.days) {
        for (final slot in day.slots) {
          final assignmentCount = day.assignments
              .where(
                (a) => a.slot.id == slot.id,
              )
              .length;

          if (assignmentCount < slot.template.maxDoctors) {
            count++;
          }
        }
      }

      return count;
    }

  int countAssignedSlots({
      required RosterMonth roster,
    }) {
      return roster.days
          .expand((day) => day.assignments)
          .length;
    }

  int countAssignmentsForDoctorInMonth({
    required RosterMonth roster,
    required Doctor doctor,
  }) {
    return roster.days
        .expand((day) => day.assignments)
        .where(
          (assignment) =>
              assignment.doctor.id == doctor.id,
        )
        .length;
  }

  int countAssignmentsForDoctorInDay({
    required RosterDay day,
    required Doctor doctor,
  }) {
    return day.assignments
        .where(
          (assignment) =>
              assignment.doctor.id == doctor.id,
        )
        .length;
  }

  List<Assignment> getAssignmentsForDoctorInMonth({
    required RosterMonth roster,
    required Doctor doctor,
  }) {
    final assignments = roster.days
        .expand((day) => day.assignments)
        .where(
          (assignment) => assignment.doctor.id == doctor.id,
        )
        .toList();

    assignments.sort((a, b) {
      final dateCompare = a.slot.date.compareTo(b.slot.date);

      if (dateCompare != 0) {
        return dateCompare;
      }

      return a.slot.template.timeRange.start.minutesSinceMidnight.compareTo(
        b.slot.template.timeRange.start.minutesSinceMidnight,
      );
    });

    return assignments;
  }

  Map<SlotKind, int> countAssignmentsBySlotKindForDoctorInMonth({
    required RosterMonth roster,
    required Doctor doctor,
  }) {
    final assignments = getAssignmentsForDoctorInMonth(
      roster: roster,
      doctor: doctor,
    );

    final counts = <SlotKind, int>{};

    for (final assignment in assignments) {
      final kind = assignment.slot.template.kind;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }

    return counts;
  }
}

// ******************************************************
// QUERIES
// ******************************************************
class AssignmentQueryService {
  List<Assignment> getAssignmentsForDoctor({
    required Doctor doctor,
    required RosterMonth roster,
  }) {
    final assignments = <Assignment>[];

    for (final day in roster.days) {
      assignments.addAll(
        day.assignments.where(
          (assignment) =>
              assignment.doctor.id == doctor.id,
        ),
      );
    }

    return assignments;
  }
}

