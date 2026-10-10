import 'package:neuro_core/neuro_core.dart';
import 'package:supabase/supabase.dart';
import '../neuro_admin_services.dart';

/// Only explicit RPCs mutate data; transport retries retain the caller's UUID.
class SupabaseWorkspaceService
    implements RosterGenerationService, AssignmentRemovalService {
  final SupabaseClient client;
  SupabaseWorkspaceService(this.client);
  Future<Map<String, dynamic>> _rpc(
    String name,
    Map<String, dynamic> params,
  ) async {
    Object? raw;
    try {
      raw = await client.rpc(name, params: params);
    } catch (_) {
      throw AssignmentMutationFailure('connectionError', outcomeUnknown: true);
    }
    if (raw is! Map || raw['ok'] is! bool) {
      throw AssignmentMutationFailure('invalidResponse', outcomeUnknown: true);
    }
    if (raw['ok'] != true) {
      throw AssignmentMutationFailure(
        raw['code'] as String? ?? 'internalError',
      );
    }
    return Map<String, dynamic>.from(raw);
  }

  @override
  Future<AssignmentMutationReceipt> removeDates(
    AssignmentRemovalPreview preview,
    AdminWriteIntent operation,
  ) async {
    final version = preview.snapshot.contentVersion;
    if (version == null ||
        version < 1 ||
        !RosterLifecyclePolicy.allowsAdminAssignment(
          preview.snapshot.month.phase,
          correctionReason: operation.reason,
        )) {
      throw StateError(
        'Removal requires a versioned editable roster and locked correction reason',
      );
    }
    final data = await _rpc('admin_remove_assignments', {
      'p_roster_id': preview.snapshot.month.id,
      'p_expected_version': version,
      'p_dates': (preview.dates.toList()..sort()).map((d) => '$d').toList(),
      'p_scope': preview.scope.name,
      'p_role_id': preview.roleId,
      'p_request_id': operation.requestId,
      'p_reason': operation.reason,
    });
    try {
      final removed = (data['removedAssignments'] as List)
          .map((r) => r['id'] as String)
          .toList();
      if (data['requestId'] != operation.requestId ||
          data['rosterId'] != preview.snapshot.month.id ||
          data['contentVersion'] is! int ||
          (data['contentVersion'] as int) < version ||
          removed
              .toSet()
              .difference(preview.assignments.map((a) => a.id).toSet())
              .isNotEmpty ||
          removed.length != removed.toSet().length ||
          removed.length != preview.assignments.length) {
        throw AssignmentMutationFailure(
          'invalidResponse',
          outcomeUnknown: true,
        );
      }
      return AssignmentMutationReceipt(
        requestId: operation.requestId,
        version: RosterVersion(data['rosterId'], data['contentVersion']),
        addedAssignmentIds: [],
        removedAssignmentIds: removed,
      );
    } on AssignmentMutationFailure {
      rethrow;
    } catch (_) {
      throw AssignmentMutationFailure('invalidResponse', outcomeUnknown: true);
    }
  }

  @override
  Future<RosterGenerationPlan> preview(
    RosterGenerationRequest request, {
    RosterRevision? existing,
  }) async {
    final data = await _rpc('admin_preview_generation', {
      'p_year': request.year,
      'p_month': request.month,
      'p_roster_id': existing?.version.rosterId,
    });
    final p = data['plan'] as Map;
    final templates = {
      for (final t in p['templates'] as List) t['templateId']: t,
    };
    return RosterGenerationPlan(
      request: RosterGenerationRequest(
        request.operation,
        year: request.year,
        month: request.month,
        expectedConfigurationVersion: p['configurationVersion'],
      ),
      existing: existing == null
          ? null
          : RosterRevision(
              version: RosterVersion(
                existing.version.rosterId,
                p['existingVersion'],
              ),
              year: request.year,
              month: request.month,
              revisionNumber: existing.revisionNumber,
              phase: existing.phase,
              isCurrentPublished: existing.isCurrentPublished,
            ),
      days: [
        for (final d in p['days'])
          AustrianHolidays.day(HospitalDate.parse(d['date'])),
      ],
      slots: [
        for (final s in p['slots'])
          PlannedRosterSlot(
            roleId: s['roleId'],
            templateId: s['templateId'],
            existingSlotId: s['existingSlotId'],
            roleLabel:
                '${templates[s['templateId']]['code']}: ${templates[s['templateId']]['name']}',
            date: HospitalDate.parse(s['date']).asDateOnlyUtc,
            startsAt: DateTime.parse(s['startsAt']),
            endsAt: DateTime.parse(s['endsAt']),
            capacity: s['capacity'],
          ),
      ],
      removedSlotIds: (p['removedSlotIds'] as List).cast<String>(),
      impactedAssignmentIds: (p['impactedAssignmentIds'] as List)
          .cast<String>(),
      blockers: (p['blockers'] as List).cast<String>(),
      holidaySource: p['holidaySource'],
      backendToken: data['token'],
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<RosterRevision> apply(RosterGenerationCommitRequest request) async {
    final plan = request.plan;
    final data = await _rpc('admin_apply_generation', {
      'p_year': plan.request.year,
      'p_month': plan.request.month,
      'p_roster_id': plan.existing?.version.rosterId,
      'p_expected_version': plan.existing?.version.contentVersion,
      'p_token': plan.backendToken,
      'p_request_id': plan.request.operation.requestId,
    });
    try {
      if (data['requestId'] != plan.request.operation.requestId ||
          data['year'] != plan.request.year ||
          data['month'] != plan.request.month ||
          data['phase'] != 'draft' ||
          data['contentVersion'] is! int ||
          (data['contentVersion'] as int) < 1 ||
          (plan.existing != null &&
              data['rosterId'] != plan.existing!.version.rosterId)) {
        throw AssignmentMutationFailure(
          'invalidResponse',
          outcomeUnknown: true,
        );
      }
      return RosterRevision(
        version: RosterVersion(data['rosterId'], data['contentVersion']),
        year: data['year'],
        month: data['month'],
        revisionNumber: 1,
        phase: RosterPhase.draft,
        isCurrentPublished: false,
      );
    } on AssignmentMutationFailure {
      rethrow;
    } catch (_) {
      throw AssignmentMutationFailure('invalidResponse', outcomeUnknown: true);
    }
  }
}
