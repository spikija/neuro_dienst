import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../extensions/time_formatting.dart';


class SlotCard extends StatelessWidget {
  final SlotDisplayModel slotModel;
  final VoidCallback? onTap;
  final Doctor currentDoctor;
  
  const SlotCard({
    super.key,
    required this.slotModel,
    required this.onTap,
    required this.currentDoctor,
  });

  
  @override
  Widget build(BuildContext context) {
    
    final slotView = slotModel.slotView;
    final hasAssignments = slotView.assignedDoctorNames.isNotEmpty;
    final eligibility = slotModel.eligibility;
    final isNotEligible = !eligibility.eligible;
    final slot = slotView.slot;
    
    final status = hasAssignments
    ? slotView.assignedDoctorNames.join(', ')
    : eligibility.eligible
        ? 'OPEN'
        : eligibility.reason ?? 'Not eligible';

    final participantCount = slotView.assignments.length;
    final maxDoctors = slot.template.maxDoctors;

    final capacityText = maxDoctors > 1
    ? '\nParticipants: $participantCount/$maxDoctors'
    : '';
    
    final isAssignedToCurrentDoctor = slotView.assignments.any(
      (assignment) => assignment.doctor.id == currentDoctor.id,
    );

    final isFull = !slotView.isOpen;

    final isAssignedToOtherDoctorOnly =
        slotView.assignments.isNotEmpty && !isAssignedToCurrentDoctor;

    final shouldLock =
        isAssignedToOtherDoctorOnly && isFull;

    final Color? cardColor;

    final canTap = isAssignedToCurrentDoctor || (!shouldLock && !isNotEligible);

    

    if (isAssignedToCurrentDoctor) {
      cardColor = Colors.blue.shade100;
    } else if (shouldLock) {
      cardColor = Colors.grey.shade300;
    } else if (isNotEligible) {
      cardColor = Colors.orange.shade100;
    } else {
      cardColor = Colors.green.shade100;
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.all(8),
      child: ListTile(
        onTap: canTap ? onTap : null,
        title: Text(slot.template.name),
        subtitle: Text(
          '${slot.template.timeRange.display}'
          '\n$status'
          '$capacityText',
        ),
        trailing: isAssignedToCurrentDoctor
            ? const Icon(Icons.check_circle)
            : shouldLock
                ? const Icon(Icons.lock)
                : isNotEligible
                    ? const Icon(Icons.warning_amber)
                    : const Icon(Icons.add_circle_outline),      ),
    );
  }

}
