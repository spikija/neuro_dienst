import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';

/// Local print choices only. Known unchecked IDs distinguish deselection from
/// roles created after the previous export; deleted IDs are ignored.
class ReportPrintPreferences {
  static const key = 'neuro_admin.printRoleColumns.v1';
  const ReportPrintPreferences();

  Future<Set<String>> restore(ReportDocument report) async {
    final defaults = report.columns.map((c) => c.id).toSet();
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      final values = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final c in report.availableRoleColumns)
          if (values[c.id] is bool
              ? values[c.id] == true
              : defaults.contains(c.id))
            c.id,
      };
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save(ReportDocument report, Set<String> selected) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        for (final c in report.availableRoleColumns)
          c.id: selected.contains(c.id),
      }),
    );
    if (!saved) throw StateError('Print preferences could not be saved');
  }
}

Set<String> usedReportRoleIds(ReportDocument report) => {
  for (final c in report.availableRoleColumns)
    if (report.rows.any(
      (row) =>
          row.cells[c.id]?.hasMatchingSlot == true ||
          row.cells[c.id]?.assignments.isNotEmpty == true,
    ))
      c.id,
};
