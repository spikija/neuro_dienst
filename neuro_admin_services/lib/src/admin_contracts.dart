import 'dart:math';

import 'package:neuro_core/neuro_core.dart';

import 'assignment_validation.dart';
import 'lifecycle.dart';

/// Idempotency key is scoped to authenticated actor + operation on the server.
final class AdminWriteIntent {
  final String requestId;
  final String? reason;
  factory AdminWriteIntent.create({String? reason}) {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return AdminWriteIntent(
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}',
      reason: reason,
    );
  }
  AdminWriteIntent(this.requestId, {this.reason}) {
    if (requestId.trim().isEmpty) throw ArgumentError('Request ID required');
  }
}

final class RosterWriteIntent {
  final AdminWriteIntent operation;
  final RosterVersion expected;
  RosterWriteIntent(this.operation, this.expected) {
    if (expected.contentVersion == null) {
      throw ArgumentError('Writes require an authoritative content version');
    }
  }
}

final class AssignmentCommitRequest {
  final AdminWriteIntent operation;
  final AssignmentPreview preview;

  /// Phase 2C atomic validate-and-apply path. This does not promote advisory
  /// results to authority: the RPC independently validates under database locks.
  AssignmentCommitRequest.atomicApply(this.operation, this.preview) {
    if (!preview.allValid ||
        preview.request.roster.contentVersion == null ||
        preview.request.replacesAssignmentId != null) {
      throw StateError('A complete versioned addition preview is required');
    }
  }
  AssignmentCommitRequest(
    this.operation,
    this.preview, {
    required DateTime now,
  }) {
    if (!preview.canConfirmAt(now)) {
      throw StateError('A valid, unexpired backend preview is required');
    }
  }
}

final class AssignmentRemovalRequest {
  final RosterWriteIntent intent;
  final String assignmentId;
  AssignmentRemovalRequest(this.intent, this.assignmentId) {
    if (assignmentId.trim().isEmpty) {
      throw ArgumentError('Assignment ID required');
    }
  }
}

final class AssignmentReplacementRequest {
  final AssignmentCommitRequest addition;
  final String replacedAssignmentId;
  AssignmentReplacementRequest(this.addition, this.replacedAssignmentId) {
    if (replacedAssignmentId.trim().isEmpty ||
        addition.preview.request.replacesAssignmentId != replacedAssignmentId) {
      throw ArgumentError(
        'Replacement must match the assignment excluded by its preview',
      );
    }
  }
}

final class AssignmentMutationReceipt {
  final String requestId;
  final RosterVersion version;
  final List<String> addedAssignmentIds;
  final List<String> removedAssignmentIds;
  AssignmentMutationReceipt({
    required this.requestId,
    required this.version,
    required Iterable<String> addedAssignmentIds,
    required Iterable<String> removedAssignmentIds,
  }) : addedAssignmentIds = List.unmodifiable(addedAssignmentIds),
       removedAssignmentIds = List.unmodifiable(removedAssignmentIds);
}

/// Every implementation must use one server transaction, enforce
/// admin+aal2 and phase rules, and revalidate rather than trusting the preview.
abstract interface class AssignmentMutationService {
  Future<bool> canApply();
  Future<AssignmentMutationReceipt> assign(AssignmentCommitRequest request);
  Future<AssignmentMutationReceipt> bulkAssign(AssignmentCommitRequest request);
  Future<AssignmentMutationReceipt> remove(AssignmentRemovalRequest request);
  Future<AssignmentMutationReceipt> replace(
    AssignmentReplacementRequest request,
  );
}

final class AssignmentMutationFailure implements Exception {
  final String code;
  final List<AssignmentValidationResult> results;

  /// A transport failure may have happened after commit; retry the same request.
  final bool outcomeUnknown;
  AssignmentMutationFailure(
    this.code, {
    Iterable<AssignmentValidationResult> results = const [],
    this.outcomeUnknown = false,
  }) : results = List.unmodifiable(results);
  @override
  String toString() => 'Assignment operation failed: $code';
}

abstract interface class RosterLifecycleService {
  Future<RosterRevision> openSelection(RosterWriteIntent intent);
  Future<RosterRevision> lockSelection(RosterWriteIntent intent);
  Future<RosterRevision> publish(RosterWriteIntent intent);

  /// Copy a published revision into a new draft, leaving the original intact.
  Future<RosterRevision> createDraftRevision(RosterWriteIntent published);
}

final class RosterGenerationRequest {
  final AdminWriteIntent operation;
  final int year;
  final int month;
  final String expectedConfigurationVersion;
  RosterGenerationRequest(
    this.operation, {
    required this.year,
    required this.month,
    required this.expectedConfigurationVersion,
  }) {
    if (year < 2000 ||
        year > 2100 ||
        month < 1 ||
        month > 12 ||
        expectedConfigurationVersion.trim().isEmpty) {
      throw ArgumentError('Invalid roster month');
    }
  }
}

abstract interface class RosterGenerationService {
  /// Read-only review of exact active role/template identities, recurrence,
  /// Vienna instants, holiday provenance and impacts on an existing draft.
  Future<RosterGenerationPlan> preview(
    RosterGenerationRequest request, {
    RosterRevision? existing,
  });

  /// One future server transaction: admin+aal2, idempotency, configuration and
  /// roster version checks, audit. Create only if the month remains absent;
  /// regenerate only the reviewed draft. Never delete a published roster.
  Future<RosterRevision> apply(RosterGenerationCommitRequest request);
}

final class PlannedRosterSlot {
  final String roleId;
  final String templateId;
  final DateTime date;
  final DateTime startsAt;
  final DateTime endsAt;
  final int capacity;
  const PlannedRosterSlot({
    required this.roleId,
    required this.templateId,
    required this.date,
    required this.startsAt,
    required this.endsAt,
    required this.capacity,
  });
}

/// Design contract only: legacy mobile generation does not produce this plan.
final class RosterGenerationPlan {
  final RosterGenerationRequest request;
  final RosterRevision? existing;
  final List<CalendarDayInfo> days;
  final List<PlannedRosterSlot> slots;
  final Set<String> removedSlotIds;
  final Set<String> impactedAssignmentIds;
  final List<String> blockers;
  final List<String> warnings;
  final String holidaySource;
  final String? backendToken;
  final DateTime? expiresAt;
  RosterGenerationPlan({
    required this.request,
    this.existing,
    required Iterable<CalendarDayInfo> days,
    required Iterable<PlannedRosterSlot> slots,
    Iterable<String> removedSlotIds = const [],
    Iterable<String> impactedAssignmentIds = const [],
    Iterable<String> blockers = const [],
    Iterable<String> warnings = const [],
    required this.holidaySource,
    this.backendToken,
    this.expiresAt,
  }) : days = List.unmodifiable(days),
       slots = List.unmodifiable(slots),
       removedSlotIds = Set.unmodifiable(removedSlotIds),
       impactedAssignmentIds = Set.unmodifiable(impactedAssignmentIds),
       blockers = List.unmodifiable(blockers),
       warnings = List.unmodifiable(warnings);
}

final class RosterGenerationCommitRequest {
  final RosterGenerationPlan plan;
  RosterGenerationCommitRequest(this.plan, {required DateTime now}) {
    final existing = plan.existing;
    if (plan.backendToken?.trim().isNotEmpty != true ||
        plan.expiresAt == null ||
        !now.toUtc().isBefore(plan.expiresAt!.toUtc()) ||
        plan.blockers.isNotEmpty ||
        plan.impactedAssignmentIds.isNotEmpty ||
        plan.holidaySource.trim().isEmpty ||
        (existing != null &&
            (existing.phase != RosterPhase.draft ||
                existing.version.contentVersion == null ||
                existing.year != plan.request.year ||
                existing.month != plan.request.month))) {
      throw StateError(
        'Generation needs a current backend plan for an absent month or a draft with no assignment loss',
      );
    }
  }
}

/// Deliberately excludes admin provisioning and privilege escalation.
enum ManagedAccountRole { doctor, viewer }

enum ProfileLanguage { en, de }

final class InvitationRequest {
  final AdminWriteIntent operation;
  final ManagedAccountRole accountRole;
  final String email;
  final String firstName;
  final String lastName;
  final ProfileLanguage language;
  final DoctorRank? rank;
  final Set<Capability> capabilities;
  InvitationRequest({
    required this.operation,
    required this.accountRole,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.language,
    this.rank,
    Iterable<Capability> capabilities = const [],
  }) : capabilities = Set.unmodifiable(capabilities) {
    if (email.trim().isEmpty ||
        firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        (accountRole == ManagedAccountRole.doctor && rank == null) ||
        (accountRole == ManagedAccountRole.viewer &&
            (rank != null || this.capabilities.isNotEmpty))) {
      throw ArgumentError(
        'Invitation fields must match the requested doctor/viewer account',
      );
    }
  }
}

enum InvitationDeliveryStatus { queued, sent, retryRequired }

final class InvitationReceipt {
  final String requestId;
  final ManagedAccountRole accountRole;
  final String? physicianId;
  final InvitationDeliveryStatus deliveryStatus;
  const InvitationReceipt(
    this.requestId,
    this.accountRole,
    this.physicianId,
    this.deliveryStatus,
  );
}

final class UserProfileChange {
  final AdminWriteIntent operation;
  final String userId;
  final String displayName;
  final ProfileLanguage language;
  UserProfileChange(
    this.operation, {
    required this.userId,
    required this.displayName,
    required this.language,
  }) {
    if (userId.trim().isEmpty || displayName.trim().isEmpty) {
      throw ArgumentError('User identity and display name required');
    }
  }
}

abstract interface class InvitationUserAdministrationService {
  /// Uses a privileged server endpoint; never an Auth admin key in either app.
  Future<InvitationReceipt> invite(InvitationRequest request);

  /// Changes non-privileged profile fields, never the account role.
  Future<void> updateProfile(UserProfileChange change);
}

enum AdminFailureCode {
  unauthenticated,
  forbidden,
  mfaRequired,
  staleVersion,
  validationFailed,
  notFound,
  idempotencyConflict,
  unavailable,
}

/// Future adapters translate transport/RPC errors to these stable outcomes.
final class AdminOperationFailure implements Exception {
  final AdminFailureCode code;
  final String message;
  final List<AssignmentValidationResult> validationResults;
  AdminOperationFailure(
    this.code,
    this.message, {
    Iterable<AssignmentValidationResult> validationResults = const [],
  }) : validationResults = List.unmodifiable(validationResults);
  @override
  String toString() => 'AdminOperationFailure(${code.name}): $message';
}
