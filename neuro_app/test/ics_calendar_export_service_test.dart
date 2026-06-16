import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_app/services/ics_calendar_export_service.dart';
import 'package:neuro_core/neuro_core.dart';

void main() {
  test('builds an ICS calendar with assigned doctor duties', () {
    final doctor = Doctor(
      id: 'doctor-1',
      firstName: 'Slaven',
      lastName: 'Pikija',
      rank: DoctorRank.consultant,
    );
    final otherDoctor = Doctor(
      id: 'doctor-2',
      firstName: 'Other',
      lastName: 'Doctor',
      rank: DoctorRank.consultant,
    );
    final slot = DailySlot(
      id: 'slot-1',
      date: DateTime(2026, 6, 16),
      template: SlotTemplate(
        id: 'role-1',
        name: 'Stroke Unit Leader',
        area: 'Stroke Unit',
        kind: SlotKind.strokeUnitLeader,
        timeRange: TimeRange(start: LocalTime(8, 0), end: LocalTime(16, 0)),
        role: DutyRole.leader,
        allowedRanks: {DoctorRank.consultant},
      ),
    );
    final otherSlot = DailySlot(
      id: 'slot-2',
      date: DateTime(2026, 6, 16),
      template: SlotTemplate(
        id: 'role-2',
        name: 'Neurosonology',
        area: 'Sono',
        kind: SlotKind.neurosonology,
        timeRange: TimeRange(start: LocalTime(9, 0), end: LocalTime(10, 0)),
        role: DutyRole.neurosonography,
        allowedRanks: {DoctorRank.consultant},
      ),
    );
    final roster = RosterMonth(
      year: 2026,
      month: 6,
      phase: RosterPhase.published,
      days: [
        RosterDay(
          calendarInfo: CalendarDayInfo(
            date: DateTime(2026, 6, 16),
            isWeekend: false,
            isPublicHoliday: false,
          ),
          slots: [slot, otherSlot],
          assignments: [
            Assignment(
              doctor: doctor,
              slot: slot,
              state: AssignmentState.confirmed,
            ),
            Assignment(doctor: otherDoctor, slot: otherSlot),
          ],
        ),
      ],
    );

    final ics = IcsCalendarExportService().buildDoctorAssignmentsCalendar(
      roster: roster,
      doctor: doctor,
      generatedAt: DateTime.utc(2026, 6, 16, 12),
    );

    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('SUMMARY:NeuroDienst: Stroke Unit Leader'));
    expect(ics, contains('DTSTART:20260616T080000'));
    expect(ics, contains('DTEND:20260616T160000'));
    expect(ics, contains('LOCATION:Stroke Unit'));
    expect(ics, contains('Doctor: Slaven Pikija'));
    expect(ics, isNot(contains('Neurosonology')));
  });
}
