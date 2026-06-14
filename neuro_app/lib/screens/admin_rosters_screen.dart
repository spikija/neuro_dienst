import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRostersScreen extends StatefulWidget {
  const AdminRostersScreen({super.key});

  @override
  State<AdminRostersScreen> createState() => _AdminRostersScreenState();
}

class _AdminRostersScreenState extends State<AdminRostersScreen> {
  final _yearController = TextEditingController(text: '${DateTime.now().year}');
  final _monthController = TextEditingController(
    text: '${DateTime.now().month}',
  );
  bool _replaceExisting = false;
  bool _isGenerating = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rosters')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Generate month',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Creates roster days and concrete slots from the active role templates.',
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _yearController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Year',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _monthController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Month',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Replace existing roster'),
                  subtitle: const Text(
                    'Deletes existing days, slots, and assignments for this month.',
                  ),
                  value: _replaceExisting,
                  onChanged: (value) {
                    setState(() {
                      _replaceExisting = value;
                    });
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_statusMessage!),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _generateRoster,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.calendar_month),
                  label: const Text('Generate roster'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _generateRoster() async {
    final year = int.tryParse(_yearController.text);
    final month = int.tryParse(_monthController.text);

    if (year == null || year < 2000 || year > 2100) {
      setState(() {
        _errorMessage = 'Use a valid year.';
        _statusMessage = null;
      });
      return;
    }

    if (month == null || month < 1 || month > 12) {
      setState(() {
        _errorMessage = 'Use a month from 1 to 12.';
        _statusMessage = null;
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final result = await _RosterGenerator().generate(
        year: year,
        month: month,
        replaceExisting: _replaceExisting,
      );

      setState(() {
        _statusMessage =
            'Generated ${result.dayCount} days and ${result.slotCount} slots.';
      });
    } on _RosterExistsException {
      setState(() {
        _errorMessage =
            'Roster already exists. Enable replace existing to regenerate it.';
      });
    } on PostgrestException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Could not generate roster.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }
}

class _RosterGenerator {
  final SupabaseClient _client;

  _RosterGenerator({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  Future<_GenerationResult> generate({
    required int year,
    required int month,
    required bool replaceExisting,
  }) async {
    final existing = await _client
        .from('rosters')
        .select('id')
        .eq('year', year)
        .eq('month', month)
        .maybeSingle();

    if (existing != null && !replaceExisting) {
      throw _RosterExistsException();
    }

    if (existing != null && replaceExisting) {
      await _client.from('rosters').delete().eq('id', existing['id'] as String);
    }

    final roster = await _client
        .from('rosters')
        .insert({
          'year': year,
          'month': month,
          'phase': 'draft',
          'created_by': _client.auth.currentUser?.id,
        })
        .select('id')
        .single();
    final rosterId = roster['id'] as String;

    final roleRows = await _client
        .from('roles')
        .select('id, code, name, max_doctors, is_active')
        .eq('is_active', true);
    final rolesById = {
      for (final row in roleRows)
        row['id'] as String: _RoleRecord.fromJson(row),
    };

    final templateRows = await _client
        .from('role_templates')
        .select('id, role_id, weekday_rule, monthly_day, start_time, end_time');
    final templates = templateRows
        .map((row) => _TemplateRecord.fromJson(row))
        .where((template) => rolesById.containsKey(template.roleId))
        .toList();

    final days = _monthDates(year, month);
    final dayRows = [
      for (final date in days)
        {
          'roster_id': rosterId,
          'date': _dateIso(date),
          'is_weekend': _isWeekend(date),
          'is_public_holiday': false,
        },
    ];

    final insertedDays = await _client
        .from('roster_days')
        .insert(dayRows)
        .select('id, date');
    final dayIdByDate = {
      for (final row in insertedDays)
        row['date'] as String: row['id'] as String,
    };

    final slotRows = <Map<String, dynamic>>[];

    for (final date in days) {
      final dateKey = _dateIso(date);
      final rosterDayId = dayIdByDate[dateKey];

      if (rosterDayId == null) {
        continue;
      }

      for (final template in templates) {
        if (!template.appliesTo(date)) {
          continue;
        }

        final role = rolesById[template.roleId]!;

        slotRows.add({
          'roster_day_id': rosterDayId,
          'role_id': template.roleId,
          'starts_at': '${dateKey}T${template.startTime}:00Z',
          'ends_at': '${dateKey}T${template.endTime}:00Z',
          'max_doctors': role.maxDoctors,
        });
      }
    }

    if (slotRows.isNotEmpty) {
      await _client.from('roster_slots').insert(slotRows);
    }

    return _GenerationResult(
      dayCount: dayRows.length,
      slotCount: slotRows.length,
    );
  }
}

class _RoleRecord {
  final int maxDoctors;

  const _RoleRecord({required this.maxDoctors});

  factory _RoleRecord.fromJson(Map<String, dynamic> json) {
    return _RoleRecord(maxDoctors: json['max_doctors'] as int? ?? 1);
  }
}

class _TemplateRecord {
  final String roleId;
  final String weekdayRule;
  final int? monthlyDay;
  final String startTime;
  final String endTime;

  const _TemplateRecord({
    required this.roleId,
    required this.weekdayRule,
    required this.monthlyDay,
    required this.startTime,
    required this.endTime,
  });

  factory _TemplateRecord.fromJson(Map<String, dynamic> json) {
    return _TemplateRecord(
      roleId: json['role_id'] as String,
      weekdayRule: json['weekday_rule'] as String? ?? 'every_weekday',
      monthlyDay: json['monthly_day'] as int?,
      startTime: _formatTime(json['start_time'] as String? ?? '08:00'),
      endTime: _formatTime(json['end_time'] as String? ?? '16:00'),
    );
  }

  bool appliesTo(DateTime date) {
    switch (weekdayRule) {
      case 'every_weekday':
        return date.weekday >= DateTime.monday &&
            date.weekday <= DateTime.friday;
      case 'monday_only':
        return date.weekday == DateTime.monday;
      case 'tuesday_only':
        return date.weekday == DateTime.tuesday;
      case 'wednesday_only':
        return date.weekday == DateTime.wednesday;
      case 'thursday_only':
        return date.weekday == DateTime.thursday;
      case 'friday_only':
        return date.weekday == DateTime.friday;
      case 'monthly_day':
        return date.day == monthlyDay;
    }

    return false;
  }
}

class _GenerationResult {
  final int dayCount;
  final int slotCount;

  const _GenerationResult({required this.dayCount, required this.slotCount});
}

class _RosterExistsException implements Exception {}

List<DateTime> _monthDates(int year, int month) {
  final dates = <DateTime>[];
  final lastDay = DateTime(year, month + 1, 0).day;

  for (var day = 1; day <= lastDay; day++) {
    dates.add(DateTime(year, month, day));
  }

  return dates;
}

bool _isWeekend(DateTime date) {
  return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
}

String _dateIso(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatTime(String value) {
  if (value.length >= 5) {
    return value.substring(0, 5);
  }

  return value;
}
