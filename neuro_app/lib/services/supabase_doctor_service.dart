import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDoctorService {
  final SupabaseClient _client;

  SupabaseDoctorService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Doctor>> loadActiveDoctors() async {
    final rows = await _client
        .from('doctors')
        .select(
          'id, first_name, last_name, rank, print_order, capabilities, is_active',
        )
        .eq('is_active', true)
        .order('print_order')
        .order('last_name')
        .order('first_name');

    final doctors = rows.map(_doctorFromJson).toList();
    final doctorIds = doctors.map((doctor) => doctor.id).toList();

    if (doctorIds.isEmpty) {
      return doctors;
    }

    final absenceRows = await _client
        .from('absences')
        .select('doctor_id, starts_on, ends_on, type')
        .inFilter('doctor_id', doctorIds)
        .order('starts_on');

    final absencesByDoctorId = <String, List<AvailabilityPeriod>>{};

    for (final row in absenceRows) {
      final doctorId = row['doctor_id'] as String?;

      if (doctorId == null) {
        continue;
      }

      absencesByDoctorId
          .putIfAbsent(doctorId, () => [])
          .add(
            AvailabilityPeriod(
              start: DateTime.parse(row['starts_on'] as String),
              end: DateTime.parse(row['ends_on'] as String),
              type: _availabilityTypeFromDatabase(row['type'] as String?),
            ),
          );
    }

    return doctors
        .map(
          (doctor) => doctor.copyWith(
            availabilities: absencesByDoctorId[doctor.id] ?? const [],
          ),
        )
        .toList();
  }
}

Doctor _doctorFromJson(Map<String, dynamic> json) {
  return Doctor(
    id: json['id'] as String,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    rank: _rankFromDatabase(json['rank'] as String?),
    printOrder: json['print_order'] as int? ?? 0,
    capabilities: _capabilitiesFromDatabase(json['capabilities']),
  );
}

DoctorRank _rankFromDatabase(String? value) {
  switch (value) {
    case 'resident':
      return DoctorRank.resident;
    case 'specialist':
      return DoctorRank.specialist;
    case 'senior_specialist':
      return DoctorRank.seniorSpecialist;
    case 'consultant':
      return DoctorRank.consultant;
    case 'head':
      return DoctorRank.head;
  }

  return DoctorRank.resident;
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

AvailabilityType _availabilityTypeFromDatabase(String? value) {
  switch (value) {
    case 'available':
      return AvailabilityType.available;
    case 'vacation':
      return AvailabilityType.vacation;
    case 'sick_leave':
      return AvailabilityType.sickLeave;
    case 'conference':
      return AvailabilityType.conference;
    case 'external_rotation':
      return AvailabilityType.externalRoatation;
    case 'duty_24':
      return AvailabilityType.duty24;
    case 'post_duty':
      return AvailabilityType.postDuty;
    case 'ef_day':
      return AvailabilityType.efDay;
  }

  return AvailabilityType.vacation;
}
