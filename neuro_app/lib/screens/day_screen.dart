import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import '../widgets/slot_card.dart';

class DayScreen extends StatefulWidget {
  final RosterDay day;
  final Doctor currentDoctor;

  const DayScreen({super.key, required this.day, required this.currentDoctor});

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  late RosterDay currentDay;
  bool showOnlyMine = false;

  @override
  void initState() {
    super.initState();
    currentDay = widget.day;
  }

  @override
  Widget build(BuildContext context) {
    final slotModels = SlotDisplayService().buildSlotDisplayModels(
      day: currentDay,
      doctor: widget.currentDoctor,
    );

    final visibleSlotModels = showOnlyMine
        ? slotModels
              .where(
                (slotModel) => slotModel.slotView.assignments.any(
                  (assignment) =>
                      assignment.doctor.id == widget.currentDoctor.id,
                ),
              )
              .toList()
        : slotModels;

    final myAssignmentsToday = currentDay.assignments
        .where((assignment) => assignment.doctor.id == widget.currentDoctor.id)
        .length;
    final absence = widget.currentDoctor.absenceOn(currentDay.date);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        Navigator.pop(context, currentDay);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${currentDay.date.day}.${currentDay.date.month}.${currentDay.date.year}',
              ),
              Text(
                widget.currentDoctor.fullName,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                showOnlyMine ? Icons.visibility_off : Icons.person_search,
              ),
              onPressed: () {
                setState(() {
                  showOnlyMine = !showOnlyMine;
                });
              },
            ),
          ],
        ),
        body: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'My slots today: $myAssignmentsToday',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (absence != null)
              Card(
                color: Colors.purple.shade100,
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.beach_access),
                  title: Text(absence.label),
                  subtitle: const Text('Assignments are blocked for this day.'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _LegendItem(label: 'Open', color: Colors.green),
                  _LegendItem(label: 'Mine', color: Colors.blue),
                  _LegendItem(label: 'Absent', color: Colors.purple),
                  _LegendItem(label: 'Full', color: Colors.grey),
                ],
              ),
            ),
            for (final slotModel in visibleSlotModels)
              SlotCard(
                slotModel: slotModel,
                currentDoctor: widget.currentDoctor,
                onTap: () => _toggleAssignment(slotModel.slotView),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleAssignment(SlotViewModel slotView) {
    final alreadyAssigned = slotView.assignments.any(
      (assignment) => assignment.doctor.id == widget.currentDoctor.id,
    );

    final result = alreadyAssigned
        ? AssignmentService().removeDoctorFromSlot(
            doctor: widget.currentDoctor,
            slot: slotView.slot,
            day: currentDay,
          )
        : AssignmentService().assignDoctorToSlot(
            doctor: widget.currentDoctor,
            slot: slotView.slot,
            day: currentDay,
          );

    if (!result.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.reason ?? 'Action failed')));
      return;
    }

    setState(() {
      currentDay = result.updatedDay!;
    });

    final message = alreadyAssigned
        ? 'Removed from ${slotView.slot.template.name}'
        : 'Assigned to ${slotView.slot.template.name}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 14, height: 14, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}
