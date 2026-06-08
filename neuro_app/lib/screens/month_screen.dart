import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_app/extensions/time_formatting.dart';
import '../widgets/month_day_card.dart';
import 'day_screen.dart';
import 'doctor_profile_screen.dart';
import 'doctor_selector_screen.dart';
import '../widgets/doctor_selector_bar.dart';


class MonthScreen extends StatefulWidget {
  final RosterMonth roster;
  final Doctor currentDoctor;
  final ValueChanged<Doctor> onDoctorChanged;
  final List<Doctor> doctors;

  
  const MonthScreen({
    super.key,
    required this.roster,
    required this.currentDoctor,
    required this.doctors,
    required this.onDoctorChanged,
  });

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {

  late RosterMonth currentRoster;

  int _myAssignmentsThisMonthCount() {
    return currentRoster.days
        .expand((day) => day.assignments)
        .where(
          (assignment) =>
              assignment.doctor.id == widget.currentDoctor.id,
        )
        .length;
  }

  @override
  void initState() {
    super.initState();
    currentRoster = widget.roster;
  }

  @override
  Widget build(BuildContext context) {
    final monthView = MonthViewService().getMonthView(currentRoster);

    final myAssignmentThisMonth =
      RosterStatisticsService()
        .countAssignmentsForDoctorInMonth(
          roster: currentRoster,
          doctor: widget.currentDoctor,
        );

    final myAssignmentsThisMonth =
      _myAssignmentsThisMonthCount();

    final statistics = RosterStatisticsService();

    final openSlots = statistics.countOpenSlots(
      roster: currentRoster,
    );

    final assignedSlots = statistics.countAssignedSlots(
      roster: currentRoster,
    );
  
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${currentRoster.month}/${currentRoster.year}'),
            Text(
              widget.currentDoctor.fullName,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.switch_account),
              onPressed: () async {
                final selectedDoctor =
                    await Navigator.push<Doctor>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DoctorSelectorScreen(
                      doctors: widget.doctors,
                    ),
                  ),
                );

                if (selectedDoctor != null) {
                  widget.onDoctorChanged(selectedDoctor);
                }
              },
            ),
          IconButton(
              icon: const Icon(Icons.list),
              onPressed: _showMyAssignmentsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DoctorProfileScreen(
                    doctor: widget.currentDoctor,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        
        children: [
          DoctorSelectorBar(
                doctors: widget.doctors,
                selectedDoctor: widget.currentDoctor,
                onSelected: widget.onDoctorChanged,
              ),
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      const Text('Open'),
                      Text(
                        '$openSlots',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Assigned'),
                      Text(
                        '$assignedSlots',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Mine'),
                      Text(
                        '$myAssignmentsThisMonth',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),    
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'My slots this month: $myAssignmentThisMonth',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GridView.builder(
                itemCount: currentRoster.days.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
              itemBuilder: (context, index) {
                final day = currentRoster.days[index];
                final dayView = monthView[index];
                final hasMyAssignment = day.assignments.any(
                  (assignment) =>
                    assignment.doctor.id == 
                    widget.currentDoctor.id,
                );
                final myAssignmentsToday = day.assignments
                .where(
                  (assignment) =>
                      assignment.doctor.id ==
                      widget.currentDoctor.id,
                )
                .length;
                final isDisabled =
                    day.calendarInfo.isPublicHoliday || day.calendarInfo.isWeekend;

                  return MonthDayCard(
                    day: day,
                    dayView: dayView,
                    currentDoctor: widget.currentDoctor,
                    onTap: () async {
                      final updatedDay = await Navigator.push<RosterDay>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DayScreen(
                            day: day,
                            currentDoctor: widget.currentDoctor,
                          ),
                        ),
                      );

                      if (updatedDay != null) {
                        _replaceDay(updatedDay);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
 
  }
     void _replaceDay(RosterDay updatedDay) {
      final updatedDays = currentRoster.days.map((day) {
        final sameDate =
            day.date.year == updatedDay.date.year &&
            day.date.month == updatedDay.date.month &&
            day.date.day == updatedDay.date.day;

        return sameDate ? updatedDay : day;
      }).toList();

      setState(() {
        currentRoster = RosterMonth(
          year: currentRoster.year,
          month: currentRoster.month,
          phase: currentRoster.phase,
          days: updatedDays,
        );
      });
    }

    // method
    void _showMyAssignmentsDialog() {
        final myAssignments = RosterStatisticsService().getAssignmentsForDoctorInMonth(
          roster:currentRoster,
          doctor: widget.currentDoctor,
        );

        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('My slots this month'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (myAssignments.isEmpty)
                  const Text('No slots assigned yet.'),
                for (final assignment in myAssignments)
                  Text(
                    '${assignment.slot.date.day}.${assignment.slot.date.month}. '
                    '${assignment.slot.template.name} '
                    '(${assignment.slot.template.timeRange.display})',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
}