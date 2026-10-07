/// Explicit desktop reporting policy, independent of neuro_core's fixed roles.
enum WorkloadCategory { station, ambulance, science, duty24h, other }

/// Evidence: supabase/migrations/202606120001_initial_roster_schema.sql.
/// Match exact seeded codes; custom/renamed codes need an explicit policy update.
/// SON/NVB/OFO are separate specialties/boards. ICB has no seeded definition.
/// No stored role identifies 24-hour duties reliably: duty24h is populated only
/// from absences.type=duty_24, never from slot duration or the mobile enum mapper.
WorkloadCategory classifyRoleCode(String code) => switch (code) {
  'SUL' || 'SU1' || 'SU2' => WorkloadCategory.station,
  'AMB' => WorkloadCategory.ambulance,
  'SCI' => WorkloadCategory.science,
  _ => WorkloadCategory.other,
};
