import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

class MonthDayCard extends StatelessWidget {
  final RosterDay day;
  final MonthDayViewModel dayView;
  final Doctor currentDoctor;
  final VoidCallback? onTap;

  const MonthDayCard({
    super.key,
    required this.day,
    required this.dayView,
    required this.currentDoctor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled =
        day.calendarInfo.isPublicHoliday || day.calendarInfo.isWeekend;

    final myAssignmentsToday = RosterStatisticsService()
      .countAssignmentsForDoctorInDay(
        day: day,
        doctor: currentDoctor,
      );

    final hasMyAssignment = myAssignmentsToday > 0;

    return InkWell(
      onTap: isDisabled ? null : onTap,
      child: Card(
        color: day.calendarInfo.isPublicHoliday
            ? Colors.red.shade100
            : day.calendarInfo.isWeekend
                ? Colors.grey.shade300
                : hasMyAssignment
                    ? Colors.blue.shade100
                    : null,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.date.day}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDisabled ? Colors.grey.shade700 : null,
                ),
              ),
              if (day.calendarInfo.isPublicHoliday)
                const Text('Holiday', style: TextStyle(fontSize: 10))
              else if (day.calendarInfo.isWeekend)
                const Text('Weekend', style: TextStyle(fontSize: 10))
              else ...[
                Text('Open: ${dayView.openSlots}',
                    style: const TextStyle(fontSize: 10)),
                Text('Filled: ${dayView.filledSlots}',
                    style: const TextStyle(fontSize: 10)),
                if (myAssignmentsToday > 0)
                  Text(
                    'Mine: $myAssignmentsToday',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}