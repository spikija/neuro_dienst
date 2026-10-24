import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase/supabase.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_workspace.dart';

void main() {
  test('Absence removal requires a physician and a versioned snapshot', () {
    expect(
      () => AbsenceDayRemovalRequest(
        roster: RosterVersion.unversioned('november'),
        physicianId: 'johanna',
        date: HospitalDate(2026, 11, 18),
        type: AvailabilityType.efDay,
        operation: AdminWriteIntent.create(),
      ),
      throwsArgumentError,
    );
  });

  test(
    'RPC scopes removal to one physician/date and validates retry receipts and failures',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test-key',
      );
      addTearDown(client.dispose);
      var request = AbsenceDayRemovalRequest(
        roster: RosterVersion('november', 1),
        physicianId: 'johanna',
        date: HospitalDate(2026, 11, 18),
        type: AvailabilityType.efDay,
        operation: AdminWriteIntent.create(),
      );
      final bodies = <Object>[];
      String mode = 'success';
      var expectedType = 'ef_day';
      server.listen((http) async {
        final body = jsonDecode(await utf8.decoder.bind(http).join());
        bodies.add(body);
        expect(http.method, 'POST');
        expect(http.uri.path, '/rest/v1/rpc/admin_remove_absence_day');
        expect(body, {
          'p_roster_id': 'november',
          'p_expected_version': 1,
          'p_physician_id': 'johanna',
          'p_date': '2026-11-18',
          'p_type': expectedType,
          'p_request_id': request.operation.requestId,
        });
        http.response.headers.contentType = ContentType.json;
        if (mode == 'missing') {
          http.response.statusCode = 404;
          http.response.write(
            jsonEncode({'code': 'PGRST202', 'message': 'missing function'}),
          );
        } else if (mode == 'stale') {
          http.response.write(
            jsonEncode({'ok': false, 'code': 'staleVersion'}),
          );
        } else {
          http.response.write(
            jsonEncode({
              'ok': true,
              'requestId': request.operation.requestId,
              'rosterId': 'november',
              'physicianId': mode == 'malformed' ? 'wrong' : 'johanna',
              'date': '2026-11-18',
              'type': mode == 'wrongType' ? 'wrong' : expectedType,
              'contentVersion': 2,
            }),
          );
        }
        await http.response.close();
      });
      final service = SupabaseAbsenceDayRemovalService(client);
      await service.removeDay(request);
      await service.removeDay(request);
      expect(bodies.first, bodies.last);
      const types = {
        AvailabilityType.available: 'available',
        AvailabilityType.vacation: 'vacation',
        AvailabilityType.sickLeave: 'sick_leave',
        AvailabilityType.conference: 'conference',
        AvailabilityType.externalRoatation: 'external_rotation',
        AvailabilityType.duty24: 'duty_24',
        AvailabilityType.postDuty: 'post_duty',
        AvailabilityType.efDay: 'ef_day',
        AvailabilityType.zamLateShift: 'zam_late_shift',
        AvailabilityType.zamDaytime: 'zam_daytime',
        AvailabilityType.otherOutpatientClinic: 'other_outpatient_clinic',
        AvailabilityType.otherAbsence: 'other_absence',
      };
      expect(types.keys.toSet(), AvailabilityType.values.toSet());
      for (final entry in types.entries) {
        expectedType = entry.value;
        request = AbsenceDayRemovalRequest(
          roster: RosterVersion('november', 1),
          physicianId: 'johanna',
          date: HospitalDate(2026, 11, 18),
          type: entry.key,
          operation: AdminWriteIntent.create(),
        );
        await service.removeDay(request);
      }
      mode = 'wrongType';
      await expectLater(
        service.removeDay(request),
        throwsA(
          isA<AssignmentMutationFailure>().having(
            (e) => e.outcomeUnknown,
            'uncertain',
            true,
          ),
        ),
      );
      mode = 'stale';
      await expectLater(
        service.removeDay(request),
        throwsA(
          isA<AssignmentMutationFailure>()
              .having((e) => e.code, 'code', 'staleVersion')
              .having((e) => e.outcomeUnknown, 'uncertain', false),
        ),
      );
      mode = 'malformed';
      await expectLater(
        service.removeDay(request),
        throwsA(
          isA<AssignmentMutationFailure>().having(
            (e) => e.outcomeUnknown,
            'uncertain',
            true,
          ),
        ),
      );
      mode = 'missing';
      await expectLater(
        service.removeDay(request),
        throwsA(
          isA<AssignmentMutationFailure>().having(
            (e) => e.code,
            'code',
            'absenceMigrationRequired',
          ),
        ),
      );
    },
  );
}
