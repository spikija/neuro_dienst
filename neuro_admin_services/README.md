# NeuroDienst administrator application services

Flutter-free shared boundary for `neuro_admin` and later `neuro_app` consumers.
`neuro_core` stays unchanged and owns the existing domain types.

Import `package:neuro_admin_services/neuro_admin_services.dart` for contracts,
read models, workload calculations, lifecycle/authorization policies and hospital
date/time helpers. Import `supabase_admin_reader.dart` separately for the optional
GET-only adapter and inject an ordinary authenticated Supabase client.

Implemented: roster/physician reads, recorded workload, advisory snapshot assignment validation,
intended lifecycle/authorization predicates and Europe/Vienna time conversion.
Phase 2C adds `SupabaseAssignmentMutationService` through the optional
`supabase_admin_mutations.dart` entry point: additions call the atomic server
validate-and-apply RPC, with version checks, idempotency and structured failures.
Not implemented: separate authoritative preview tokens, remove/replace adapters,
invitation orchestration, roster generation, version selection or backend RPCs.
Policies are design/application predicates, not evidence of server authorization.
Never use a local preview or these predicates as permission to bypass server validation.

The desktop's previous `lib/data` imports are compatibility exports, not copies.
The mobile app has not been migrated. Its business operations must be extracted
incrementally behind these contracts, not reimplemented in desktop screens.

Run `dart format lib test`, `dart analyze`, and `dart test` here. Tests use
in-memory models and a loopback server; they perform no live Supabase writes.
Read [the Phase 2A design](../docs/neuro_admin_phase_2a.md) before implementing
adapters: it specifies transactions, concurrency, lifecycle, authorization and
timezone migration requirements.
The [Phase 2B implementation](../docs/neuro_admin_phase_2b.md) preserves exact database
role/slot IDs and provides per-date errors, factual warnings and current occupants.
Legacy snapshots are explicitly unversioned and cannot enable writes.
See [Phase 2C](../docs/neuro_admin_phase_2c.md) for the forward migration and safeguards.
See [Phase 2D](../docs/neuro_admin_phase_2d.md) for month-wide assignability,
reporting contracts, and the preview/commit roster-generation design. Reporting
and generation remain contracts only; mobile behavior has not been copied.
