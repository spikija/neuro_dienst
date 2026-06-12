import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseDoctorService {
  final SupabaseClient _client;

  SupabaseDoctorService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<List<Doctor>> loadActiveDoctors() async {
    final rows = await _client
        .from('doctors')
        .select('id, first_name, last_name, rank, capabilities, is_active')
        .eq('is_active', true)
        .order('last_name')
        .order('first_name');

    return rows.map(_doctorFromJson).toList();
  }
}

Doctor _doctorFromJson(Map<String, dynamic> json) {
  return Doctor(
    id: json['id'] as String,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    rank: _rankFromDatabase(json['rank'] as String?),
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
