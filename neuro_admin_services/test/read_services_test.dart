import 'dart:convert';
import 'dart:io';

import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_reader.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  test(
    'physician read contract retains inactive directory entries and only issues GETs',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final methods = <String>[];
      server.listen((request) async {
        methods.add(request.method);
        expect(request.uri.path, '/rest/v1/doctors');
        expect(request.uri.queryParameters.containsKey('is_active'), isFalse);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            {
              'id': 'old',
              'first_name': 'Past',
              'last_name': 'Physician',
              'rank': 'consultant',
              'is_active': false,
              'print_order': 1,
            },
            {
              'id': 'current',
              'first_name': 'Current',
              'last_name': 'Physician',
              'rank': 'resident',
              'is_active': true,
              'print_order': 2,
            },
          ]),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test-key',
      );
      addTearDown(client.dispose);
      final PhysicianReadService service = SupabaseRosterReader(client);
      final all = await service.loadPhysicians();
      expect(all.map((record) => record.physician.id), ['old', 'current']);
      expect(all.first.isActive, isFalse);
      expect(
        all.first.physician.availabilities,
        isEmpty,
        reason: 'Directory records are not a dated absence query',
      );
      final active = await service.loadPhysicians(includeInactive: false);
      expect(active.single.physician.id, 'current');
      expect(methods, ['GET', 'GET']);
    },
  );

  test(
    'shared workload interface counts stored dates and preserves unknown roles',
    () {
      final date = DateTime.utc(2026, 9, 1);
      final doctor = Doctor(
        id: 'doctor',
        firstName: 'Past',
        lastName: 'Physician',
        rank: DoctorRank.consultant,
      );
      final facts = [
        for (final (id, code) in [
          ('leader', 'SUL'),
          ('team', 'SU1'),
          ('custom', 'CUSTOM'),
        ])
          AssignmentFact(
            id,
            doctor,
            StoredDuty(
              id,
              date,
              StoredRole(id, code, code),
              DateTime.utc(2026, 9, 2),
              DateTime.utc(2026, 9, 3),
              1,
            ),
            AssignmentState.provisional,
            RosterPhase.locked,
          ),
      ];
      final snapshot = RosterSnapshot(
        const RosterChoice('month', 2026, 10, RosterPhase.draft),
        [],
        [doctor],
        {'doctor'},
        facts,
        {date},
      );
      const WorkloadReadService service = RecordedWorkloadService();
      final totals = service.forPhysician(
        snapshot,
        doctor,
        WorkloadWindow(snapshot.historyStart, snapshot.historyEnd),
      );
      expect(totals.assignments, 3);
      expect(totals.assignedDays, 1);
      expect(totals.daysFor(WorkloadCategory.station), 1);
      expect(totals.daysFor(WorkloadCategory.other), 1);
      expect(totals.provisional, 3);
      expect(totals.roles.map((value) => value.role.code), contains('CUSTOM'));
    },
  );
}
