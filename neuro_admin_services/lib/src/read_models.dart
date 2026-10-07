import 'package:neuro_core/neuro_core.dart';

typedef JsonRow = Map<String, dynamic>;

/// Metadata for choosing a persisted month; domain objects remain in neuro_core.
class RosterChoice {
  final String id;
  final int year;
  final int month;
  final RosterPhase phase;

  const RosterChoice(this.id, this.year, this.month, this.phase);

  String get label => '$year-${month.toString().padLeft(2, '0')}';
}

/// Database projections preserve dynamic roles and full timestamps. They are
/// not editable domain models: SlotKind cannot represent arbitrary stored roles.
class StoredRole {
  final String id;
  final String code;
  final String name;
  const StoredRole(this.id, this.code, this.name);
}

class StoredDuty {
  final String id;
  final DateTime date;
  final StoredRole role;
  final DateTime startsAt;
  final DateTime endsAt;
  final int capacity;
  const StoredDuty(
    this.id,
    this.date,
    this.role,
    this.startsAt,
    this.endsAt,
    this.capacity,
  );
}

class AssignmentFact {
  final String id;
  final Doctor doctor;
  final StoredDuty duty;
  final AssignmentState state;
  final RosterPhase phase;
  const AssignmentFact(this.id, this.doctor, this.duty, this.state, this.phase);
}

class StoredDay {
  final CalendarDayInfo calendarInfo;
  final List<StoredDuty> slots;
  final List<AssignmentFact> assignments;
  const StoredDay(this.calendarInfo, this.slots, this.assignments);
  DateTime get date => calendarInfo.date;
}

class RosterSnapshot {
  final RosterChoice month;
  final List<StoredDay> days;
  final List<Doctor> doctors;
  final Set<String> inactiveDoctorIds;
  final List<AssignmentFact> facts;
  final Set<DateTime> loadedHistoryDates;
  const RosterSnapshot(
    this.month,
    this.days,
    this.doctors,
    this.inactiveDoctorIds,
    this.facts,
    this.loadedHistoryDates,
  );

  DateTime get historyEnd => DateTime.utc(month.year, month.month);
  DateTime get historyStart => historyEnd.subtract(const Duration(days: 90));
}

abstract interface class RosterReader {
  Future<List<RosterChoice>> listMonths();
  Future<RosterSnapshot> loadMonth(RosterChoice month);
}

/// Directory metadata; absence periods belong to a dated roster query.
class PhysicianRecord {
  final Doctor physician;
  final bool isActive;
  const PhysicianRecord(this.physician, {required this.isActive});
}

abstract interface class PhysicianReadService {
  Future<List<PhysicianRecord>> loadPhysicians({bool includeInactive = true});
}
