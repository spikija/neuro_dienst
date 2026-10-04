import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/personal_roster_report.dart';
import '../services/supabase_bootstrap.dart';

class PersonalRosterReportScreen extends StatefulWidget {
  final RosterMonth roster;
  final List<Doctor> doctors;
  final Doctor? demoDoctor;

  const PersonalRosterReportScreen({
    super.key,
    required this.roster,
    required this.doctors,
    this.demoDoctor,
  });

  @override
  State<PersonalRosterReportScreen> createState() =>
      _PersonalRosterReportScreenState();
}

class _PersonalRosterReportScreenState
    extends State<PersonalRosterReportScreen> {
  late Future<Doctor?> _doctorFuture;

  @override
  void initState() {
    super.initState();
    _doctorFuture = _loadSignedInDoctor();
  }

  Future<Doctor?> _loadSignedInDoctor() async {
    if (!SupabaseConfig.isConfigured) return widget.demoDoctor;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await client
        .from('doctors')
        .select('id')
        .eq('auth_user_id', userId)
        .eq('is_active', true)
        .maybeSingle();
    if (client.auth.currentUser?.id != userId) return null;
    // Never fall back to the selected doctor: administrators can select others.
    for (final doctor in widget.doctors) {
      if (doctor.id == row?['id']) return doctor;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('myDuties'))),
      body: FutureBuilder<Doctor?>(
        future: _doctorFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.t(
                        snapshot.hasError
                            ? 'personalReportError'
                            : 'personalReportNoDoctor',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _doctorFuture = _loadSignedInDoctor();
                      }),
                      child: Text(l10n.t('retry')),
                    ),
                  ],
                ),
              ),
            );
          }
          return PdfPreview(
            initialPageFormat: PdfPageFormat.a4,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            pdfFileName:
                'NeuroDienst-${widget.roster.year}-${widget.roster.month}.pdf',
            onError: (_, _) =>
                Center(child: Text(l10n.t('personalReportPdfError'))),
            build: (format) => buildPersonalRosterPdf(
              roster: widget.roster,
              doctor: snapshot.data!,
              l10n: l10n,
              format: format,
            ),
          );
        },
      ),
    );
  }
}
