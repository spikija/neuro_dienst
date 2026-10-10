import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:supabase/supabase.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_directory.dart';
import 'package:neuro_admin_services/supabase_admin_reader.dart';
import 'package:neuro_core/neuro_core.dart';

void main() {
  test(
    'linked viewers are excluded from directory, facts, reports and workload input',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public',
      );
      addTearDown(client.dispose);
      server.listen((request) async {
        final data = switch (request.uri.path.split('/').last) {
          'profiles' => [
            {'id': 'viewer-user'},
          ],
          'doctors' => [
            for (final id in ['real', 'viewer'])
              {
                'id': id,
                'auth_user_id': id == 'viewer' ? 'viewer-user' : null,
                'first_name': id,
                'last_name': 'Test',
                'rank': 'resident',
                'capabilities': [],
                'is_active': id == 'viewer',
                'print_order': 0,
              },
          ],
          'rosters' => [
            {'id': 'month', 'phase': 'draft', 'content_version': 1},
          ],
          'roster_days' => [
            {
              'id': 'day',
              'roster_id': 'month',
              'date': '2026-10-01',
              'is_weekend': false,
              'is_public_holiday': false,
            },
          ],
          'roles' => [
            {
              'id': 'role',
              'code': 'AMB',
              'name': 'Clinic',
              'allowed_ranks': ['resident'],
              'required_capabilities': [],
              'is_active': true,
            },
          ],
          'roster_slots' => [
            {
              'id': 'slot',
              'roster_day_id': 'day',
              'role_id': 'role',
              'starts_at': '2026-10-01T06:00:00Z',
              'ends_at': '2026-10-01T14:00:00Z',
              'max_doctors': 3,
            },
          ],
          'assignments' => [
            for (final id in ['real', 'viewer'])
              {
                'id': 'a-$id',
                'roster_slot_id': 'slot',
                'doctor_id': id,
                'state': 'confirmed',
              },
          ],
          'absences' => [
            {
              'id': 'absence',
              'doctor_id': 'viewer',
              'starts_on': '2026-10-01',
              'ends_on': '2026-10-01',
              'type': 'vacation',
            },
          ],
          _ => <Object>[],
        };
        expect(request.method, 'GET');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      });
      final reader = SupabaseRosterReader(client);
      expect((await reader.loadPhysicians()).map((p) => p.physician.id), [
        'real',
      ]);
      final snapshot = await reader.loadMonth(
        const RosterChoice('month', 2026, 10, RosterPhase.draft),
      );
      expect(snapshot.doctors.map((d) => d.id), ['real']);
      expect(snapshot.inactiveDoctorIds, {'real'});
      expect(snapshot.facts.map((a) => a.doctor.id), ['real']);
      final configuration = ReportConfiguration(
        roles: [ReportRoleSetting(snapshot.roles.single, 0, true)],
        physicianPrintOrder: {},
      );
      for (final layout in [ReportLayout.roles, ReportLayout.physicians]) {
        final report = const FactualReportProjection().project(
          snapshot,
          configuration,
          ReportRequest(RosterVersion('month', 1), layout),
        );
        expect(report.physicianLabels.keys, ['real']);
        expect(
          report.rows
              .expand((r) => r.cells.values)
              .expand((c) => c.assignments)
              .map((a) => a.doctor.id)
              .toSet(),
          {'real'},
        );
        if (layout == ReportLayout.physicians) {
          expect(report.columns.map((c) => c.id), ['real']);
        }
      }
      final workload = const RecordedWorkloadService().forPhysician(
        snapshot,
        snapshot.doctors.single,
        WorkloadWindow(DateTime.utc(2026, 10), DateTime.utc(2026, 11)),
      );
      expect(workload.assignments, 1);
    },
  );
  test(
    'directory command retains version and request ID and invitation uses existing endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public',
      );
      addTearDown(client.dispose);
      final bodies = <Map>[];
      final paths = <String>[];
      server.listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        bodies.add(body);
        paths.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('invite-doctor')) {
          request.response.statusCode = 201;
          request.response.write(
            jsonEncode({'accountRole': body['accountRole'], 'doctorId': null}),
          );
        } else {
          request.response.write(
            jsonEncode({'success': true, 'requestId': body['p_request_id']}),
          );
        }
        await request.response.close();
      });
      final service = SupabaseDirectoryService(client);
      final change = DirectoryChange(
        operation: AdminWriteIntent.create(),
        directory: 'viewers',
        id: 'viewer',
        updatedAt: '2026-10-10T01:02:03.123456Z',
        changes: {'access_revoked': true},
      );
      await service.change(change);
      await service.change(change);
      expect(bodies[0], bodies[1]);
      expect(bodies.first['p_expected_updated_at'], change.updatedAt);
      final receipt = await service.invite(
        InvitationRequest(
          operation: AdminWriteIntent.create(),
          accountRole: ManagedAccountRole.viewer,
          email: 'test@example.invalid',
          firstName: 'Test',
          lastName: 'Viewer',
          language: ProfileLanguage.de,
        ),
      );
      expect(paths.last, '/functions/v1/invite-doctor');
      expect(bodies.last['accountRole'], 'viewer');
      expect(bodies.last.containsKey('rank'), false);
      expect(receipt.physicianId, isNull);
      // A successful HTTP response without the promised physician identity
      // might already have sent mail. Never offer a blind invitation retry.
      await expectLater(
        service.invite(
          InvitationRequest(
            operation: AdminWriteIntent.create(),
            accountRole: ManagedAccountRole.doctor,
            email: 'doctor@example.invalid',
            firstName: 'Test',
            lastName: 'Physician',
            language: ProfileLanguage.de,
            rank: DoctorRank.resident,
          ),
        ),
        throwsA(
          isA<DirectoryFailure>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            true,
          ),
        ),
      );
    },
  );
}
