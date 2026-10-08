import 'package:supabase/supabase.dart';

import 'admin_contracts.dart';
import 'assignment_validation.dart';
import 'lifecycle.dart';
import 'scheduling_time.dart';

class SupabaseAssignmentMutationService implements AssignmentMutationService {
  final SupabaseClient client;
  SupabaseAssignmentMutationService(this.client);

  @override
  Future<bool> canApply() async {
    try {
      final user = (await client.auth.getUser()).user;
      if (user == null ||
          client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel !=
              AuthenticatorAssuranceLevels.aal2) {
        return false;
      }
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      return profile?['role'] == 'admin';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AssignmentMutationReceipt> assign(AssignmentCommitRequest request) =>
      bulkAssign(request);

  @override
  Future<AssignmentMutationReceipt> bulkAssign(
    AssignmentCommitRequest request,
  ) async {
    final intent = request.preview.request;
    if (intent.roster.contentVersion == null ||
        intent.replacesAssignmentId != null ||
        !request.preview.allValid) {
      throw StateError('A versioned addition preview is required');
    }
    Object? raw;
    try {
      raw = await client.rpc(
        'admin_apply_assignments',
        params: {
          'p_roster_id': intent.roster.rosterId,
          'p_expected_version': intent.roster.contentVersion,
          'p_physician_id': intent.physicianId,
          'p_role_id': intent.roleId,
          'p_dates': [
            for (final target in intent.targets) target.date.toString(),
          ],
          'p_request_id': request.operation.requestId,
          'p_reason': intent.correctionReason,
        },
      );
    } catch (_) {
      // Never log transport exceptions, JWTs, SQL details, or request headers.
      throw AssignmentMutationFailure('connectionError', outcomeUnknown: true);
    }
    try {
      final data = Map<String, dynamic>.from(raw as Map);
      if (data['ok'] != true) {
        final results = <AssignmentValidationResult>[];
        for (final row in data['results'] as List? ?? []) {
          final codes = (row['errors'] as List).cast<String>();
          final original = request.preview.results
              .where((r) => r.date.toString() == row['date'])
              .firstOrNull;
          results.add(
            AssignmentValidationResult(
              date: HospitalDate.parse(row['date'] as String),
              slotId: row['slotId'] as String?,
              physicianId: intent.physicianId,
              roleId: intent.roleId,
              errors: [
                for (final code in codes)
                  AssignmentValidationError(
                    _code(code),
                    assignmentErrorMessage(code),
                  ),
              ],
              currentAssignments: original?.currentAssignments ?? [],
              matchingSlots: original?.matchingSlots ?? [],
            ),
          );
        }
        if (results.isNotEmpty) {
          AssignmentPreview(request: intent, results: results);
        }
        final code = data['code'] as String? ?? 'internalError';
        throw AssignmentMutationFailure(
          {
                'validationFailed',
                'physicianInactive',
                ...AssignmentErrorCode.values.map((e) => e.name),
              }.contains(code)
              ? code
              : 'internalError',
          results: results,
        );
      }
      if (data['requestId'] != request.operation.requestId ||
          data['rosterId'] != intent.roster.rosterId) {
        throw const FormatException();
      }
      final version = data['contentVersion'] as int;
      final added = (data['addedAssignments'] as List)
          .map((a) => a['id'] as String)
          .toList();
      if (version <= intent.roster.contentVersion! ||
          added.length != intent.targets.length) {
        throw const FormatException();
      }
      return AssignmentMutationReceipt(
        requestId: request.operation.requestId,
        version: RosterVersion(intent.roster.rosterId, version),
        addedAssignmentIds: added,
        removedAssignmentIds: [],
      );
    } on AssignmentMutationFailure {
      rethrow;
    } catch (_) {
      throw AssignmentMutationFailure('invalidResponse', outcomeUnknown: true);
    }
  }

  @override
  Future<AssignmentMutationReceipt> remove(AssignmentRemovalRequest request) =>
      throw UnsupportedError('Removal is not enabled');
  @override
  Future<AssignmentMutationReceipt> replace(
    AssignmentReplacementRequest request,
  ) => throw UnsupportedError('Replacement is not enabled');
}

AssignmentErrorCode _code(String code) => code == 'physicianInactive'
    ? AssignmentErrorCode.inactivePhysician
    : AssignmentErrorCode.values.where((c) => c.name == code).firstOrNull ??
          AssignmentErrorCode.internalError;

String assignmentErrorMessage(String code) => switch (code) {
  'unauthorized' => 'An administrator session is required.',
  'mfaRequired' => 'Verify your authenticator before applying assignments.',
  'staleVersion' => 'Roster data changed. Reload and preview again.',
  'rosterNotEditable' =>
    'Published rosters require a new revision; locked rosters require a correction reason.',
  'missingSlot' => 'No slot exists for this role and date.',
  'ambiguousSlot' => 'Multiple slots match; no slot was chosen.',
  'physicianInactive' => 'Physician is inactive.',
  'physicianNotFound' => 'Physician no longer exists.',
  'physicianNotEligible' => 'Physician rank is not eligible.',
  'missingCapability' => 'Physician lacks a required capability.',
  'roleInactive' => 'Role is inactive or unavailable.',
  'blockingAbsence' => 'A full-day absence blocks this duty.',
  'duplicateAssignment' => 'Physician is already assigned to this slot.',
  'slotFull' => 'Slot is full; no occupant was removed.',
  'overlappingAssignment' => 'An existing or proposed duty overlaps.',
  'invalidDate' => 'Date or roster identity is invalid.',
  'idempotencyConflict' =>
    'Request identity was already used for different inputs.',
  _ => 'The server could not complete the assignment operation.',
};
