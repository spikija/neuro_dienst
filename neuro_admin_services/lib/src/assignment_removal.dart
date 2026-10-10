import 'admin_contracts.dart';
import 'read_models.dart';
import 'scheduling_time.dart';

enum RemovalScope { role, all }

/// Immutable advisory selection; backend independently enumerates under locks.
final class AssignmentRemovalPreview {
  final RosterSnapshot snapshot;
  final RemovalScope scope;
  final String? roleId;
  final Set<HospitalDate> dates;
  final List<AssignmentFact> assignments;
  AssignmentRemovalPreview._(
    this.snapshot,
    this.scope,
    this.roleId,
    this.dates,
    this.assignments,
  );
  factory AssignmentRemovalPreview(
    RosterSnapshot snapshot,
    Iterable<HospitalDate> dates, {
    required RemovalScope scope,
    String? roleId,
  }) {
    final selected = Set<HospitalDate>.unmodifiable(dates);
    if (selected.isEmpty ||
        selected.length > 31 ||
        selected.any(
          (d) =>
              d.year != snapshot.month.year || d.month != snapshot.month.month,
        ) ||
        (scope == RemovalScope.role) != (roleId != null)) {
      throw ArgumentError('A dated, explicit removal scope is required');
    }
    return AssignmentRemovalPreview._(
      snapshot,
      scope,
      roleId,
      selected,
      List.unmodifiable(
        snapshot.days
            .expand((d) => d.assignments)
            .where(
              (a) =>
                  selected.contains(
                    HospitalDate.fromCalendarComponents(a.duty.date),
                  ) &&
                  (scope == RemovalScope.all || a.duty.role.id == roleId),
            ),
      ),
    );
  }
  Set<HospitalDate> get noOpDates => dates.difference(
    assignments
        .map((a) => HospitalDate.fromCalendarComponents(a.duty.date))
        .toSet(),
  );
}

abstract interface class AssignmentRemovalService {
  Future<AssignmentMutationReceipt> removeDates(
    AssignmentRemovalPreview preview,
    AdminWriteIntent operation,
  );
}
