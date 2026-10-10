import 'package:neuro_core/neuro_core.dart';
import 'lifecycle.dart';
import 'read_models.dart';
import 'scheduling_time.dart';
import 'austrian_holidays.dart';

enum ReportLayout { roles, physicians, personal }

/// Department reports use configured role visibility; personal reports include
/// every assigned role. Both provisional and confirmed facts are retained.
final class ReportRequest {
  final RosterVersion roster;
  final ReportLayout layout;
  final String? physicianId;
  ReportRequest(this.roster, this.layout, {this.physicianId}) {
    if ((layout == ReportLayout.personal) != (physicianId != null) ||
        physicianId?.trim().isEmpty == true) {
      throw ArgumentError(
        'Only a personal report requires a physician identity',
      );
    }
  }
}

final class ReportRoleSetting {
  final StoredRole role;
  final int displayOrder;
  final bool printInReport;
  const ReportRoleSetting(this.role, this.displayOrder, this.printInReport);
}

/// Configuration needs its own authoritative stamp; current roster versions do
/// not cover every future print setting. Never invent one in a legacy adapter.
final class ReportConfiguration {
  final String? version;
  final List<ReportRoleSetting> roles;
  final Map<String, int> physicianPrintOrder;
  ReportConfiguration({
    this.version,
    required Iterable<ReportRoleSetting> roles,
    required Map<String, int> physicianPrintOrder,
  }) : roles = List.unmodifiable(roles),
       physicianPrintOrder = Map.unmodifiable(physicianPrintOrder);
}

final class ReportColumn {
  /// Exact database role/physician identity, never SlotKind or a localized name.
  final String id;
  final String label;
  const ReportColumn(this.id, this.label);
}

/// Keep assignments and absences independently so each established report's
/// precedence rules can be extracted and tested before either client migrates.
final class ReportCell {
  final List<AssignmentFact> assignments;
  final Map<String, List<AvailabilityPeriod>> absencesByPhysician;
  final bool hasMatchingSlot;
  ReportCell({
    required Iterable<AssignmentFact> assignments,
    required Map<String, List<AvailabilityPeriod>> absencesByPhysician,
    required this.hasMatchingSlot,
  }) : assignments = List.unmodifiable(assignments),
       absencesByPhysician = Map.unmodifiable(
         absencesByPhysician.map(
           (key, value) =>
               MapEntry(key, List<AvailabilityPeriod>.unmodifiable(value)),
         ),
       );
}

final class ReportRow {
  final HospitalDate date;
  final CalendarDayInfo calendar;
  final Map<String, ReportCell> cells;
  ReportRow(this.date, this.calendar, Map<String, ReportCell> cells)
    : cells = Map.unmodifiable(cells);
}

final class ReportDocument {
  final ReportRequest request;
  final RosterPhase phase;
  final ReportConfiguration configuration;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;
  final List<String> parityWarnings;
  final Map<String, String> physicianLabels;
  ReportDocument({
    required this.request,
    required this.phase,
    required this.configuration,
    required Iterable<ReportColumn> columns,
    required Iterable<ReportRow> rows,
    Iterable<String> parityWarnings = const [],
    Map<String, String> physicianLabels = const {},
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(rows),
       parityWarnings = List.unmodifiable(parityWarnings),
       physicianLabels = Map.unmodifiable(physicianLabels);
}

/// Adapters load a version-checked snapshot including historical physicians,
/// dynamic role metadata, absences and report settings.
abstract interface class ReportingService {
  Future<ReportDocument> load(ReportRequest request);
}

/// Shared factual projection; PDF/printing/localization stay outside this
/// Flutter-free boundary. Desktop widgets do not calculate report facts.
abstract interface class ReportProjectionService {
  ReportDocument project(
    RosterSnapshot snapshot,
    ReportConfiguration configuration,
    ReportRequest request,
  );
}

/// Shared factual projection: exact IDs, configured columns, all matching slots.
/// Historical assigned physicians are retained even when inactive.
class FactualReportProjection implements ReportProjectionService {
  const FactualReportProjection();
  @override
  ReportDocument project(
    RosterSnapshot snapshot,
    ReportConfiguration configuration,
    ReportRequest request,
  ) {
    if (snapshot.month.id != request.roster.rosterId ||
        (request.roster.contentVersion != null &&
            snapshot.contentVersion != request.roster.contentVersion)) {
      throw StateError('Report snapshot changed; reload');
    }
    final roles = configuration.roles.where((r) => r.printInReport).toList()
      ..sort((a, b) {
        final order = a.displayOrder.compareTo(b.displayOrder);
        return order != 0 ? order : a.role.code.compareTo(b.role.code);
      });
    final visibleIds = roles.map((r) => r.role.id).toSet();
    final assignedIds = snapshot.days
        .expand((d) => d.assignments)
        .map((a) => a.doctor.id)
        .toSet();
    final doctors =
        snapshot.doctors
            .where(
              (d) => request.layout == ReportLayout.personal
                  ? d.id == request.physicianId
                  : !snapshot.inactiveDoctorIds.contains(d.id) ||
                        assignedIds.contains(d.id),
            )
            .toList()
          ..sort((a, b) {
            final order =
                (configuration.physicianPrintOrder[a.id] ?? a.printOrder)
                    .compareTo(
                      configuration.physicianPrintOrder[b.id] ?? b.printOrder,
                    );
            if (order != 0) return order;
            final rank = b.rank.index.compareTo(a.rank.index);
            if (rank != 0) return rank;
            final last = a.lastName.compareTo(b.lastName);
            return last != 0 ? last : a.firstName.compareTo(b.firstName);
          });
    final columns = request.layout == ReportLayout.roles
        ? roles
              .map(
                (r) =>
                    ReportColumn(r.role.id, '${r.role.code}: ${r.role.name}'),
              )
              .toList()
        : doctors.map((d) => ReportColumn(d.id, d.fullName)).toList();
    final days = {
      for (final d in snapshot.days)
        HospitalDate.fromCalendarComponents(d.date): d,
    };
    return ReportDocument(
      physicianLabels: {for (final d in snapshot.doctors) d.id: d.fullName},
      request: request,
      phase: snapshot.month.phase,
      configuration: configuration,
      columns: columns,
      rows: [
        for (
          var n = 1;
          n <=
              DateTime.utc(
                snapshot.month.year,
                snapshot.month.month + 1,
                0,
              ).day;
          n++
        )
          () {
            final date = HospitalDate(
              snapshot.month.year,
              snapshot.month.month,
              n,
            );
            final day = days[date];
            final absences = {
              for (final d in doctors)
                if (d.absenceOn(date.asDateOnlyUtc) != null)
                  d.id: [d.absenceOn(date.asDateOnlyUtc)!],
            };
            return ReportRow(date, AustrianHolidays.day(date), {
              for (final c in columns)
                c.id: ReportCell(
                  assignments: (day?.assignments ?? <AssignmentFact>[]).where(
                    (a) => request.layout == ReportLayout.roles
                        ? a.duty.role.id == c.id
                        : a.doctor.id == c.id &&
                              (request.layout == ReportLayout.personal ||
                                  visibleIds.contains(a.duty.role.id)),
                  ),
                  absencesByPhysician: request.layout == ReportLayout.roles
                      ? absences
                      : {if (absences[c.id] != null) c.id: absences[c.id]!},
                  hasMatchingSlot: request.layout == ReportLayout.roles
                      ? day?.slots.any((s) => s.role.id == c.id) == true
                      : day != null,
                ),
            });
          }(),
      ],
    );
  }
}

/// Screen text adapter, reusable by both clients; full facts remain in cells.
String reportCellText(ReportCell cell, ReportLayout layout) {
  if (layout == ReportLayout.physicians &&
      cell.absencesByPhysician.isNotEmpty) {
    return cell.absencesByPhysician.values
        .expand((a) => a)
        .map((a) => a.label)
        .toSet()
        .join(', ');
  }
  const priority = [
    'SUL',
    'SU1',
    'SU2',
    'AMB',
    'ICB',
    'SON',
    'NVB',
    'OFO',
    'SCI',
  ];
  int roleOrder(String code) {
    final index = priority.indexOf(code.toUpperCase());
    return index < 0 ? 99 : index;
  }

  final labels =
      cell.assignments
          .map(
            (a) => layout == ReportLayout.roles
                ? a.doctor.lastName
                : a.duty.role.code,
          )
          .toList()
        ..sort(
          (a, b) => layout == ReportLayout.roles
              ? a.compareTo(b)
              : roleOrder(a).compareTo(roleOrder(b)),
        );
  return labels.isEmpty ? (cell.hasMatchingSlot ? '—' : '') : labels.join(', ');
}
