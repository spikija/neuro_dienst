import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseRosterService {
  final SupabaseClient _client;

  SupabaseRosterService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<ReportRole>> listReportRoles({bool onlyPrintable = false}) async {
    var query = _client
        .from('roles')
        .select('id, code, name, display_order, print_in_report')
        .eq('is_active', true);

    if (onlyPrintable) {
      query = query.eq('print_in_report', true);
    }

    final rows = await query.order('display_order').order('code');
    return rows.map((row) => ReportRole.fromJson(row)).toList();
  }

  Future<void> updateRolePrintInReport({
    required String roleId,
    required bool printInReport,
  }) async {
    await _client
        .from('roles')
        .update({'print_in_report': printInReport})
        .eq('id', roleId);
  }

  Future<void> updateRoleDisplayOrder({
    required String roleId,
    required int displayOrder,
  }) async {
    await _client
        .from('roles')
        .update({'display_order': displayOrder})
        .eq('id', roleId);
  }

  Future<List<RosterSummary>> listRosters() async {
    final rows = await _client
        .from('rosters')
        .select('id, year, month, phase, updated_at')
        .order('year', ascending: false)
        .order('month', ascending: false);

    return rows.map((row) => RosterSummary.fromJson(row)).toList();
  }

  Future<RosterMonth?> loadRoster({
    required int year,
    required int month,
    required List<Doctor> doctors,
  }) async {
    final rosterRow = await _client
        .from('rosters')
        .select('id, year, month, phase')
        .eq('year', year)
        .eq('month', month)
        .maybeSingle();

    if (rosterRow == null) {
      return null;
    }

    final rosterId = rosterRow['id'] as String;
    final dayRows = await _client
        .from('roster_days')
        .select('id, date, is_weekend, is_public_holiday, public_holiday_name')
        .eq('roster_id', rosterId)
        .order('date');
    final dayIds = dayRows.map((row) => row['id'] as String).toList();

    if (dayIds.isEmpty) {
      return RosterMonth(
        year: year,
        month: month,
        days: const [],
        phase: _phaseFromDatabase(rosterRow['phase'] as String?),
      );
    }

    final slotRows = await _client
        .from('roster_slots')
        .select('id, roster_day_id, role_id, starts_at, ends_at, max_doctors')
        .inFilter('roster_day_id', dayIds);
    final roleIds = slotRows.map((row) => row['role_id'] as String).toSet();
    final slotIds = slotRows.map((row) => row['id'] as String).toList();

    final roleRows = roleIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('roles')
              .select(
                'id, code, name, area, max_doctors, allowed_ranks, required_capabilities',
              )
              .inFilter('id', roleIds.toList());
    final roleById = {
      for (final row in roleRows)
        row['id'] as String: _RoleRecord.fromJson(row),
    };

    final assignmentRows = slotIds.isEmpty
        ? <Map<String, dynamic>>[]
        : await _client
              .from('assignments')
              .select('roster_slot_id, doctor_id, state')
              .inFilter('roster_slot_id', slotIds);
    final doctorById = {for (final doctor in doctors) doctor.id: doctor};

    final slotsByDayId = <String, List<DailySlot>>{};
    final slotById = <String, DailySlot>{};

    for (final row in slotRows) {
      final role = roleById[row['role_id'] as String];

      if (role == null) {
        continue;
      }

      final startsAt = DateTime.parse(row['starts_at'] as String).toLocal();
      final endsAt = DateTime.parse(row['ends_at'] as String).toLocal();
      final slot = DailySlot(
        id: row['id'] as String,
        date: DateTime(startsAt.year, startsAt.month, startsAt.day),
        template: SlotTemplate(
          id: role.id,
          name: role.name,
          area: role.area,
          kind: _slotKindFromRole(role),
          timeRange: TimeRange(
            start: LocalTime(startsAt.hour, startsAt.minute),
            end: LocalTime(endsAt.hour, endsAt.minute),
          ),
          role: _dutyRoleFromRole(role),
          allowedRanks: role.allowedRanks,
          requiredCapabilities: role.requiredCapabilities,
          maxDoctors: row['max_doctors'] as int? ?? role.maxDoctors,
        ),
      );

      slotById[slot.id] = slot;
      slotsByDayId
          .putIfAbsent(row['roster_day_id'] as String, () => [])
          .add(slot);
    }

    for (final slots in slotsByDayId.values) {
      slots.sort(
        (a, b) => a.template.timeRange.start.minutesSinceMidnight.compareTo(
          b.template.timeRange.start.minutesSinceMidnight,
        ),
      );
    }

    final assignmentsByDayId = <String, List<Assignment>>{};

    for (final row in assignmentRows) {
      final slot = slotById[row['roster_slot_id'] as String];
      final doctor = doctorById[row['doctor_id'] as String];

      if (slot == null || doctor == null) {
        continue;
      }

      final dayKey =
          slotRows.firstWhere(
                (slotRow) => slotRow['id'] == slot.id,
              )['roster_day_id']
              as String;

      assignmentsByDayId
          .putIfAbsent(dayKey, () => [])
          .add(
            Assignment(
              doctor: doctor,
              slot: slot,
              state: _assignmentStateFromDatabase(row['state'] as String?),
            ),
          );
    }

    final days = [
      for (final row in dayRows)
        RosterDay(
          calendarInfo: CalendarDayInfo(
            date: DateTime.parse(row['date'] as String),
            isWeekend: row['is_weekend'] as bool? ?? false,
            isPublicHoliday: row['is_public_holiday'] as bool? ?? false,
            publicHolidayName: row['public_holiday_name'] as String?,
          ),
          slots: slotsByDayId[row['id'] as String] ?? const [],
          assignments: assignmentsByDayId[row['id'] as String] ?? const [],
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    return RosterMonth(
      year: year,
      month: month,
      days: days,
      phase: _phaseFromDatabase(rosterRow['phase'] as String?),
    );
  }
}

class ReportRole {
  final String id;
  final String code;
  final String name;
  final int displayOrder;
  final bool printInReport;

  const ReportRole({
    required this.id,
    required this.code,
    required this.name,
    required this.displayOrder,
    required this.printInReport,
  });

  factory ReportRole.fromJson(Map<String, dynamic> json) {
    return ReportRole(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayOrder: json['display_order'] as int? ?? 0,
      printInReport: json['print_in_report'] as bool? ?? true,
    );
  }
}

class RosterSummary {
  final String id;
  final int year;
  final int month;
  final RosterPhase phase;
  final DateTime? updatedAt;

  const RosterSummary({
    required this.id,
    required this.year,
    required this.month,
    required this.phase,
    required this.updatedAt,
  });

  factory RosterSummary.fromJson(Map<String, dynamic> json) {
    final updatedAtValue = json['updated_at'] as String?;

    return RosterSummary(
      id: json['id'] as String,
      year: json['year'] as int,
      month: json['month'] as int,
      phase: _phaseFromDatabase(json['phase'] as String?),
      updatedAt: updatedAtValue == null ? null : DateTime.parse(updatedAtValue),
    );
  }
}

class _RoleRecord {
  final String id;
  final String code;
  final String name;
  final String area;
  final int maxDoctors;
  final Set<DoctorRank> allowedRanks;
  final Set<Capability> requiredCapabilities;

  const _RoleRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.area,
    required this.maxDoctors,
    required this.allowedRanks,
    required this.requiredCapabilities,
  });

  factory _RoleRecord.fromJson(Map<String, dynamic> json) {
    return _RoleRecord(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      area: json['area'] as String? ?? '',
      maxDoctors: json['max_doctors'] as int? ?? 1,
      allowedRanks: _ranksFromDatabase(json['allowed_ranks']),
      requiredCapabilities: _capabilitiesFromDatabase(
        json['required_capabilities'],
      ),
    );
  }
}

RosterPhase _phaseFromDatabase(String? value) {
  switch (value) {
    case 'open_for_selection':
      return RosterPhase.openForSelection;
    case 'locked':
      return RosterPhase.locked;
    case 'published':
      return RosterPhase.published;
    case 'draft':
    default:
      return RosterPhase.draft;
  }
}

AssignmentState _assignmentStateFromDatabase(String? value) {
  return value == 'confirmed'
      ? AssignmentState.confirmed
      : AssignmentState.provisional;
}

SlotKind _slotKindFromRole(_RoleRecord role) {
  switch (role.code.toUpperCase()) {
    case 'SCI':
      return SlotKind.science;
    case 'SUL':
      return SlotKind.strokeUnitLeader;
    case 'SU1':
      return SlotKind.strokeUnitTeam1;
    case 'SU2':
      return SlotKind.strokeUnitTeam2;
    case 'AMB':
    case 'ICB':
      return SlotKind.ambulance;
    case 'SON':
      return SlotKind.neurosonology;
    case 'NVB':
      return SlotKind.neurovascularBoard;
    case 'OFO':
      return SlotKind.ofoBoard;
  }

  if (role.name.toLowerCase().contains('ambulance')) {
    return SlotKind.ambulance;
  }

  return SlotKind.science;
}

DutyRole _dutyRoleFromRole(_RoleRecord role) {
  final code = role.code.toUpperCase();

  if (code == 'AMB' ||
      code == 'ICB' ||
      role.name.toLowerCase().contains('ambulance')) {
    return DutyRole.outpatientClinic;
  }

  if (code == 'SON') {
    return DutyRole.neurosonography;
  }

  if (code == 'SU1' || code == 'SU2') {
    return DutyRole.subordinate;
  }

  return DutyRole.leader;
}

Set<DoctorRank> _ranksFromDatabase(Object? value) {
  if (value is! List) {
    return {
      DoctorRank.resident,
      DoctorRank.specialist,
      DoctorRank.seniorSpecialist,
      DoctorRank.consultant,
      DoctorRank.head,
    };
  }

  return value.whereType<String>().map(_rankFromDatabase).toSet();
}

DoctorRank _rankFromDatabase(String value) {
  switch (value) {
    case 'specialist':
      return DoctorRank.specialist;
    case 'senior_specialist':
      return DoctorRank.seniorSpecialist;
    case 'consultant':
      return DoctorRank.consultant;
    case 'head':
      return DoctorRank.head;
    case 'resident':
    default:
      return DoctorRank.resident;
  }
}

Set<Capability> _capabilitiesFromDatabase(Object? value) {
  if (value is! List) {
    return {};
  }

  return value
      .whereType<String>()
      .map(_capabilityFromDatabase)
      .whereType<Capability>()
      .toSet();
}

Capability? _capabilityFromDatabase(String value) {
  switch (value) {
    case 'can_lead':
      return Capability.canLead;
    case 'can_work_outpatient_clinic':
      return Capability.canWorkOutpatientClinic;
    case 'can_do_neurosonography':
      return Capability.canDoNeurosonography;
    case 'can_do_night_duty':
      return Capability.canDoNightDuty;
    case 'can_supervise':
      return Capability.canSupervise;
  }

  return null;
}
