import 'lifecycle.dart';
import 'scheduling_time.dart';

enum AssignmentErrorCode {
  physicianNotEligible,
  blockingAbsence,
  overlappingAssignment,
  slotFull,
  duplicateAssignment,
  rosterNotEditable,
  missingSlot,
  inactivePhysician,
  invalidPhase,
  ambiguousSlot,
  staleVersion,
  validationUnavailable,
}

enum AssignmentWarningCode {
  heavyRecentDutyBurden,
  weekendImbalance,
  targetRoleOverAllocation,
}

final class AssignmentValidationError {
  final AssignmentErrorCode code;
  final String message;
  const AssignmentValidationError(this.code, this.message);
}

final class AssignmentValidationWarning {
  final AssignmentWarningCode code;
  final String message;
  const AssignmentValidationWarning(this.code, this.message);
}

final class AssignmentTarget {
  final HospitalDate date;

  /// Null means resolve this role's slot for the date, never pick the first match.
  final String? slotId;
  AssignmentTarget(this.date, {this.slotId}) {
    if (slotId != null && slotId!.trim().isEmpty) {
      throw ArgumentError('Empty slot ID');
    }
  }
}

final class AssignmentValidationRequest {
  final RosterVersion roster;
  final String roleId;
  final String physicianId;
  final List<AssignmentTarget> targets;
  final String? correctionReason;

  /// Replacement preview excludes exactly this assignment before validating.
  final String? replacesAssignmentId;
  AssignmentValidationRequest({
    required this.roster,
    required this.roleId,
    required this.physicianId,
    required Iterable<AssignmentTarget> targets,
    this.correctionReason,
    this.replacesAssignmentId,
  }) : targets = List.unmodifiable(targets) {
    if (roleId.trim().isEmpty ||
        physicianId.trim().isEmpty ||
        this.targets.isEmpty ||
        this.targets.map((target) => target.date).toSet().length !=
            this.targets.length) {
      throw ArgumentError(
        'Role, physician and a nonempty set of distinct target dates required',
      );
    }
    if (replacesAssignmentId != null &&
        (replacesAssignmentId!.trim().isEmpty || this.targets.length != 1)) {
      throw ArgumentError(
        'Replacement requires one target and an assignment identity',
      );
    }
  }
}

final class AssignmentValidationResult {
  final HospitalDate date;
  final String? slotId;
  final String physicianId;
  final String roleId;
  final List<AssignmentValidationError> errors;
  final List<AssignmentValidationWarning> warnings;

  AssignmentValidationResult({
    required this.date,
    required this.slotId,
    required this.physicianId,
    required this.roleId,
    Iterable<AssignmentValidationError> errors = const [],
    Iterable<AssignmentValidationWarning> warnings = const [],
  }) : errors = List.unmodifiable([
         ...errors,
         if (slotId == null || slotId.trim().isEmpty)
           const AssignmentValidationError(
             AssignmentErrorCode.missingSlot,
             'No target slot resolved.',
           ),
       ]),
       warnings = List.unmodifiable(warnings) {
    if (physicianId.trim().isEmpty || roleId.trim().isEmpty) {
      throw ArgumentError('Physician and role identity required');
    }
  }

  /// Fairness warnings can never turn a hard failure into a valid target.
  bool get isValid => errors.isEmpty;
}

enum ValidationAuthority { advisory, backend }

/// Immutable preview bound to the exact request. A local preview cannot be used
/// for a write. Even a backend preview is not a reservation: commit revalidates.
final class AssignmentPreview {
  final AssignmentValidationRequest request;
  final List<AssignmentValidationResult> results;
  final ValidationAuthority authority;
  final String? confirmationToken;
  final DateTime? expiresAt;

  AssignmentPreview({
    required this.request,
    required Iterable<AssignmentValidationResult> results,
    this.authority = ValidationAuthority.advisory,
    this.confirmationToken,
    DateTime? expiresAt,
  }) : results = List.unmodifiable(results),
       expiresAt = expiresAt?.toUtc() {
    final byDate = {for (final result in this.results) result.date: result};
    if (this.results.length != request.targets.length ||
        byDate.length != this.results.length ||
        request.targets.any((target) {
          final result = byDate[target.date];
          return result == null ||
              result.physicianId != request.physicianId ||
              result.roleId != request.roleId ||
              (target.slotId != null &&
                  result.slotId != null &&
                  target.slotId != result.slotId);
        })) {
      throw ArgumentError(
        'Preview must cover every requested date exactly once with matching identities',
      );
    }
    if (authority == ValidationAuthority.backend &&
        (confirmationToken == null ||
            confirmationToken!.trim().isEmpty ||
            expiresAt == null)) {
      throw ArgumentError(
        'Backend preview needs a confirmation token and expiry',
      );
    }
  }

  bool get allValid => results.every((result) => result.isValid);
  bool canConfirmAt(DateTime now) =>
      authority == ValidationAuthority.backend &&
      allValid &&
      now.toUtc().isBefore(expiresAt!);
}

/// No implementation until authoritative data/rules and the backend preview
/// operation exist. Do not adapt fixed SlotKind enums to arbitrary stored roles.
abstract interface class AssignmentValidationService {
  Future<AssignmentPreview> preview(AssignmentValidationRequest request);
}
