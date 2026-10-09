import 'package:neuro_core/neuro_core.dart';
import 'lifecycle.dart';
import 'read_models.dart';
import 'scheduling_time.dart';

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
  ReportDocument({
    required this.request,
    required this.phase,
    required this.configuration,
    required Iterable<ReportColumn> columns,
    required Iterable<ReportRow> rows,
    Iterable<String> parityWarnings = const [],
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(rows),
       parityWarnings = List.unmodifiable(parityWarnings);
}

/// Future adapters load one consistent snapshot including historical physicians,
/// dynamic role metadata, absences and report settings. No implementation yet.
abstract interface class ReportingService {
  Future<ReportDocument> load(ReportRequest request);
}

/// The projection is extracted once from mobile; PDF/printing/localization stay
/// outside this Flutter-free boundary. No duplicated report rules in desktop.
abstract interface class ReportProjectionService {
  ReportDocument project(
    RosterSnapshot snapshot,
    ReportConfiguration configuration,
    ReportRequest request,
  );
}
