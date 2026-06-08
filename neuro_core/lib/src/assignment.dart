class Assignment{
  final Doctor doctor;
  final DailySlot slot;

  Assignment({
    required this.doctor,
    required this.slot,
  });
}

class RosterDay{
  final DateTime date;
  final List<DailySlot> slots;

  RosterDay({
    required this.date,
    this.slots =const[],
  })
}

class Conflict{
  final String message;

  Conflict(this.message);

  @override

  String toString() => message;
}

class RosterValidator {
  List<Conflict> validateDay(RosterDay day) {
    final conflicts = <Conflict>[];

    for (var i = 0; i < day.slots.length; i++) {
      for (var j = i + 1; j < day.slots.length; j++) {
        final slotA = day.slots[i];
        final slotB = day.slots[j];

        for (final doctorA in slotA.assignedDoctors) {
          for (final doctorB in slotB.assignedDoctors) {
            if (doctorA.id == doctorB.id &&
                slotA.template.timeRange.overlaps(
                  slotB.template.timeRange,
                )) {
              conflicts.add(
                Conflict(
                  '${doctorA.fullName} assigned twice '
                  '(${slotA.template.name} / ${slotB.template.name})',
                ),
              );
            }
          }
        }
      }
    }

    return conflicts;
  }
}