import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/device_calendar_import_service.dart';

class VacationImportScreen extends StatefulWidget {
  final int year;
  final int month;
  final DeviceCalendarImportService? importService;

  const VacationImportScreen({
    super.key,
    required this.year,
    required this.month,
    this.importService,
  });

  @override
  State<VacationImportScreen> createState() => _VacationImportScreenState();
}

class _VacationImportScreenState extends State<VacationImportScreen> {
  late final Future<CalendarVacationScan> _future;
  final Set<int> _selectedIndexes = {};
  String? _selectedCalendarId;

  DateTime get _rangeStart => DateTime(widget.year, widget.month);

  DateTime get _rangeEnd => DateTime(widget.year, widget.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _future = (widget.importService ?? DeviceCalendarImportService())
        .loadVacationScan(start: _rangeStart, end: _rangeEnd)
        .then((scan) {
          _selectedIndexes.addAll(
            List.generate(scan.candidates.length, (index) => index),
          );
          return scan;
        });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('importVacation'))),
      body: FutureBuilder<CalendarVacationScan>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ImportMessage(
              icon: Icons.error_outline,
              message: snapshot.error.toString(),
            );
          }

          final scan = snapshot.data!;
          final candidates = scan.candidates
              .where(
                (candidate) =>
                    _selectedCalendarId == null ||
                    candidate.calendarId == _selectedCalendarId,
              )
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCalendarId ?? '',
                      isExpanded: true,
                      menuMaxHeight: 320,
                      decoration: InputDecoration(
                        labelText: l10n.t('vacationSourceCalendar'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(l10n.t('allPhoneCalendars')),
                        ),
                        for (final source in scan.sources)
                          DropdownMenuItem(
                            value: source.id,
                            child: Text(
                              source.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCalendarId = value == '' ? null : value;
                          final count = scan.candidates
                              .where(
                                (candidate) =>
                                    _selectedCalendarId == null ||
                                    candidate.calendarId == _selectedCalendarId,
                              )
                              .length;
                          _selectedIndexes
                            ..clear()
                            ..addAll(List.generate(count, (index) => index));
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.t('vacationSourceHint')),
                  ],
                ),
              ),
              Expanded(
                child: candidates.isEmpty
                    ? _ImportMessage(
                        icon: Icons.event_busy,
                        message: l10n.t('noVacationCalendarEventsFound'),
                      )
                    : ListView.builder(
                        itemCount: candidates.length,
                        itemBuilder: (context, index) {
                          final candidate = candidates[index];
                          final selected = _selectedIndexes.contains(index);

                          return CheckboxListTile(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedIndexes.add(index);
                                } else {
                                  _selectedIndexes.remove(index);
                                }
                              });
                            },
                            title: Text(candidate.title),
                            subtitle: Text(
                              '${_formatDate(candidate.start)} - '
                              '${_formatDate(candidate.end)}\n'
                              '${l10n.t('vacationSourceCalendar')}: ${candidate.sourceLabel}'
                              '${candidate.allDay ? ' - ${l10n.t('allDay')}' : ''}',
                            ),
                            secondary: const Icon(Icons.beach_access),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(l10n.t('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _selectedIndexes.isEmpty
                              ? null
                              : () => _importSelected(candidates),
                          icon: const Icon(Icons.download),
                          label: Text(l10n.t('import')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _importSelected(List<CalendarVacationCandidate> candidates) {
    final selectedDates = <DateTime>{};

    for (final index in _selectedIndexes) {
      selectedDates.addAll(
        candidates[index].datesWithin(_rangeStart, _rangeEnd),
      );
    }

    final dates = selectedDates.toList()..sort((a, b) => a.compareTo(b));
    Navigator.pop(context, dates);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }
}

class _ImportMessage extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ImportMessage({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
