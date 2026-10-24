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
    if (selectedDates.isEmpty) return null;
    final request = preview.request;
    final byDate = {for (final result in preview.results) result.date: result};
    // Keep every chosen date, including failures. Omitting blocked dates would
    // turn an invalid selection into a valid, silently reduced assignment.
    final results = [
      for (final date in (selectedDates.toList()..sort()))
        byDate[date] ??
            AssignmentValidationResult(
              date: date,
              slotId: null,
              physicianId: request.physicianId,
              roleId: request.roleId,
              errors: const [
                AssignmentValidationError(
                  AssignmentErrorCode.validationUnavailable,
                  'Selected date has not been validated.',
                ),
              ],
            ),
    ];
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
