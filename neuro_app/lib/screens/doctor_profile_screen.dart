import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

class DoctorProfileScreen extends StatelessWidget {
  static const _supportEmail = 'spikija@gmail.com';

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
            const Spacer(),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              l10n.t('accountAndPrivacy'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.t('accountDeletionExplanation')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _requestAccountDeletion(context),
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.t('requestAccountDeletion')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _requestAccountDeletion(BuildContext context) async {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': 'NeuroDienst account deletion request',
        'body':
            'Please delete my NeuroDienst account and associated data.\n\n'
            'Account email: $userEmail\n'
            'Doctor ID: ${doctor.id}',
      },
    );

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${AppLocalizations.of(context).t('couldNotOpenEmail')} '
            '$_supportEmail',
          ),
        ),
      );
    }
  }
}
