import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRolesScreen extends StatefulWidget {
  const AdminRolesScreen({super.key});

  @override
  State<AdminRolesScreen> createState() => _AdminRolesScreenState();
}

class _AdminRolesScreenState extends State<AdminRolesScreen> {
  late Future<List<_RoleRecord>> _rolesFuture;

  @override
  void initState() {
    super.initState();
    _rolesFuture = _loadRoles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Roles')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRoleForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add role'),
      ),
      body: FutureBuilder<List<_RoleRecord>>(
        future: _rolesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reloadRoles,
            );
          }

          final roles = snapshot.data ?? [];

          if (roles.isEmpty) {
            return const Center(child: Text('No roles yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: roles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final role = roles[index];

              return ListTile(
                leading: CircleAvatar(child: Text(role.code)),
                title: Text(role.name),
                subtitle: Text(
                  '${role.area.isEmpty ? 'No area' : role.area} · '
                  'max ${role.maxDoctors} · order ${role.displayOrder}',
                ),
                trailing: Switch(
                  value: role.isActive,
                  onChanged: (value) =>
                      _setRoleActiveState(role: role, isActive: value),
                ),
                onTap: () => _openRoleForm(role: role),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_RoleRecord>> _loadRoles() async {
    final rows = await Supabase.instance.client
        .from('roles')
        .select(
          'id, code, name, area, display_order, max_doctors, '
          'required_capabilities, allowed_ranks, is_active',
        )
        .order('display_order')
        .order('code');

    return rows.map((row) => _RoleRecord.fromJson(row)).toList();
  }

  void _reloadRoles() {
    setState(() {
      _rolesFuture = _loadRoles();
    });
  }

  Future<void> _openRoleForm({_RoleRecord? role}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RoleFormSheet(role: role),
    );

    if (saved == true) {
      _reloadRoles();
    }
  }

  Future<void> _setRoleActiveState({
    required _RoleRecord role,
    required bool isActive,
  }) async {
    try {
      await Supabase.instance.client
          .from('roles')
          .update({'is_active': isActive})
          .eq('id', role.id);
      _reloadRoles();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not update role.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RoleFormSheet extends StatefulWidget {
  final _RoleRecord? role;

  const _RoleFormSheet({this.role});

  @override
  State<_RoleFormSheet> createState() => _RoleFormSheetState();
}

class _RoleFormSheetState extends State<_RoleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _areaController;
  late final TextEditingController _displayOrderController;
  late final TextEditingController _maxDoctorsController;
  late Set<String> _requiredCapabilities;
  late Set<String> _allowedRanks;
  late bool _isActive;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _codeController = TextEditingController(text: role?.code ?? '');
    _nameController = TextEditingController(text: role?.name ?? '');
    _areaController = TextEditingController(text: role?.area ?? '');
    _displayOrderController = TextEditingController(
      text: '${role?.displayOrder ?? 100}',
    );
    _maxDoctorsController = TextEditingController(
      text: '${role?.maxDoctors ?? 1}',
    );
    _requiredCapabilities = {...?role?.requiredCapabilities};
    _allowedRanks = {...?role?.allowedRanks};
    _isActive = role?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _areaController.dispose();
    _displayOrderController.dispose();
    _maxDoctorsController.dispose();
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
                widget.role == null ? 'Add role' : 'Edit role',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Abbreviation',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Name',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _areaController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Area',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _displayOrderController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Display order',
                      ),
                      validator: _positiveIntegerValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxDoctorsController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Max doctors',
                      ),
                      validator: _positiveIntegerValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Allowed ranks',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _ChoiceCheckbox(
                label: 'Resident',
                value: 'resident',
                selected: _allowedRanks,
                onChanged: _setAllowedRank,
              ),
              _ChoiceCheckbox(
                label: 'Specialist',
                value: 'specialist',
                selected: _allowedRanks,
                onChanged: _setAllowedRank,
              ),
              _ChoiceCheckbox(
                label: 'Senior specialist',
                value: 'senior_specialist',
                selected: _allowedRanks,
                onChanged: _setAllowedRank,
              ),
              _ChoiceCheckbox(
                label: 'Consultant',
                value: 'consultant',
                selected: _allowedRanks,
                onChanged: _setAllowedRank,
              ),
              _ChoiceCheckbox(
                label: 'Head',
                value: 'head',
                selected: _allowedRanks,
                onChanged: _setAllowedRank,
              ),
              const SizedBox(height: 12),
              const Text(
                'Required capabilities',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _ChoiceCheckbox(
                label: 'Can lead',
                value: 'can_lead',
                selected: _requiredCapabilities,
                onChanged: _setRequiredCapability,
              ),
              _ChoiceCheckbox(
                label: 'Outpatient clinic',
                value: 'can_work_outpatient_clinic',
                selected: _requiredCapabilities,
                onChanged: _setRequiredCapability,
              ),
              _ChoiceCheckbox(
                label: 'Neurosonography',
                value: 'can_do_neurosonography',
                selected: _requiredCapabilities,
                onChanged: _setRequiredCapability,
              ),
              _ChoiceCheckbox(
                label: 'Night duty',
                value: 'can_do_night_duty',
                selected: _requiredCapabilities,
                onChanged: _setRequiredCapability,
              ),
              _ChoiceCheckbox(
                label: 'Can supervise',
                value: 'can_supervise',
                selected: _requiredCapabilities,
                onChanged: _setRequiredCapability,
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
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
                onPressed: _isSaving ? null : _saveRole,
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

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  String? _positiveIntegerValidator(String? value) {
    final number = int.tryParse(value ?? '');

    if (number == null || number <= 0) {
      return 'Use a positive number';
    }

    return null;
  }

  void _setAllowedRank(String rank, bool enabled) {
    setState(() {
      if (enabled) {
        _allowedRanks.add(rank);
      } else {
        _allowedRanks.remove(rank);
      }
    });
  }

  void _setRequiredCapability(String capability, bool enabled) {
    setState(() {
      if (enabled) {
        _requiredCapabilities.add(capability);
      } else {
        _requiredCapabilities.remove(capability);
      }
    });
  }

  Future<void> _saveRole() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = {
      'code': _codeController.text.trim().toUpperCase(),
      'name': _nameController.text.trim(),
      'area': _areaController.text.trim(),
      'display_order': int.parse(_displayOrderController.text),
      'max_doctors': int.parse(_maxDoctorsController.text),
      'allowed_ranks': _allowedRanks.toList()..sort(),
      'required_capabilities': _requiredCapabilities.toList()..sort(),
      'is_active': _isActive,
    };

    try {
      final role = widget.role;

      if (role == null) {
        await Supabase.instance.client.from('roles').insert(payload);
      } else {
        await Supabase.instance.client
            .from('roles')
            .update(payload)
            .eq('id', role.id);
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
        _errorMessage = 'Could not save role.';
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

class _ChoiceCheckbox extends StatelessWidget {
  final String label;
  final String value;
  final Set<String> selected;
  final void Function(String value, bool enabled) onChanged;

  const _ChoiceCheckbox({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: selected.contains(value),
      onChanged: (enabled) => onChanged(value, enabled ?? false),
    );
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

class _RoleRecord {
  final String id;
  final String code;
  final String name;
  final String area;
  final int displayOrder;
  final int maxDoctors;
  final Set<String> requiredCapabilities;
  final Set<String> allowedRanks;
  final bool isActive;

  const _RoleRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.area,
    required this.displayOrder,
    required this.maxDoctors,
    required this.requiredCapabilities,
    required this.allowedRanks,
    required this.isActive,
  });

  factory _RoleRecord.fromJson(Map<String, dynamic> json) {
    return _RoleRecord(
      id: json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      area: json['area'] as String? ?? '',
      displayOrder: json['display_order'] as int? ?? 0,
      maxDoctors: json['max_doctors'] as int? ?? 1,
      requiredCapabilities: _stringSetFromJson(json['required_capabilities']),
      allowedRanks: _stringSetFromJson(json['allowed_ranks']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

Set<String> _stringSetFromJson(Object? value) {
  if (value is! List) {
    return {};
  }

  return value.whereType<String>().toSet();
}
