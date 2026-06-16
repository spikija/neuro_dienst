import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDoctorsScreen extends StatefulWidget {
  const AdminDoctorsScreen({super.key});

  @override
  State<AdminDoctorsScreen> createState() => _AdminDoctorsScreenState();
}

class _AdminDoctorsScreenState extends State<AdminDoctorsScreen> {
  late Future<List<_DoctorRecord>> _doctorsFuture;

  @override
  void initState() {
    super.initState();
    _doctorsFuture = _loadDoctors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Doctors')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDoctorForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add doctor'),
      ),
      body: FutureBuilder<List<_DoctorRecord>>(
        future: _doctorsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reloadDoctors,
            );
          }

          final doctors = snapshot.data ?? [];

          if (doctors.isEmpty) {
            return const Center(child: Text('No doctors yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: doctors.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doctor = doctors[index];

              return ListTile(
                leading: SizedBox(
                  width: 92,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '#${doctor.printOrder}',
                          textAlign: TextAlign.right,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(child: Text(doctor.initials)),
                    ],
                  ),
                ),
                title: Text(doctor.fullName),
                subtitle: Text(
                  '${_rankLabel(doctor.rank)} · print order ${doctor.printOrder}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Move up in print report',
                      onPressed: index == 0
                          ? null
                          : () => _swapPrintOrder(
                              doctors[index],
                              doctors[index - 1],
                            ),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move down in print report',
                      onPressed: index == doctors.length - 1
                          ? null
                          : () => _swapPrintOrder(
                              doctors[index],
                              doctors[index + 1],
                            ),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    Switch(
                      value: doctor.isActive,
                      onChanged: (value) => _setDoctorActiveState(
                        doctor: doctor,
                        isActive: value,
                      ),
                    ),
                  ],
                ),
                onTap: () => _openDoctorForm(doctor: doctor),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<_DoctorRecord>> _loadDoctors() async {
    final rows = await Supabase.instance.client
        .from('doctors')
        .select(
          'id, first_name, last_name, rank, print_order, capabilities, is_active',
        )
        .order('print_order')
        .order('last_name')
        .order('first_name');

    return rows.map((row) => _DoctorRecord.fromJson(row)).toList();
  }

  void _reloadDoctors() {
    setState(() {
      _doctorsFuture = _loadDoctors();
    });
  }

  Future<void> _openDoctorForm({_DoctorRecord? doctor}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DoctorFormSheet(doctor: doctor),
    );

    if (saved == true) {
      _reloadDoctors();
    }
  }

  Future<void> _setDoctorActiveState({
    required _DoctorRecord doctor,
    required bool isActive,
  }) async {
    try {
      await Supabase.instance.client
          .from('doctors')
          .update({'is_active': isActive})
          .eq('id', doctor.id);
      _reloadDoctors();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not update doctor.');
    }
  }

  Future<void> _swapPrintOrder(
    _DoctorRecord firstDoctor,
    _DoctorRecord secondDoctor,
  ) async {
    try {
      await Supabase.instance.client
          .from('doctors')
          .update({'print_order': secondDoctor.printOrder})
          .eq('id', firstDoctor.id);
      await Supabase.instance.client
          .from('doctors')
          .update({'print_order': firstDoctor.printOrder})
          .eq('id', secondDoctor.id);
      _reloadDoctors();
    } on PostgrestException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not update print order.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DoctorFormSheet extends StatefulWidget {
  final _DoctorRecord? doctor;

  const _DoctorFormSheet({this.doctor});

  @override
  State<_DoctorFormSheet> createState() => _DoctorFormSheetState();
}

class _DoctorFormSheetState extends State<_DoctorFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _printOrderController;
  late String _rank;
  late Set<String> _capabilities;
  late bool _isActive;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final doctor = widget.doctor;
    _firstNameController = TextEditingController(text: doctor?.firstName ?? '');
    _lastNameController = TextEditingController(text: doctor?.lastName ?? '');
    _printOrderController = TextEditingController(
      text: (doctor?.printOrder ?? 0).toString(),
    );
    _rank = doctor?.rank ?? 'resident';
    _capabilities = {...?doctor?.capabilities};
    _isActive = doctor?.isActive ?? true;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _printOrderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.doctor == null ? 'Add doctor' : 'Edit doctor',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _firstNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'First name',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Last name',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _rank,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Rank',
                ),
                items: const [
                  DropdownMenuItem(value: 'resident', child: Text('Resident')),
                  DropdownMenuItem(
                    value: 'specialist',
                    child: Text('Specialist'),
                  ),
                  DropdownMenuItem(
                    value: 'senior_specialist',
                    child: Text('Senior specialist'),
                  ),
                  DropdownMenuItem(
                    value: 'consultant',
                    child: Text('Consultant'),
                  ),
                  DropdownMenuItem(value: 'head', child: Text('Head')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _rank = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _printOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Print order',
                  helperText:
                      'Lower numbers appear further left in physician reports.',
                ),
                validator: _printOrderValidator,
              ),
              const SizedBox(height: 12),
              const Text(
                'Capabilities',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              _CapabilityCheckbox(
                label: 'Can lead',
                value: 'can_lead',
                selected: _capabilities,
                onChanged: _setCapability,
              ),
              _CapabilityCheckbox(
                label: 'Outpatient clinic',
                value: 'can_work_outpatient_clinic',
                selected: _capabilities,
                onChanged: _setCapability,
              ),
              _CapabilityCheckbox(
                label: 'Neurosonography',
                value: 'can_do_neurosonography',
                selected: _capabilities,
                onChanged: _setCapability,
              ),
              _CapabilityCheckbox(
                label: 'Night duty',
                value: 'can_do_night_duty',
                selected: _capabilities,
                onChanged: _setCapability,
              ),
              _CapabilityCheckbox(
                label: 'Can supervise',
                value: 'can_supervise',
                selected: _capabilities,
                onChanged: _setCapability,
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
                onPressed: _isSaving ? null : _saveDoctor,
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

  String? _printOrderValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    if (int.tryParse(value.trim()) == null) {
      return 'Enter a whole number';
    }

    return null;
  }

  void _setCapability(String capability, bool enabled) {
    setState(() {
      if (enabled) {
        _capabilities.add(capability);
      } else {
        _capabilities.remove(capability);
      }
    });
  }

  Future<void> _saveDoctor() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'rank': _rank,
      'print_order': int.parse(_printOrderController.text.trim()),
      'capabilities': _capabilities.toList()..sort(),
      'is_active': _isActive,
    };

    try {
      final doctor = widget.doctor;

      if (doctor == null) {
        await Supabase.instance.client.from('doctors').insert(payload);
      } else {
        await Supabase.instance.client
            .from('doctors')
            .update(payload)
            .eq('id', doctor.id);
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
        _errorMessage = 'Could not save doctor.';
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

class _CapabilityCheckbox extends StatelessWidget {
  final String label;
  final String value;
  final Set<String> selected;
  final void Function(String capability, bool enabled) onChanged;

  const _CapabilityCheckbox({
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

class _DoctorRecord {
  final String id;
  final String firstName;
  final String lastName;
  final String rank;
  final int printOrder;
  final Set<String> capabilities;
  final bool isActive;

  const _DoctorRecord({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.rank,
    required this.printOrder,
    required this.capabilities,
    required this.isActive,
  });

  factory _DoctorRecord.fromJson(Map<String, dynamic> json) {
    return _DoctorRecord(
      id: json['id'] as String,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      rank: json['rank'] as String? ?? 'resident',
      printOrder: json['print_order'] as int? ?? 0,
      capabilities: _capabilitiesFromJson(json['capabilities']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final firstInitial = firstName.isEmpty ? '' : firstName[0];
    final lastInitial = lastName.isEmpty ? '' : lastName[0];
    final value = '$firstInitial$lastInitial'.toUpperCase();
    return value.isEmpty ? '?' : value;
  }
}

Set<String> _capabilitiesFromJson(Object? value) {
  if (value is! List) {
    return {};
  }

  return value.whereType<String>().toSet();
}

String _rankLabel(String rank) {
  switch (rank) {
    case 'resident':
      return 'Resident';
    case 'specialist':
      return 'Specialist';
    case 'senior_specialist':
      return 'Senior specialist';
    case 'consultant':
      return 'Consultant';
    case 'head':
      return 'Head';
  }

  return rank;
}
