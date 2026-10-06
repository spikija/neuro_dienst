import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/auth/session_gate.dart';
import 'package:neuro_admin/data/roster_reader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final role in ['doctor', 'viewer', 'admin', 'missing']) {
    test('server-validated $role access; only admin reaches MFA/ready', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var assurance = 'aal1';
      var userChecks = 0;
      var rejectUser = false;
      const user = {
        'id': 'account',
        'aud': 'authenticated',
        'email': 'test@example.invalid',
      };
      String token() {
        String encode(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        return '${encode({'alg': 'HS256'})}.${encode({'sub': 'account', 'aal': assurance, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test';
      }

      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        Object? payload;
        if (request.uri.path == '/auth/v1/token') {
          payload = {
            'access_token': token(),
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': user,
          };
        } else if (request.uri.path == '/auth/v1/user') {
          userChecks++;
          if (rejectUser) {
            request.response.statusCode = 401;
            payload = {'message': 'Invalid session'};
          } else {
            payload = user;
          }
        } else if (request.uri.path == '/rest/v1/profiles') {
          payload = role == 'missing' ? null : {'role': role};
        } else if (request.uri.path == '/auth/v1/factors') {
          payload = {'all': [], 'totp': [], 'phone': []};
        } else {
          request.response.statusCode = 404;
          payload = {};
        }
        await request.drain<void>();
        request.response.write(jsonEncode(payload));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(client.dispose);
      await client.auth.setSession('test-refresh');
      final gateway = SupabaseSessionGateway(client);
      expect(
        (await gateway.checkAccess()).level,
        role == 'admin' ? AccessLevel.requiresMfa : AccessLevel.denied,
      );
      assurance = 'aal2';
      await client.auth.setSession('test-refresh');
      expect(
        (await gateway.checkAccess()).level,
        role == 'admin' ? AccessLevel.ready : AccessLevel.denied,
      );
      expect(userChecks, greaterThanOrEqualTo(2));
      rejectUser = true;
      await expectLater(gateway.checkAccess(), throwsA(isA<AuthException>()));
      expect(
        requests
            .where((r) => r.contains('/rest/'))
            .every((r) => r.startsWith('GET ')),
        isTrue,
      );
    });
  }

  test(
    'roster reads are GET-only, date-bounded and paginated; inactive physicians are not filtered',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Uri>[];
      final methods = <String>[];
      server.listen((request) async {
        requests.add(request.uri);
        methods.add(request.method);
        final table = request.uri.path.split('/').last;
        final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
        final rows = switch (table) {
          'rosters' => [
            {'id': 'm', 'year': 2026, 'month': 10, 'phase': 'published'},
          ],
          'doctors' =>
            offset == 0
                ? [
                    for (var i = 0; i < 500; i++)
                      {
                        'id': 'd$i',
                        'first_name': 'Test',
                        'last_name': '$i',
                        'rank': 'resident',
                        'is_active': false,
                        'capabilities': [],
                      },
                  ]
                : [
                    {
                      'id': 'last',
                      'first_name': 'Last',
                      'last_name': 'Doctor',
                      'rank': 'resident',
                      'is_active': true,
                    },
                  ],
          'roles' => [
            {'id': 'role', 'code': 'UNCLASSIFIED', 'name': 'Unclassified duty'},
          ],
          'roster_days' => [
            {
              'id': 'day',
              'roster_id': 'm',
              'date': '2026-10-01',
              'is_weekend': false,
              'is_public_holiday': false,
            },
          ],
          'roster_slots' => [
            {
              'id': 'slot',
              'roster_day_id': 'day',
              'role_id': 'role',
              'starts_at': '2026-10-01T23:00:00+02:00',
              'ends_at': '2026-10-02T08:00:00+02:00',
              'max_doctors': 1,
            },
          ],
          'assignments' => [
            {
              'id': 'a',
              'doctor_id': 'd0',
              'roster_slot_id': 'slot',
              'state': 'confirmed',
            },
          ],
          _ => <Map<String, Object>>[],
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(rows));
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public',
      );
      addTearDown(client.dispose);
      final reader = SupabaseRosterReader(client);
      final month = (await reader.listMonths()).single;
      final data = await reader.loadMonth(month);
      expect(data.doctors, hasLength(501));
      expect(data.inactiveDoctorIds, hasLength(500));
      expect(data.facts.single.duty.role.code, 'UNCLASSIFIED');
      expect(data.facts.single.duty.startsAt, DateTime.utc(2026, 10, 1, 21));
      expect(methods.every((method) => method == 'GET'), isTrue);
      final doctorQueries = requests
          .where((uri) => uri.path.endsWith('/doctors'))
          .toList();
      expect(doctorQueries, hasLength(2));
      expect(
        doctorQueries.every(
          (uri) => !uri.queryParameters.containsKey('is_active'),
        ),
        isTrue,
      );
      final dayQuery = requests.firstWhere(
        (uri) => uri.path.endsWith('/roster_days'),
      );
      expect(dayQuery.queryParametersAll['date'], [
        'gte.2026-07-03',
        'lte.2026-10-31',
      ]);
      expect(
        requests.every((uri) => !uri.queryParameters.containsKey('created_at')),
        isTrue,
      );
    },
  );
}
