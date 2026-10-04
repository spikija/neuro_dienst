import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/services/supabase_doctor_service.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Supabase reload preserves all additional absence reasons and date bounds',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final values = {
        'zam_late_shift': AvailabilityType.zamLateShift,
        'zam_daytime': AvailabilityType.zamDaytime,
        'other_outpatient_clinic': AvailabilityType.otherOutpatientClinic,
        'conference': AvailabilityType.conference,
        'other_absence': AvailabilityType.otherAbsence,
      };
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('/doctors')
                ? [
                    {
                      'id': 'doctor',
                      'first_name': 'Test',
                      'last_name': 'Doctor',
                      'rank': 'consultant',
                      'capabilities': [],
                      'is_active': true,
                    },
                  ]
                : [
                    for (final type in values.keys)
                      {
                        'doctor_id': 'doctor',
                        'starts_on': '2026-06-30',
                        'ends_on': '2026-06-30',
                        'type': type,
                      },
                  ],
          ),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
      );
      addTearDown(client.dispose);
      final doctor = (await SupabaseDoctorService(
        client: client,
      ).loadActiveDoctors()).single;
      expect(doctor.availabilities.map((period) => period.type), values.values);
      expect(doctor.isAbsentOn(DateTime(2026, 6, 30)), isTrue);
      expect(doctor.isAbsentOn(DateTime(2026, 7, 1)), isFalse);
    },
  );
}
