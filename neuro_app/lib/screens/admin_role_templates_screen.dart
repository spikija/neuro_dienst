import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRoleTemplatesScreen extends StatefulWidget {
  const AdminRoleTemplatesScreen({super.key});

  @override
  State<AdminRoleTemplatesScreen> createState() =>
      _AdminRoleTemplatesScreenState();
}

class _AdminRoleTemplatesScreenState extends State<AdminRoleTemplatesScreen> {
  late Future<_TemplateScreenData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Role templates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTemplateForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add template'),
      ),
      body: FutureBuilder<_TemplateScreenData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reloadData,
            );
          }

          final data = snapshot.data!;

          if (data.templates.isEmpty) {
            return const Center(child: Text('No role templates yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: data.templates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final template = data.templates[index];
              final role = data.roleById[template.roleId];

              return ListTile(
                leading: CircleAvatar(child: Text(role?.code ?? '?')),
                title: Text(role?.name ?? 'Unknown role'),
                subtitle: Text(
                  '${_templateRuleLabel(template)} | '
                  '${template.startTime}-${template.endTime}',
                ),
                trailing: IconButton(
                  tooltip: 'Delete template',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteTemplate(template),
                ),
                onTap: () => _openTemplateForm(template: template),
              );
            },
          );
        },
      ),
    );
  }

  Future<_TemplateScreenData> _loadData() async {
    final rolesRows = await Supabase.instance.client
        .from('roles')
        .select('id, code, name, display_order, is_active')
        .order('display_order')
        .order('code');

    final roles = rolesRows.map((row) => _RoleOption.fromJson(row)).toList();
    final roleById = {for (final role in roles) role.id: role};

    final templateRows = await Supabase.instance.client
        .from('role_templates')
        .select('id, role_id, weekday_rule, monthly_day, start_time, end_time')
        .order('weekday_rule')
        .order('start_time');

    final templates =
        templateRows.map((row) => _RoleTemplateRecord.fromJson(row)).toList()
          ..sort((a, b) {
            final roleCompare = (roleById[a.roleId]?.displayOrder ?? 9999)
                .compareTo(roleById[b.roleId]?.displayOrder ?? 9999);

            if (roleCompare != 0) {
              return roleCompare;
            }

            final weekdayCompare = _weekdayRuleSortValue(
              a.weekdayRule,
            ).compareTo(_weekdayRuleSortValue(b.weekdayRule));

            if (weekdayCompare != 0) {
              return weekdayCompare;
            }

            return a.startTime.compareTo(b.startTime);
          });

    return _TemplateScreenData(
      roles: roles,
      roleById: roleById,
      templates: templates,
    );
  }

  void _reloadData() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  Future<void> _openTemplateForm({_RoleTemplateRecord? template}) async {
    final data = await _dataFuture;

    if (!mounted) {
      return;
    }

    if (data.roles.isEmpty) {
      _showError('Create at least one role first.');
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _RoleTemplateFormSheet(roles: data.roles, template: template),
    );

    if (saved == true) {
      _reloadData();
    }
  }

  Future<void> _deleteTemplate(_RoleTemplateRecord template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete template?'),
        content: const Text('This stops future slot generation for this rule.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await Supabase.instance.client
          .from('role_templates')
          .delete()
          .eq('id', template.id);
      _reloadData();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not delete template.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoleTemplateFormSheet extends StatefulWidget {
  final List<_RoleOption> roles;
  final _RoleTemplateRecord? template;

  const _RoleTemplateFormSheet({required this.roles, this.template});

  @override
  State<_RoleTemplateFormSheet> createState() => _RoleTemplateFormSheetState();
}

class _RoleTemplateFormSheetState extends State<_RoleTemplateFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late String _roleId;
  late String _weekdayRule;
  late final TextEditingController _monthlyDayController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _roleId = template?.roleId ?? widget.roles.first.id;
    _weekdayRule = template?.weekdayRule ?? 'every_weekday';
    _monthlyDayController = TextEditingController(
      text: template?.monthlyDay == null ? '1' : '${template!.monthlyDay}',
    );
    _startTimeController = TextEditingController(
      text: template?.startTime ?? '08:00',
    );
    _endTimeController = TextEditingController(
      text: template?.endTime ?? '16:00',
    );
  }

  @override
  void dispose() {
    _monthlyDayController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.template == null ? 'Add template' : 'Edit template',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _roleId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Role',
                ),
                items: [
                  for (final role in widget.roles)
                    DropdownMenuItem(
                      value: role.id,
                      child: Text('${role.code} - ${role.name}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _roleId = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _weekdayRule,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Weekday rule',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'every_weekday',
                    child: Text('Every weekday'),
                  ),
                  DropdownMenuItem(
                    value: 'monday_only',
                    child: Text('Monday only'),
                  ),
                  DropdownMenuItem(
                    value: 'tuesday_only',
                    child: Text('Tuesday only'),
                  ),
                  DropdownMenuItem(
                    value: 'wednesday_only',
                    child: Text('Wednesday only'),
                  ),
                  DropdownMenuItem(
                    value: 'thursday_only',
                    child: Text('Thursday only'),
                  ),
                  DropdownMenuItem(
                    value: 'friday_only',
                    child: Text('Friday only'),
                  ),
                  DropdownMenuItem(
                    value: 'monthly_day',
                    child: Text('Monthly date'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _weekdayRule = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_weekdayRule == 'monthly_day') ...[
                TextFormField(
                  controller: _monthlyDayController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Day of month',
                    hintText: '1-31',
                  ),
                  validator: _monthlyDayValidator,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startTimeController,
                      keyboardType: TextInputType.datetime,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Start',
                        hintText: '07:30',
                      ),
                      validator: _timeValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _endTimeController,
                      keyboardType: TextInputType.datetime,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'End',
                        hintText: '15:30',
                      ),
                      validator: _timeValidator,
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveTemplate,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _timeValidator(String? value) {
    if (!_isValidTime(value ?? '')) {
      return 'Use HH:mm';
    }

    return null;
  }

  String? _monthlyDayValidator(String? value) {
    if (_weekdayRule != 'monthly_day') {
      return null;
    }

    final day = int.tryParse(value ?? '');

    if (day == null || day < 1 || day > 31) {
      return 'Use 1-31';
    }

    return null;
  }

  bool _isValidTime(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    return match != null;
  }

  Future<void> _saveTemplate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_startTimeController.text.compareTo(_endTimeController.text) >= 0) {
      setState(() {
        _errorMessage = 'End time must be after start time.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = {
      'role_id': _roleId,
      'weekday_rule': _weekdayRule,
      'monthly_day': _weekdayRule == 'monthly_day'
          ? int.parse(_monthlyDayController.text)
          : null,
      'start_time': _startTimeController.text.trim(),
      'end_time': _endTimeController.text.trim(),
    };

    try {
      final template = widget.template;

      if (template == null) {
        await Supabase.instance.client.from('role_templates').insert(payload);
      } else {
        await Supabase.instance.client
            .from('role_templates')
            .update(payload)
            .eq('id', template.id);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on PostgrestException catch (error) {
      setState(() {
        _errorMessage = error.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Could not save template.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _AdminErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdminErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateScreenData {
  final List<_RoleOption> roles;
  final Map<String, _RoleOption> roleById;
  final List<_RoleTemplateRecord> templates;

  const _TemplateScreenData({
    required this.roles,
    required this.roleById,
    required this.templates,
  });
}

class _RoleOption {
  final String id;
  final String code;
  final String name;
  final int displayOrder;
  final bool isActive;

  const _RoleOption({
    required this.id,
    required this.code,
    required this.name,
    required this.displayOrder,
    required this.isActive,
  });

  factory _RoleOption.fromJson(Map<String, dynamic> json) {
    return _RoleOption(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      displayOrder: json['display_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class _RoleTemplateRecord {
  final String id;
  final String roleId;
  final String weekdayRule;
  final int? monthlyDay;
  final String startTime;
  final String endTime;

  const _RoleTemplateRecord({
    required this.id,
    required this.roleId,
    required this.weekdayRule,
    required this.monthlyDay,
    required this.startTime,
    required this.endTime,
  });

  factory _RoleTemplateRecord.fromJson(Map<String, dynamic> json) {
    return _RoleTemplateRecord(
      id: json['id'] as String,
      roleId: json['role_id'] as String,
      weekdayRule: json['weekday_rule'] as String? ?? 'every_weekday',
      monthlyDay: json['monthly_day'] as int?,
      startTime: _formatTime(json['start_time'] as String? ?? ''),
      endTime: _formatTime(json['end_time'] as String? ?? ''),
    );
  }
}

String _formatTime(String value) {
  if (value.length >= 5) {
    return value.substring(0, 5);
  }

  return value;
}

String _weekdayRuleLabel(String rule) {
  switch (rule) {
    case 'every_weekday':
      return 'Every weekday';
    case 'monday_only':
      return 'Monday only';
    case 'tuesday_only':
      return 'Tuesday only';
    case 'wednesday_only':
      return 'Wednesday only';
    case 'thursday_only':
      return 'Thursday only';
    case 'friday_only':
      return 'Friday only';
    case 'monthly_day':
      return 'Monthly date';
  }

  return rule;
}

String _templateRuleLabel(_RoleTemplateRecord template) {
  if (template.weekdayRule == 'monthly_day') {
    return 'Monthly day ${template.monthlyDay ?? '?'}';
  }

  return _weekdayRuleLabel(template.weekdayRule);
}

int _weekdayRuleSortValue(String rule) {
  switch (rule) {
    case 'every_weekday':
      return 0;
    case 'monday_only':
      return 1;
    case 'tuesday_only':
      return 2;
    case 'wednesday_only':
      return 3;
    case 'thursday_only':
      return 4;
    case 'friday_only':
      return 5;
    case 'monthly_day':
      return 6;
  }

  return 99;
}
