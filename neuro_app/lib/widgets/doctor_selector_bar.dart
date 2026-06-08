import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

class DoctorSelectorBar extends StatelessWidget {
  final List<Doctor> doctors;
  final Doctor selectedDoctor;
  final ValueChanged<Doctor> onSelected;

  const DoctorSelectorBar({
    super.key,
    required this.doctors,
    required this.selectedDoctor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: doctors.length,
        itemBuilder: (context, index) {
          final doctor = doctors[index];

          final selected =
              doctor.id == selectedDoctor.id;

          return Padding(
            padding: const EdgeInsets.all(4),
            child: ChoiceChip(
              label: Text(
                doctor.firstName,
              ),
              selected: selected,
              onSelected: (_) {
                onSelected(doctor);
              },
            ),
          );
        },
      ),
    );
  }
}