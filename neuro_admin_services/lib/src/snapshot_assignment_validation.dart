import 'package:neuro_core/neuro_core.dart';

import 'assignment_validation.dart';
import 'lifecycle.dart';
import 'read_models.dart';
import 'scheduling_time.dart';

/// Exact stored role identities, including custom/inactive roles for inspection.
List<StoredRole> previewRoles(RosterSnapshot snapshot) => [
  ...{
    for (final day in snapshot.days)
      for (final slot in day.slots) slot.role.id: slot.role,
    for (final role in snapshot.roles) role.id: role,
  }.values,
]..sort((a, b) => a.code.compareTo(b.code));

/// Advisory validation of one loaded snapshot. No client/network dependency and
/// no mutation behavior. Backend validation must independently recheck all rules.
class SnapshotAssignmentValidationService
    implements AssignmentValidationService {
  final RosterSnapshot snapshot;
  SnapshotAssignmentValidationService(this.snapshot);

  @override
  Future<AssignmentPreview> preview(AssignmentValidationRequest request) async {
    final doctor = snapshot.doctors
        .where((d) => d.id == request.physicianId)
        .firstOrNull;
    final role = previewRoles(
      snapshot,
    ).where((r) => r.id == request.roleId).firstOrNull;
    final results = [
      for (final target in request.targets)
        _validate(request, target, doctor, role),
    ];
    // Evaluate mutual proposed overlaps without adding them to the snapshot.
    // Already blocked targets are not proposed additions, so do not poison peers.
    final proposed = results.where((r) => r.isValid).toList();
    final mutual = <HospitalDate, List<AssignmentValidationError>>{};
    for (var i = 0; i < proposed.length; i++) {
      for (var j = i + 1; j < proposed.length; j++) {
        final first = proposed[i].matchingSlots.single;
        final second = proposed[j].matchingSlots.single;
        if (_overlaps(first, second) && !_allowedOverlap(first, second)) {
          for (final (a, b) in [
            (proposed[i], proposed[j]),
            (proposed[j], proposed[i]),
          ]) {
            (mutual[a.date] ??= []).add(
              AssignmentValidationError(
                AssignmentErrorCode.overlappingAssignment,
                'Proposed duty overlaps the selected duty on ${b.date}.',
              ),
            );
          }
        }
      }
    }
    return AssignmentPreview(
      request: request,
      results: [
        for (final result in results)
          if (mutual.containsKey(result.date))
            AssignmentValidationResult(
              date: result.date,
              slotId: result.slotId,
              physicianId: result.physicianId,
              roleId: result.roleId,
              errors: [...result.errors, ...mutual[result.date]!],
              warnings: result.warnings,
              currentAssignments: result.currentAssignments,
              conflictingAssignments: result.conflictingAssignments,
              matchingSlots: result.matchingSlots,
            )
          else
            result,
      ],
    );
  }

  AssignmentValidationResult _validate(
    AssignmentValidationRequest request,
    AssignmentTarget target,
    Doctor? doctor,
    StoredRole? role,
  ) {
    final errors = <AssignmentValidationError>[];
    final warnings = <AssignmentValidationWarning>[];
    void error(AssignmentErrorCode code, String text) =>
        errors.add(AssignmentValidationError(code, text));
    final date = target.date.asDateOnlyUtc;
    if (request.roster.rosterId != snapshot.month.id ||
        target.date.year != snapshot.month.year ||
        target.date.month != snapshot.month.month) {
      error(
        AssignmentErrorCode.invalidDate,
        'Date does not belong to this roster.',
      );
    }
    if (request.replacesAssignmentId != null) {
      error(
        AssignmentErrorCode.validationUnavailable,
        'This preview supports additions only; replacement needs a separate reviewed workflow.',
      );
    }
    if (snapshot.month.phase == RosterPhase.locked &&
        !RosterLifecyclePolicy.allowsAdminAssignment(
          snapshot.month.phase,
          correctionReason: request.correctionReason,
        )) {
      warnings.add(
        const AssignmentValidationWarning(
          AssignmentWarningCode.correctionReasonRequired,
          'Locked roster: a correction reason would be required before writing.',
        ),
      );
    } else if (!RosterLifecyclePolicy.allowsAdminAssignment(
      snapshot.month.phase,
      correctionReason: request.correctionReason,
    )) {
      error(
        AssignmentErrorCode.rosterNotEditable,
        'Published rosters require a new revision before editing.',
      );
    }
    if (!snapshot.hasOverlapCoverage) {
      error(
        AssignmentErrorCode.validationUnavailable,
        'Complete interval-conflict data is unavailable. Reload the roster.',
      );
    }
    if (doctor == null) {
      error(
        AssignmentErrorCode.physicianNotFound,
        'Physician was not found in the loaded directory.',
      );
    } else {
      if (snapshot.inactiveDoctorIds.contains(doctor.id)) {
        error(AssignmentErrorCode.inactivePhysician, 'Physician is inactive.');
      }
      if (snapshot.unknownActivityDoctorIds.contains(doctor.id)) {
        error(
          AssignmentErrorCode.validationUnavailable,
          'Physician activity status is unknown.',
        );
      }
      if (role?.allowedRanks == null ||
          role?.requiredCapabilities == null ||
          role?.isActive == null) {
        error(
          AssignmentErrorCode.validationUnavailable,
          'Role eligibility metadata is incomplete.',
        );
      } else {
        if (!role!.isActive!) {
          error(AssignmentErrorCode.roleInactive, 'Duty role is inactive.');
        }
        // Same rank/capability predicate as SlotTemplate.canBeFilledBy. Its API
        // requires fixed role/kind and wall-time objects; do not fabricate them.
        if (!role.allowedRanks!.contains(doctor.rank)) {
          error(
            AssignmentErrorCode.physicianNotEligible,
            'Rank ${doctor.rank.name} is not eligible for ${role.name}.',
          );
        }
        final missing = role.requiredCapabilities!.difference(
          doctor.capabilities,
        );
        if (missing.isNotEmpty) {
          error(
            AssignmentErrorCode.missingCapability,
            'Missing capabilities: ${missing.map((c) => c.name).join(', ')}.',
          );
        }
      }
    }
    final days = snapshot.days
        .where(
          (day) => HospitalDate.fromCalendarComponents(day.date) == target.date,
        )
        .toList();
    final matching = [
      for (final day in days)
        for (final slot in day.slots)
          if (slot.role.id == request.roleId &&
              (target.slotId == null || slot.id == target.slotId))
            slot,
    ];
    final slot = matching.length == 1 ? matching.single : null;
    if (days.length > 1 || matching.length > 1) {
      error(
        AssignmentErrorCode.ambiguousSlot,
        'Several slots match this role/date. Choose a specific slot in a future slot-selection workflow.',
      );
    } else if (slot == null) {
      error(
        AssignmentErrorCode.missingSlot,
        'No concrete slot for this role on ${target.date}.',
      );
    }
    final slotIds = matching.map((s) => s.id).toSet();
    final current = snapshot.facts
        .where((a) => slotIds.contains(a.duty.id))
        .toList();
    final conflicts = <AssignmentFact>[];
    if (slot != null) {
      if (HospitalDate.fromCalendarComponents(slot.date) != target.date ||
          slot.capacity < 1 ||
          !slot.endsAt.isAfter(slot.startsAt)) {
        error(
          AssignmentErrorCode.invalidSlot,
          'Slot date, interval or capacity is invalid.',
        );
      }
      if (current.length >= slot.capacity) {
        error(
          AssignmentErrorCode.slotFull,
          'Slot is full (${current.length}/${slot.capacity}); no occupants will be removed.',
        );
      }
      if (doctor != null) {
        if (current.any((a) => a.doctor.id == doctor.id)) {
          error(
            AssignmentErrorCode.duplicateAssignment,
            'Physician is already assigned to this slot.',
          );
        }
        for (final assignment in snapshot.facts.where(
          (a) => a.doctor.id == doctor.id && a.duty.id != slot.id,
        )) {
          if (!_overlaps(slot, assignment.duty)) continue;
          if (_allowedOverlap(slot, assignment.duty)) {
            warnings.add(
              AssignmentValidationWarning(
                AssignmentWarningCode.allowedOverlap,
                'Existing ${assignment.duty.role.code} duty overlaps; the shared domain policy permits this role pair.',
              ),
            );
          } else {
            conflicts.add(assignment);
            error(
              AssignmentErrorCode.overlappingAssignment,
              '${doctor.fullName} is already assigned to ${assignment.duty.role.name} (${_interval(assignment.duty)}).',
            );
          }
        }
        // Reuse core full-day absence semantics (including post-duty and all
        // "other absences"). Check stored date AND every hospital date touched.
        final occupied = <HospitalDate>{target.date};
        if (slot.endsAt.isAfter(slot.startsAt)) {
          final end = ViennaSchedulingTime.dateOfInstant(
            slot.endsAt.subtract(const Duration(microseconds: 1)),
          );
          for (
            var day = ViennaSchedulingTime.dateOfInstant(slot.startsAt);
            day.compareTo(end) <= 0;
            day = day.addDays(1)
          ) {
            occupied.add(day);
          }
        }
        for (final day in occupied) {
          final absence = doctor.absenceOn(day.asDateOnlyUtc);
          if (absence != null) {
            error(
              AssignmentErrorCode.blockingAbsence,
              '${absence.label} blocks ${day.toString()}.',
            );
          }
        }
      }
    } else if (doctor != null) {
      final absence = doctor.absenceOn(date);
      if (absence != null) {
        error(
          AssignmentErrorCode.blockingAbsence,
          '${absence.label} blocks ${target.date}.',
        );
      }
    }
    if (snapshot.loadedHistoryDates.length < 90) {
      warnings.add(
        AssignmentValidationWarning(
          AssignmentWarningCode.incompleteWorkloadHistory,
          '${snapshot.loadedHistoryDates.length}/90 historical roster dates available; workload may be incomplete.',
        ),
      );
    }
    return AssignmentValidationResult(
      date: target.date,
      slotId: slot?.id,
      physicianId: request.physicianId,
      roleId: request.roleId,
      errors: errors,
      warnings: warnings,
      currentAssignments: current,
      conflictingAssignments: conflicts,
      matchingSlots: matching,
    );
  }
}

bool _overlaps(StoredDuty a, StoredDuty b) =>
    a.startsAt.isBefore(b.endsAt) && b.startsAt.isBefore(a.endsAt);

bool _allowedOverlap(StoredDuty a, StoredDuty b) {
  if (a.date != b.date) return false;
  // Only the four exact seeded codes needed by existing core exceptions.
  // This is not an assignment-role identity or a fallback classification.
  const kinds = {
    'SON': SlotKind.neurosonology,
    'NVB': SlotKind.neurovascularBoard,
    'OFO': SlotKind.ofoBoard,
    'SUL': SlotKind.strokeUnitLeader,
  };
  final first = kinds[a.role.code];
  final second = kinds[b.role.code];
  return first != null &&
      second != null &&
      DefaultOverlapRules.isAllowed(first, second);
}

String _interval(StoredDuty slot) {
  String time(DateTime value) {
    final local = ViennaSchedulingTime.localTime(value);
    return '${HospitalDate.fromCalendarComponents(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  return '${time(slot.startsAt)} - ${time(slot.endsAt)} Europe/Vienna';
}
