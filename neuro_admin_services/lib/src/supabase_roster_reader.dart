import 'package:neuro_core/neuro_core.dart';
import 'package:supabase/supabase.dart';
import 'read_models.dart';
import 'scheduling_time.dart';

/// Read-only adapter. It deliberately exposes no mutation operations.
class SupabaseRosterReader implements RosterReader, PhysicianReadService {
  final SupabaseClient client;

  SupabaseRosterReader(this.client);

  Future<List<JsonRow>> _doctorRows() => _pages(
    (start, end) => client
        .from('doctors')
        .select(
          'id, first_name, last_name, rank, capabilities, print_order, is_active',
        )
        .order('id')
        .range(start, end),
  );

  @override
  Future<List<PhysicianRecord>> loadPhysicians({
    bool includeInactive = true,
  }) async {
    final rows = await _doctorRows();
    return [
      for (final row in rows)
        if (includeInactive || row['is_active'] == true)
          PhysicianRecord(
            _doctor(row, const []),
            isActive: row['is_active'] == true,
          ),
    ]..sort((a, b) => _compareDoctors(a.physician, b.physician));
  }

  @override
  Future<List<RosterChoice>> listMonths() async {
    final rows = await _pages(
      (start, end) => client
          .from('rosters')
          .select('id, year, month, phase')
          .order('year', ascending: false)
          .order('month', ascending: false)
          .range(start, end),
    );
    return [
      for (final row in rows)
        RosterChoice(
          row['id'] as String,
          row['year'] as int,
          row['month'] as int,
          _enumValue(RosterPhase.values, row['phase']),
        ),
    ];
  }

  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) async {
    // Load inactive doctors too: old assignments must not disappear.
    final doctors = await _doctorRows();
    final days = await _pages(
      (start, end) => client
          .from('roster_days')
          .select(
            'id, roster_id, date, is_weekend, is_public_holiday, public_holiday_name',
          )
          .gte(
            'date',
            _date(
              DateTime.utc(
                month.year,
                month.month,
              ).subtract(const Duration(days: 90)),
            ),
          )
          .lte('date', _date(DateTime.utc(month.year, month.month + 1, 0)))
          .order('id')
          .range(start, end),
    );
    final rosterRows = await _pages(
      (start, end) => client
          .from('rosters')
          .select('id, phase')
          .order('id')
          .range(start, end),
    );
    final roles = await _pages(
      (start, end) => client
          .from('roles')
          .select('id, code, name, area, allowed_ranks, required_capabilities')
          .order('id')
          .range(start, end),
    );
    final slots = await _byIds(
      'roster_slots',
      'id, roster_day_id, role_id, starts_at, ends_at, max_doctors',
      'roster_day_id',
      days.map((row) => row['id'] as String).toList(),
    );
    final assignments = await _byIds(
      'assignments',
      'id, roster_slot_id, doctor_id, state',
      'roster_slot_id',
      slots.map((row) => row['id'] as String).toList(),
    );
    final first = _date(
      DateTime.utc(month.year, month.month).subtract(const Duration(days: 90)),
    );
    final last = _date(DateTime(month.year, month.month + 1, 0));
    final absences = await _pages(
      (start, end) => client
          .from('absences')
          .select('id, doctor_id, starts_on, ends_on, type')
          .lte('starts_on', last)
          .gte('ends_on', first)
          .order('id')
          .range(start, end),
    );
    return decodeRoster(
      month,
      doctors: doctors,
      rosterRows: rosterRows,
      days: days,
      roles: roles,
      slots: slots,
      assignments: assignments,
      absences: absences,
    );
  }

  Future<List<JsonRow>> _byIds(
    String table,
    String columns,
    String field,
    List<String> ids,
  ) async {
    final rows = <JsonRow>[];
    for (var i = 0; i < ids.length; i += 100) {
      final batch = ids.sublist(i, (i + 100).clamp(0, ids.length));
      rows.addAll(
        await _pages(
          (start, end) => client
              .from(table)
              .select(columns)
              .inFilter(field, batch)
              .order('id')
              .range(start, end),
        ),
      );
    }
    return rows;
  }
}

Future<List<JsonRow>> _pages(
  Future<List<JsonRow>> Function(int, int) fetch,
) async {
  const size = 500;
  final result = <JsonRow>[];
  for (var offset = 0; ; offset += size) {
    final page = await fetch(offset, offset + size - 1);
    result.addAll(page);
    if (page.length < size) return result;
  }
}

RosterSnapshot decodeRoster(
  RosterChoice month, {
  required List<JsonRow> doctors,
  required List<JsonRow> days,
  required List<JsonRow> roles,
  required List<JsonRow> slots,
  required List<JsonRow> assignments,
  required List<JsonRow> absences,
  required List<JsonRow> rosterRows,
}) {
  final periods = <String, List<AvailabilityPeriod>>{};
  for (final row in absences) {
    final value = row['type'] == 'external_rotation'
        ? 'externalRoatation'
        : row['type'] == 'duty_24'
        ? 'duty24'
        : row['type'];
    (periods[_id(row, 'doctor_id')] ??= []).add(
      AvailabilityPeriod(
        start: _calendarDate(row['starts_on']),
        end: _calendarDate(row['ends_on']),
        type: _enumValue(AvailabilityType.values, value),
      ),
    );
  }
  final doctorById = {
    for (final row in doctors)
      _id(row, 'id'): _doctor(row, periods[row['id']] ?? []),
  };
  if (periods.keys.any((id) => !doctorById.containsKey(id))) {
    throw const FormatException(
      'An absence references an unavailable physician. Refresh or check backend access.',
    );
  }
  final dayById = {for (final row in days) _id(row, 'id'): row};
  final phaseById = {
    for (final row in rosterRows)
      _id(row, 'id'): _enumValue(RosterPhase.values, row['phase']),
  };
  final roleById = {
    for (final row in roles)
      _id(row, 'id'): StoredRole(
        _id(row, 'id'),
        row['code'] as String,
        row['name'] as String,
      ),
  };
  final slotsByDay = <String, List<StoredDuty>>{};
  final slotById = <String, StoredDuty>{};
  final dayIdBySlot = <String, String>{};
  for (final row in slots) {
    final role = roleById[row['role_id']];
    final day = dayById[row['roster_day_id']];
    if (role == null || day == null) {
      throw const FormatException(
        'A duty references missing roster data. Refresh the month.',
      );
    }
    final start = ViennaSchedulingTime.parseInstant(row['starts_at'] as String);
    final end = ViennaSchedulingTime.parseInstant(row['ends_at'] as String);
    if (!end.isAfter(start)) {
      throw const FormatException('A duty has invalid start/end timestamps.');
    }
    final slot = StoredDuty(
      _id(row, 'id'),
      _calendarDate(day['date']),
      role,
      start,
      end,
      row['max_doctors'] as int,
    );
    slotById[slot.id] = slot;
    final dayId = _id(row, 'roster_day_id');
    dayIdBySlot[slot.id] = dayId;
    (slotsByDay[dayId] ??= []).add(slot);
  }
  final assignmentsByDay = <String, List<AssignmentFact>>{};
  final facts = <AssignmentFact>[];
  for (final row in assignments) {
    final doctor = doctorById[row['doctor_id']];
    final slot = slotById[row['roster_slot_id']];
    if (doctor == null || slot == null) {
      throw const FormatException(
        'An assignment references an unavailable physician or duty. No partial totals are displayed.',
      );
    }
    final dayId = dayIdBySlot[slot.id]!;
    final phase = phaseById[dayById[dayId]!['roster_id']];
    if (phase == null) {
      throw const FormatException('Missing roster phase for an assignment.');
    }
    final fact = AssignmentFact(
      _id(row, 'id'),
      doctor,
      slot,
      _enumValue(AssignmentState.values, row['state']),
      phase,
    );
    facts.add(fact);
    (assignmentsByDay[dayId] ??= []).add(fact);
  }
  final rosterDays = [
    for (final row in days)
      if (row['roster_id'] == month.id)
        StoredDay(
          CalendarDayInfo(
            date: _calendarDate(row['date']),
            isWeekend: row['is_weekend'] as bool,
            isPublicHoliday: row['is_public_holiday'] as bool,
            publicHolidayName: row['public_holiday_name'] as String?,
          ),
          (slotsByDay[row['id']] ?? [])
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt)),
          assignmentsByDay[row['id']] ?? [],
        ),
  ]..sort((a, b) => a.date.compareTo(b.date));
  final orderedDoctors = doctorById.values.toList()..sort(_compareDoctors);
  final actualPhase = phaseById[month.id];
  if (actualPhase == null) {
    throw const FormatException(
      'The selected roster no longer exists. Refresh the list.',
    );
  }
  final historyEnd = DateTime.utc(month.year, month.month);
  final historyStart = historyEnd.subtract(const Duration(days: 90));
  return RosterSnapshot(
    RosterChoice(month.id, month.year, month.month, actualPhase),
    rosterDays,
    orderedDoctors,
    {
      for (final row in doctors)
        if (row['is_active'] == false) _id(row, 'id'),
    },
    facts,
    {
      for (final row in days)
        if (!_calendarDate(row['date']).isBefore(historyStart) &&
            _calendarDate(row['date']).isBefore(historyEnd))
          _calendarDate(row['date']),
    },
  );
}

T _enumValue<T extends Enum>(List<T> values, Object? value) {
  final normalized = value.toString().replaceAll('_', '').toLowerCase();
  return values.firstWhere(
    (item) => item.name.toLowerCase() == normalized,
    orElse: () => throw FormatException('Unsupported database value: $value'),
  );
}

String _id(JsonRow row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Missing required identifier: $key');
  }
  return value;
}

// Calendar dates use UTC midnight as a date-only representation, never an instant
// converted to the workstation timezone. Duty timestamps remain real UTC instants.
DateTime _calendarDate(Object? value) =>
    HospitalDate.parse(value as String).asDateOnlyUtc;
String _date(DateTime date) => date.toIso8601String().split('T').first;

Doctor _doctor(JsonRow row, List<AvailabilityPeriod> periods) => Doctor(
  id: _id(row, 'id'),
  firstName: row['first_name'] as String,
  lastName: row['last_name'] as String,
  rank: _enumValue(DoctorRank.values, row['rank']),
  printOrder: row['print_order'] as int? ?? 0,
  capabilities: {
    for (final value in row['capabilities'] as List? ?? [])
      _enumValue(Capability.values, value),
  },
  availabilities: periods,
);

int _compareDoctors(Doctor a, Doctor b) {
  final order = a.printOrder.compareTo(b.printOrder);
  return order != 0 ? order : a.fullName.compareTo(b.fullName);
}
