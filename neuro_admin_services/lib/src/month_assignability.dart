import 'assignment_validation.dart';
import 'scheduling_time.dart';

/// Advisory month validity, independent of the user's mutable selection.
final class MonthAssignability {
  final AssignmentPreview preview;
  final Set<HospitalDate> assignableDates;
  final Set<HospitalDate> warningDates;
  final Set<HospitalDate> blockedDates;
  final Set<HospitalDate> missingSlotDates;

  MonthAssignability(this.preview)
    : assignableDates = Set.unmodifiable(
        preview.results.where((r) => r.isValid).map((r) => r.date),
      ),
      warningDates = Set.unmodifiable(
        preview.results
            .where((r) => r.isValid && r.warnings.isNotEmpty)
            .map((r) => r.date),
      ),
      blockedDates = Set.unmodifiable(
        preview.results
            .where(
              (r) =>
                  !r.isValid &&
                  !r.errors.any(
                    (e) => e.code == AssignmentErrorCode.missingSlot,
                  ),
            )
            .map((r) => r.date),
      ),
      missingSlotDates = Set.unmodifiable(
        preview.results
            .where(
              (r) => r.errors.any(
                (e) => e.code == AssignmentErrorCode.missingSlot,
              ),
            )
            .map((r) => r.date),
      );

  /// A subset is still advisory; never reuse a backend token for changed inputs.
  AssignmentPreview? selectedPreview(Set<HospitalDate> selectedDates) {
    final results = preview.results
        .where(
          (r) =>
              selectedDates.contains(r.date) &&
              assignableDates.contains(r.date),
        )
        .toList();
    if (results.isEmpty) return null;
    final request = preview.request;
    return AssignmentPreview(
      request: AssignmentValidationRequest(
        roster: request.roster,
        roleId: request.roleId,
        physicianId: request.physicianId,
        targets: results.map((r) => AssignmentTarget(r.date, slotId: r.slotId)),
        correctionReason: request.correctionReason,
      ),
      results: results,
    );
  }
}
