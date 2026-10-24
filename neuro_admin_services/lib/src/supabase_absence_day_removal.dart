import 'package:supabase/supabase.dart';

import 'admin_contracts.dart';
import 'absence_day_removal.dart';

class SupabaseAbsenceDayRemovalService implements AbsenceDayRemovalService {
  final SupabaseClient client;
  SupabaseAbsenceDayRemovalService(this.client);

  @override
  Future<void> removeDay(AbsenceDayRemovalRequest request) async {
    Object? raw;
    try {
      raw = await client.rpc(
        'admin_remove_absence_day',
        params: {
          'p_roster_id': request.roster.rosterId,
          'p_expected_version': request.roster.contentVersion,
          'p_physician_id': request.physicianId,
          'p_date': request.date.toString(),
          'p_type': request.databaseType,
          'p_request_id': request.operation.requestId,
        },
      );
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202') {
        throw AssignmentMutationFailure('absenceMigrationRequired');
      }
      throw AssignmentMutationFailure('connectionError', outcomeUnknown: true);
    } catch (_) {
      throw AssignmentMutationFailure('connectionError', outcomeUnknown: true);
    }
    try {
      final data = Map<String, dynamic>.from(raw as Map);
      if (data['ok'] != true) {
        final code = data['code'];
        throw AssignmentMutationFailure(
          {
                'unauthorized',
                'mfaRequired',
                'staleVersion',
                'invalidRequest',
                'noAbsence',
              }.contains(code)
              ? code as String
              : 'internalError',
        );
      }
      if (data['requestId'] != request.operation.requestId ||
          data['rosterId'] != request.roster.rosterId ||
          data['physicianId'] != request.physicianId ||
          data['date'] != request.date.toString() ||
          data['type'] != request.databaseType ||
          (data['contentVersion'] as int) <= request.roster.contentVersion!) {
        throw const FormatException();
      }
    } on AssignmentMutationFailure {
      rethrow;
    } catch (_) {
      throw AssignmentMutationFailure('invalidResponse', outcomeUnknown: true);
    }
  }
}
