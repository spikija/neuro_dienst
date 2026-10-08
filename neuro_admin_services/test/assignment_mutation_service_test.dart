import 'dart:convert';
import 'dart:io';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_mutations.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

AssignmentCommitRequest request() => AssignmentCommitRequest.atomicApply(
  AdminWriteIntent.create(),
  AssignmentPreview(
    request: AssignmentValidationRequest(
      roster: RosterVersion('roster', 7),
      roleId: 'role',
      physicianId: 'doctor',
      targets: [AssignmentTarget(HospitalDate(2026, 10, 5))],
    ),
    results: [
      AssignmentValidationResult(
        date: HospitalDate(2026, 10, 5),
        slotId: 'slot',
        physicianId: 'doctor',
        roleId: 'role',
      ),
    ],
  ),
);

void main() {
  test(
    'RPC-only adapter preserves request identity/version and structured server failures',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Map<String, dynamic>>[];
      String mode = 'success';
      server.listen((http) async {
        expect(http.method, 'POST');
        expect(http.uri.path, '/rest/v1/rpc/admin_apply_assignments');
        final body =
            jsonDecode(await utf8.decoder.bind(http).join())
                as Map<String, dynamic>;
        requests.add(body);
        http.response.headers.contentType = ContentType.json;
        if (mode == 'transport') {
          http.response.statusCode = 500;
          http.response.write('{"message":"PRIVATE SQL SECRET-TOKEN"}');
        } else {
          http.response.write(
            jsonEncode(
              mode == 'success'
                  ? {
                      'ok': true,
                      'requestId': body['p_request_id'],
                      'rosterId': 'roster',
                      'contentVersion': 8,
                      'addedAssignments': [
                        {'id': 'new'},
                      ],
                    }
                  : {
                      'ok': false,
                      'code': 'validationFailed',
                      'results': [
                        {
                          'date': '2026-10-05',
                          'slotId': 'slot',
                          'errors': ['physicianInactive', 'slotFull'],
                        },
                      ],
                    },
            ),
          );
        }
        await http.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test-key',
      );
      addTearDown(client.dispose);
      final service = SupabaseAssignmentMutationService(client);
      final operation = request();
      expect(operation.preview.authority, ValidationAuthority.advisory);
      final result = await service.bulkAssign(operation);
      expect(result.version.contentVersion, 8);
      expect(result.addedAssignmentIds, ['new']);
      await service.bulkAssign(operation);
      expect(requests[0], requests[1]);
      expect(requests.first['p_expected_version'], 7);
      expect(requests.first['p_dates'], ['2026-10-05']);
      mode = 'validation';
      await expectLater(
        service.bulkAssign(operation),
        throwsA(
          isA<AssignmentMutationFailure>()
              .having(
                (e) => e.results.single.errors.map((e) => e.code).toList(),
                'codes',
                [
                  AssignmentErrorCode.inactivePhysician,
                  AssignmentErrorCode.slotFull,
                ],
              )
              .having((e) => e.outcomeUnknown, 'known rejection', false),
        ),
      );
      mode = 'transport';
      await expectLater(
        service.bulkAssign(operation),
        throwsA(
          isA<AssignmentMutationFailure>()
              .having((e) => e.outcomeUnknown, 'uncertain response', true)
              .having(
                (e) => e.toString().contains('PRIVATE'),
                'no SQL/credentials',
                false,
              ),
        ),
      );
    },
  );
  test(
    'atomic apply rejects unversioned and blocked previews; UUIDs are independent',
    () {
      expect(
        AdminWriteIntent.create().requestId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect({
        for (var i = 0; i < 100; i++) AdminWriteIntent.create().requestId,
      }, hasLength(100));
      final original = request().preview;
      final bad = AssignmentPreview(
        request: original.request,
        results: [
          AssignmentValidationResult(
            date: HospitalDate(2026, 10, 5),
            slotId: null,
            physicianId: 'doctor',
            roleId: 'role',
          ),
        ],
      );
      expect(
        () =>
            AssignmentCommitRequest.atomicApply(AdminWriteIntent.create(), bad),
        throwsStateError,
      );
      final legacy = AssignmentPreview(
        request: AssignmentValidationRequest(
          roster: RosterVersion.unversioned('roster'),
          roleId: 'role',
          physicianId: 'doctor',
          targets: original.request.targets,
        ),
        results: original.results,
      );
      expect(
        () => AssignmentCommitRequest.atomicApply(
          AdminWriteIntent.create(),
          legacy,
        ),
        throwsStateError,
      );
    },
  );
}
