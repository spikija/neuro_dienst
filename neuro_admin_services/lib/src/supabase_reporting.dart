import 'package:supabase/supabase.dart';
import 'reporting.dart';
import 'supabase_roster_reader.dart';
import 'read_models.dart';

class SupabaseReportingService implements ReportingService {
  final SupabaseClient client;
  SupabaseReportingService(this.client);
  @override
  Future<ReportDocument> load(ReportRequest request) async {
    final reader = SupabaseRosterReader(client);
    final month = (await reader.listMonths())
        .where((m) => m.id == request.roster.rosterId)
        .first;
    final snapshot = await reader.loadMonth(month);
    final settings = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('roles')
          .select('id,code,name,display_order,print_in_report,is_active')
          .order('id')
          .range(offset, offset + 499);
      settings.addAll(page);
      if (page.length < 500) break;
    }
    final version = await client
        .from('rosters')
        .select('content_version')
        .eq('id', month.id)
        .single();
    if (version['content_version'] != snapshot.contentVersion) {
      throw StateError('Report data changed; reload');
    }
    return const FactualReportProjection().project(
      snapshot,
      ReportConfiguration(
        roles: [
          for (final r in settings)
            ReportRoleSetting(
              StoredRole(
                r['id'],
                r['code'],
                r['name'],
                isActive: r['is_active'],
              ),
              r['display_order'],
              r['print_in_report'] == true,
            ),
        ],
        physicianPrintOrder: {
          for (final d in snapshot.doctors) d.id: d.printOrder,
        },
      ),
      request,
    );
  }
}
