import 'package:flutter/material.dart';

import '../services/device_calendar_import_service.dart';

class VacationImportScreen extends StatefulWidget {
  final int year;
  final int month;

  const VacationImportScreen({
    super.key,
    required this.year,
    required this.month,
  });

  @override
  State<VacationImportScreen> createState() => _VacationImportScreenState();
}

class _VacationImportScreenState extends State<VacationImportScreen> {
  late final Future<List<CalendarVacationCandidate>> _future;
  final Set<int> _selectedIndexes = {};

  DateTime get _rangeStart => DateTime(widget.year, widget.month);

  DateTime get _rangeEnd => DateTime(widget.year, widget.month + 1, 0);

  @override
  void initState() {
    super.initState();
    _future = DeviceCalendarImportService()
        .loadVacationCandidates(start: _rangeStart, end: _rangeEnd)
        .then((candidates) {
          _selectedIndexes.addAll(
            List.generate(candidates.length, (index) => index),
          );
          return candidates;
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import vacation')),
      body: FutureBuilder<List<CalendarVacationCandidate>>(
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

          final candidates = snapshot.data ?? const [];

          if (candidates.isEmpty) {
            return const _ImportMessage(
              icon: Icons.event_busy,
              message: 'No vacation-like calendar events found for this month.',
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
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
                        '${candidate.calendarName}'
                        '${candidate.allDay ? ' · all day' : ''}',
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
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _selectedIndexes.isEmpty
                              ? null
                              : () => _importSelected(candidates),
                          icon: const Icon(Icons.download),
                          label: const Text('Import'),
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
