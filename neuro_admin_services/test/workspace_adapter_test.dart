import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:supabase/supabase.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_workspace.dart';
import 'package:neuro_core/neuro_core.dart';
import 'support/preview_fixture.dart';

void main() {
  test(
    'generation preview and apply use exact server plan and same operation UUID',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public-key',
      );
      addTearDown(client.dispose);
      final calls = <String>[];
      final operation = AdminWriteIntent.create();
      server.listen((http) async {
        final body =
            jsonDecode(await utf8.decoder.bind(http).join())
                as Map<String, dynamic>;
        expect(http.method, 'POST');
        calls.add(http.uri.path);
        http.response.headers.contentType = ContentType.json;
        if (http.uri.path.endsWith('admin_preview_generation')) {
          expect(body['p_roster_id'], isNull);
          http.response.write(
            jsonEncode({
              'ok': true,
              'token': 'server-token',
              'plan': {
                'configurationVersion': 'config',
                'templates': [
                  {'templateId': 'template', 'code': 'ICB', 'name': 'Clinic'},
                ],
                'days': [
                  {
                    'date': '2040-05-01',
                    'isWeekend': false,
                    'holidayName': 'Staatsfeiertag',
                  },
                ],
                'slots': [
                  {
                    'templateId': 'template',
                    'roleId': 'custom',
                    'existingSlotId': null,
                    'date': '2040-05-01',
                    'startsAt': '2040-05-01T06:00:00+00:00',
                    'endsAt': '2040-05-01T14:00:00+00:00',
                    'capacity': 2,
                  },
                ],
                'removedSlotIds': [],
                'impactedAssignmentIds': [],
                'blockers': [],
                'holidaySource': AustrianHolidays.source,
              },
            }),
          );
        } else {
          expect(http.uri.path, '/rest/v1/rpc/admin_apply_generation');
          expect(body['p_token'], 'server-token');
          expect(body['p_request_id'], operation.requestId);
          http.response.write(
            jsonEncode({
              'ok': true,
              'requestId': operation.requestId,
              'rosterId': 'new',
              'contentVersion': 3,
              'year': 2040,
              'month': 5,
              'phase': 'draft',
            }),
          );
        }
        await http.response.close();
      });
      final service = SupabaseWorkspaceService(client);
      final plan = await service.preview(
        RosterGenerationRequest(
          operation,
          year: 2040,
          month: 5,
          expectedConfigurationVersion: 'server-preview',
        ),
      );
      expect(plan.request.expectedConfigurationVersion, 'config');
      expect(plan.slots.single.roleId, 'custom');
      expect(plan.days.single.isPublicHoliday, isTrue);
      expect(
        ViennaSchedulingTime.localTime(plan.slots.single.startsAt).hour,
        8,
      );
      final receipt = await service.apply(
        RosterGenerationCommitRequest(plan, now: DateTime.now()),
      );
      expect(receipt.version.rosterId, 'new');
      expect(receipt.phase, RosterPhase.draft);
      expect(calls, hasLength(2));
    },
  );
  test(
    'removal RPC retains scope, version and retry identity; malformed receipts remain uncertain',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public-key',
      );
      addTearDown(client.dispose);
      final bodies = <Map<String, dynamic>>[];
      var mode = 'ok';
      server.listen((http) async {
        expect(http.method, 'POST');
        expect(http.uri.path, '/rest/v1/rpc/admin_remove_assignments');
        final body =
            jsonDecode(await utf8.decoder.bind(http).join())
                as Map<String, dynamic>;
        bodies.add(body);
        http.response.headers.contentType = ContentType.json;
        http.response.write(
          jsonEncode(
            mode == 'error'
                ? {'ok': false, 'code': 'staleVersion'}
                : {
                    'ok': true,
                    'requestId': body['p_request_id'],
                    'rosterId': 'october',
                    'contentVersion': 2,
                    'removedAssignments': mode == 'malformed'
                        ? null
                        : [
                            {'id': 'a'},
                          ],
                  },
          ),
        );
        await http.response.close();
      });
      final slot = duty(1);
      final p = AssignmentRemovalPreview(
        previewFixture(
          contentVersion: 1,
          facts: [
            AssignmentFact(
              'a',
              ana(),
              slot,
              AssignmentState.confirmed,
              RosterPhase.draft,
            ),
          ],
        ),
        [HospitalDate(2026, 10, 1), HospitalDate(2026, 10, 2)],
        scope: RemovalScope.role,
        roleId: leader.id,
      );
      final service = SupabaseWorkspaceService(client);
      final op = AdminWriteIntent.create();
      expect((await service.removeDates(p, op)).removedAssignmentIds, ['a']);
      expect(bodies.single['p_dates'], ['2026-10-01', '2026-10-02']);
      expect(bodies.single['p_expected_version'], 1);
      expect(bodies.single['p_scope'], 'role');
      mode = 'malformed';
      await expectLater(
        service.removeDates(p, op),
        throwsA(
          isA<AssignmentMutationFailure>().having(
            (e) => e.outcomeUnknown,
            'unknown outcome',
            true,
          ),
        ),
      );
      expect(bodies.last['p_request_id'], op.requestId);
      mode = 'error';
      await expectLater(
        service.removeDates(p, op),
        throwsA(
          isA<AssignmentMutationFailure>().having(
            (e) => e.code,
            'code',
            'staleVersion',
          ),
        ),
      );
    },
  );
}
