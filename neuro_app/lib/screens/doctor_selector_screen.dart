import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../l10n/app_localizations.dart';

class DoctorSelectorScreen extends StatelessWidget {
  final List<Doctor> doctors;

  const DoctorSelectorScreen({super.key, required this.doctors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('selectDoctor'))),
      body: ListView.builder(
        itemCount: doctors.length,
        itemBuilder: (context, index) {
          final doctor = doctors[index];

          return ListTile(
            title: Text(doctor.fullName),
            subtitle: Text(doctor.rank.name),
            onTap: () {
              Navigator.pop(context, doctor);
            },
          );
        },
      ),
    );
  }
}
