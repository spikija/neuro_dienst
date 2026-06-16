import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ics_calendar_export_service.dart';

class CalendarExportScreen extends StatefulWidget {
  final RosterMonth roster;
  final Doctor doctor;

  const CalendarExportScreen({
    super.key,
    required this.roster,
    required this.doctor,
  });

  @override
  State<CalendarExportScreen> createState() => _CalendarExportScreenState();
}

class _CalendarExportScreenState extends State<CalendarExportScreen> {
  late final IcsCalendarExportService _exportService;
  late final String _ics;
  late final int _assignmentCount;
  String? _savedPath;
  bool _isSaving = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _exportService = IcsCalendarExportService();
    _ics = _exportService.buildDoctorAssignmentsCalendar(
      roster: widget.roster,
      doctor: widget.doctor,
    );
    _assignmentCount = _exportService.countAssignments(
      roster: widget.roster,
      doctor: widget.doctor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar export')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.doctor.fullName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.roster.month}/${widget.roster.year} · '
                    '$_assignmentCount assigned duties',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _isSharing ? null : _shareIcs,
                        icon: _isSharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.ios_share),
                        label: const Text('Share .ics file'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _copyIcs,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy .ics'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _saveIcs,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt),
                        label: const Text('Save .ics file'),
                      ),
                    ],
                  ),
                  if (_savedPath != null) ...[
                    const SizedBox(height: 12),
                    SelectableText('Saved to: $_savedPath'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Preview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _ics,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyIcs() async {
    await Clipboard.setData(ClipboardData(text: _ics));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Calendar copied.')));
  }

  Future<void> _shareIcs() async {
    setState(() {
      _isSharing = true;
    });

    try {
      final directory = await getTemporaryDirectory();
      final file = await _writeIcsFile(directory);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: 'text/calendar', name: _fileName()),
          ],
          subject:
              'NeuroDienst calendar ${widget.roster.month}/${widget.roster.year}',
          text: 'NeuroDienst duties for ${widget.doctor.fullName}',
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share calendar file.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  Future<void> _saveIcs() async {
    setState(() {
      _isSaving = true;
      _savedPath = null;
    });

    try {
      final directory = await _exportDirectory();
      await directory.create(recursive: true);
      final file = await _writeIcsFile(directory);

      if (!mounted) {
        return;
      }

      setState(() {
        _savedPath = file.path;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Calendar file saved.')));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save calendar file.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<File> _writeIcsFile(Directory directory) {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${_fileName()}',
    );
    return file.writeAsString(_ics);
  }

  Future<Directory> _exportDirectory() async {
    final userProfile = Platform.environment['USERPROFILE'];

    if (userProfile != null && userProfile.isNotEmpty) {
      final downloads = Directory(
        '$userProfile${Platform.pathSeparator}Downloads',
      );

      if (await downloads.exists()) {
        return downloads;
      }
    }

    return Directory.systemTemp;
  }

  String _fileName() {
    final name = widget.doctor.fullName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safeName = name.isEmpty ? 'doctor' : name;
    final month = widget.roster.month.toString().padLeft(2, '0');

    return 'neurodienst-$safeName-${widget.roster.year}-$month.ics';
  }
}
