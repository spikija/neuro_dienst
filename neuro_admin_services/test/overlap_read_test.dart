import 'dart:convert';
import 'dart:io';

import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_reader.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  for (final mode in ['stable', 'changed', 'unmigrated']) {
    test('snapshot version loading is safe when $mode', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var reads = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        Object rows = [];
        if (request.uri.path.endsWith('/rosters')) {
          if (request.uri.queryParameters['select'] == 'content_version') {
            reads++;
            if (mode == 'unmigrated') {
              request.response.statusCode = 400;
              rows = {'code': '42703', 'message': 'Column unavailable'};
            } else {
              rows = [
                {'content_version': mode == 'changed' && reads > 1 ? 8 : 7},
              ];
            }
          } else {
            rows = [
              {'id': 'oct', 'phase': 'draft'},
            ];
          }
        }
        request.response.write(jsonEncode(rows));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public',
      );
      addTearDown(client.dispose);
      final load = SupabaseRosterReader(
        client,
      ).loadMonth(const RosterChoice('oct', 2026, 10, RosterPhase.draft));
      if (mode == 'changed') {
        await expectLater(load, throwsA(isA<FormatException>()));
      } else {
        expect((await load).contentVersion, mode == 'stable' ? 7 : null);
      }
      expect(reads, 2);
    });
  }
  test(
    'GET-only reads cover adjacent-month conflicts, absences and role metadata',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Uri>[];
      final methods = <String>[];
      Map<String, Object> day(String id, String roster, String date) => {
        'id': id,
        'roster_id': roster,
        'date': date,
        'is_weekend': true,
        'is_public_holiday': false,
      };
      Map<String, Object> slot(
        String id,
        String day,
        String start,
        String end,
      ) => {
        'id': id,
        'roster_day_id': day,
        'role_id': 'amb',
        'starts_at': start,
        'ends_at': end,
        'max_doctors': 1,
      };
      server.listen((request) async {
        requests.add(request.uri);
        methods.add(request.method);
        final query = request.uri.queryParameters;
        final Object rows = switch (request.uri.path.split('/').last) {
          'profiles' => <Object>[],
          'rosters' => [
            {'id': 'oct', 'phase': 'draft'},
            {'id': 'nov', 'phase': 'published'},
          ],
          'doctors' => [
            {
              'id': 'ana',
              'first_name': 'Ana',
              'last_name': 'Example',
              'rank': 'consultant',
              'capabilities': ['can_lead'],
              'is_active': true,
            },
          ],
          'roles' => [
            {
              'id': 'amb',
              'code': 'AMB',
              'name': 'Ambulance',
              'allowed_ranks': ['consultant'],
              'required_capabilities': [],
              'is_active': true,
            },
          ],
          'roster_days' => [
            query.containsKey('id')
                ? day('nov1', 'nov', '2026-11-01')
                : day('oct31', 'oct', '2026-10-31'),
          ],
          'roster_slots' => [
            slot(
              'overnight',
              'oct31',
              '2026-10-31T22:00:00Z',
              '2026-11-01T08:00:00Z',
            ),
            if (query.containsKey('starts_at'))
              slot(
                'next-month',
                'nov1',
                '2026-11-01T07:00:00Z',
                '2026-11-01T12:00:00Z',
              ),
          ],
          'assignments' => [
            {
              'id': 'existing',
              'roster_slot_id': 'next-month',
              'doctor_id': 'ana',
              'state': 'confirmed',
            },
          ],
          'absences' => [
            {
              'id': 'absence',
              'doctor_id': 'ana',
              'starts_on': '2026-11-01',
              'ends_on': '2026-11-01',
              'type': 'vacation',
            },
          ],
          _ => throw StateError('Unexpected table'),
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(rows));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test-key',
      );
      addTearDown(client.dispose);
      final snapshot = await SupabaseRosterReader(
        client,
      ).loadMonth(const RosterChoice('oct', 2026, 10, RosterPhase.draft));
      expect(methods, everyElement('GET'));
      expect(snapshot.hasOverlapCoverage, isTrue);
      expect(snapshot.days.single.date, DateTime.utc(2026, 10, 31));
      expect(snapshot.facts.single.duty.id, 'next-month');
      expect(snapshot.facts.single.phase, RosterPhase.published);
      expect(snapshot.roles.single.allowedRanks, {DoctorRank.consultant});
      expect(snapshot.roles.single.requiredCapabilities, isEmpty);
      expect(snapshot.roles.single.isActive, isTrue);
      final overlap = requests.singleWhere(
        (uri) => uri.queryParameters.containsKey('starts_at'),
      );
      expect(
        overlap.queryParameters['starts_at'],
        'lt.2026-11-01T08:00:00.000Z',
      );
      expect(overlap.queryParameters['ends_at'], 'gt.2026-10-31T22:00:00.000Z');
      expect(
        requests
            .singleWhere((uri) => uri.path.endsWith('/absences'))
            .queryParameters['starts_on'],
        'lte.2026-11-01',
      );
      final preview = await SnapshotAssignmentValidationService(snapshot)
          .preview(
            AssignmentValidationRequest(
              roster: RosterVersion.unversioned('oct'),
              roleId: 'amb',
              physicianId: 'ana',
              targets: [AssignmentTarget(HospitalDate(2026, 10, 31))],
            ),
          );
      expect(
        preview.results.single.errors.map((e) => e.code),
        containsAll([
          AssignmentErrorCode.overlappingAssignment,
          AssignmentErrorCode.blockingAbsence,
        ]),
      );
      expect(
        preview.results.single.conflictingAssignments.single.id,
        'existing',
      );
    },
  );
}
