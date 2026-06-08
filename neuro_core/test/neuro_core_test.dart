import 'package:test/test.dart';
import 'package:neuro_core/neuro_core.dart';


void main() {
  
group('InMemoryDoctorRepository', () {
  test('returns all doctors', () {
    final repo = InMemoryDoctorRepository(
      doctors: [
        Doctor(
          id: 'd1',
          firstName: 'Slaven',
          lastName: 'Pikija',
          rank: DoctorRank.consultant,
        ),
        Doctor(
          id: 'd2',
          firstName: 'Anna',
          lastName: 'Resident',
          rank: DoctorRank.resident,
        ),
      ],
    );

    final doctors = repo.getAllDoctors();

    expect(doctors.length, 2);
  });

  test('finds doctor by id', () {
    final repo = InMemoryDoctorRepository(
      doctors: [
        Doctor(
          id: 'd1',
          firstName: 'Slaven',
          lastName: 'Pikija',
          rank: DoctorRank.consultant,
        ),
      ],
    );

    final doctor = repo.getDoctorById('d1');

    expect(doctor, isNotNull);
    expect(doctor!.fullName, 'Slaven Pikija');
  });

  test('returns null for unknown doctor id', () {
    final repo = InMemoryDoctorRepository(
      doctors: [],
    );

    final doctor = repo.getDoctorById('unknown');

    expect(doctor, null);
  });
});


group('DayViewService', () {
  test('shows slot as open when no assignment exists', () {
    final slot = DailySlot(
      id: 'slot1',
      date: DateTime(2026, 6, 1),
      template: SlotTemplate(
        id: 'ambulance',
        name: 'Ambulance',
        area: 'Outpatient Clinic',
        kind: SlotKind.ambulance,
        timeRange: TimeRange(
          start: LocalTime(9, 0),
          end: LocalTime(13, 0),
        ),
        role: DutyRole.outpatientClinic,
        allowedRanks: {
          DoctorRank.consultant,
        },
      ),
    );

    final day = RosterDay(
      calendarInfo: CalendarDayInfo(
        date: DateTime(2026, 6, 1),
        isWeekend: false,
        isPublicHoliday: false,
      ),
      slots: [slot],
      assignments: [],
    );

    final views =
        DayViewService().getSlotViews(day);

    expect(views.length, 1);
    expect(views.first.isOpen, true);
  });

  test('shows slot as filled when assignment exists', () {
    final doctor = Doctor(
      id: 'd1',
      firstName: 'Slaven',
      lastName: 'Pikija',
      rank: DoctorRank.consultant,
    );

    final slot = DailySlot(
      id: 'slot1',
      date: DateTime(2026, 6, 1),
      template: SlotTemplate(
        id: 'ambulance',
        name: 'Ambulance',
        area: 'Outpatient Clinic',
        kind: SlotKind.ambulance,
        timeRange: TimeRange(
          start: LocalTime(9, 0),
          end: LocalTime(13, 0),
        ),
        role: DutyRole.outpatientClinic,
        allowedRanks: {
          DoctorRank.consultant,
        },
      ),
    );

    final day = RosterDay(
      calendarInfo: CalendarDayInfo(
        date: DateTime(2026, 6, 1),
        isWeekend: false,
        isPublicHoliday: false,
      ),
      slots: [slot],
      assignments: [
        Assignment(
          doctor: doctor,
          slot: slot,
        ),
      ],
    );

    final views =
        DayViewService().getSlotViews(day);

    expect(views.first.isOpen, false);
  });
});

test('shows assigned doctor names', () {
  final doctor = Doctor(
    id: 'd1',
    firstName: 'Slaven',
    lastName: 'Pikija',
    rank: DoctorRank.consultant,
  );

  final slot = DailySlot(
    id: 'slot1',
    date: DateTime(2026, 6, 1),
    template: SlotTemplate(
      id: 'ambulance',
      name: 'Ambulance',
      area: 'Outpatient Clinic',
      kind: SlotKind.ambulance,
      timeRange: TimeRange(
        start: LocalTime(9, 0),
        end: LocalTime(13, 0),
      ),
      role: DutyRole.outpatientClinic,
      allowedRanks: {
        DoctorRank.consultant,
      },
    ),
  );

  final day = RosterDay(
    calendarInfo: CalendarDayInfo(
      date: DateTime(2026, 6, 1),
      isWeekend: false,
      isPublicHoliday: false,
    ),
    slots: [slot],
    assignments: [
      Assignment(
        doctor: doctor,
        slot: slot,
      ),
    ],
  );

  final views = DayViewService().getSlotViews(day);

  expect(
    views.first.assignedDoctorNames,
    ['Slaven Pikija'],
  );
});

group('MonthViewService', () {
  test('counts open and filled slots', () {
    final doctor = Doctor(
      id: 'd1',
      firstName: 'Slaven',
      lastName: 'Pikija',
      rank: DoctorRank.consultant,
    );

    final slot1 = DailySlot(
      id: 'slot1',
      date: DateTime(2026, 6, 1),
      template: SlotTemplate(
        id: 'ambulance',
        name: 'Ambulance',
        area: 'Ambulance',
        kind: SlotKind.ambulance,
        timeRange: TimeRange(
          start: LocalTime(9, 0),
          end: LocalTime(13, 0),
        ),
        role: DutyRole.outpatientClinic,
        allowedRanks: {
          DoctorRank.consultant,
        },
      ),
    );

    final slot2 = DailySlot(
      id: 'slot2',
      date: DateTime(2026, 6, 1),
      template: SlotTemplate(
        id: 'neurosono',
        name: 'Neurosonology',
        area: 'Neurosonology',
        kind: SlotKind.neurosonology,
        timeRange: TimeRange(
          start: LocalTime(8, 0),
          end: LocalTime(15, 30),
        ),
        role: DutyRole.neurosonography,
        allowedRanks: {
          DoctorRank.consultant,
        },
      ),
    );

    final day = RosterDay(
      calendarInfo: CalendarDayInfo(
        date: DateTime(2026, 6, 1),
        isWeekend: false,
        isPublicHoliday: false,
      ),
      slots: [
        slot1,
        slot2,
      ],
      assignments: [
        Assignment(
          doctor: doctor,
          slot: slot1,
        ),
      ],
    );

    final roster = RosterMonth(
      year: 2026,
      month: 6,
      phase: RosterPhase.openForSelection,
      days: [day],
    );

    final result =
        MonthViewService().getMonthView(
      roster,
    );

    expect(
      result.first.openSlots,
      1,
    );

    expect(
      result.first.filledSlots,
      1,
    );
  });
});


}