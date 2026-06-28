import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';

import '../l10n/app_localizations.dart';

class DoctorProfileScreen extends StatelessWidget {
  final Doctor doctor;

  const DoctorProfileScreen({super.key, required this.doctor});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('doctorProfile'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doctor.fullName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text('${l10n.t('rank')}: ${doctor.rank.name}'),
            const SizedBox(height: 8),
            Text('ID: ${doctor.id}'),
          ],
        ),
      ),
    );
  }
}
