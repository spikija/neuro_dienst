import 'package:neuro_core/neuro_core.dart';

class DemoRoster {
  static Doctor createCurrentDoctor() {
    return Doctor(
      id: 'pikija',
      firstName: 'Slaven',
      lastName: 'Pikija',
      rank: DoctorRank.consultant,
      capabilities: {Capability.canLead, Capability.canDoNeurosonography},
      availabilities: [
        AvailabilityPeriod(
          start: DateTime(2026, 6, 8),
          end: DateTime(2026, 6, 12),
          type: AvailabilityType.vacation,
        ),
      ],
    );
  }

  static Doctor createOtherDoctor() {
    return Doctor(
      id: 'mueller',
      firstName: 'Max',
      lastName: 'Müller',
      rank: DoctorRank.consultant,
      capabilities: {Capability.canLead, Capability.canDoNeurosonography},
      availabilities: [
        AvailabilityPeriod(
          start: DateTime(2026, 6, 18),
          end: DateTime(2026, 6, 19),
          type: AvailabilityType.conference,
        ),
      ],
    );
  }

  static Doctor createResidentDoctor() {
    return Doctor(
      id: 'resident1',
      firstName: 'Anna',
      lastName: 'Resident',
      rank: DoctorRank.resident,
    );
  }

  static List<Doctor> createDoctors() {
    return [createCurrentDoctor(), createOtherDoctor(), createResidentDoctor()];
  }

  static RosterMonth createJune2026() {
    final roster =
        RosterMonthFactory(
          holidayProvider: ManualHolidayProvider(
            holidays: {'2026-6-4': 'Fronleichnam'},
          ),
          slotFactory: SlotFactory(),
        ).generateMonth(
          year: 2026,
          month: 6,
          departmentTemplate: NeurologyDepartmentFactory.create(),
        );

    final otherDoctor = createOtherDoctor();

    final updatedDays = roster.days.map((day) {
      if (day.date.day != 1) {
        return day;
      }

      final ambulanceSlot = day.slots.firstWhere(
        (slot) => slot.template.kind == SlotKind.ambulance,
      );

      final neurosonologySlot = day.slots.firstWhere(
        (slot) => slot.template.kind == SlotKind.neurosonology,
      );

      return RosterDay(
        calendarInfo: day.calendarInfo,
        slots: day.slots,
        availabilities: day.availabilities,
        assignments: [
          ...day.assignments,
          Assignment(doctor: otherDoctor, slot: ambulanceSlot),
          Assignment(doctor: otherDoctor, slot: neurosonologySlot),
        ],
      );
    }).toList();

    return RosterMonth(
      year: roster.year,
      month: roster.month,
      phase: roster.phase,
      days: updatedDays,
    );
  }
}
