import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminInviteDoctorScreen extends StatefulWidget {
  const AdminInviteDoctorScreen({super.key});

  @override
  State<AdminInviteDoctorScreen> createState() =>
      _AdminInviteDoctorScreenState();
}

class _AdminInviteDoctorScreenState extends State<AdminInviteDoctorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String _rank = 'resident';
  String _preferredLanguage = 'de';
  final Set<String> _capabilities = {};
  bool _isSending = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite doctor')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create account and send password setup link',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The doctor receives a one-time email link and chooses '
                    'their own password. Administrators never see it.',
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Institutional email',
                    ),
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'First name',
                          ),
                          validator: _validateRequired,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Last name',
                          ),
                          validator: _validateRequired,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _rank,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Rank',
                    ),
                    items: _rankLabels.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: _isSending
                        ? null
                        : (value) => setState(() => _rank = value ?? _rank),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _preferredLanguage,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Preferred language',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'de', child: Text('German')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                    ],
                    onChanged: _isSending
                        ? null
                        : (value) => setState(
                            () => _preferredLanguage =
                                value ?? _preferredLanguage,
                          ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Capabilities',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: _isSending
                            ? null
                            : () => setState(() {
                                if (_capabilities.length ==
                                    _capabilityLabels.length) {
                                  _capabilities.clear();
                                } else {
                                  _capabilities
                                    ..clear()
                                    ..addAll(_capabilityLabels.keys);
                                }
                              }),
                        child: Text(
                          _capabilities.length == _capabilityLabels.length
                              ? 'Clear all'
                              : 'Select all',
                        ),
                      ),
                    ],
                  ),
                  ..._capabilityLabels.entries.map(
                    (entry) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      value: _capabilities.contains(entry.key),
                      onChanged: _isSending
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _capabilities.add(entry.key);
                              } else {
                                _capabilities.remove(entry.key);
                              }
                            }),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_successMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _successMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _inviteDoctor,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.outgoing_mail),
                    label: const Text('Create doctor and send link'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _inviteDoctor() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'invite-doctor',
        body: {
          'email': _emailController.text.trim().toLowerCase(),
          'firstName': _firstNameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'rank': _rank,
          'preferredLanguage': _preferredLanguage,
          'capabilities': _capabilities.toList()..sort(),
        },
      );

      final data = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw Exception(_errorFromResponse(data));
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _successMessage =
            'Doctor created. Password setup link sent to '
            '${_emailController.text.trim()}.';
        _emailController.clear();
        _firstNameController.clear();
        _lastNameController.clear();
        _rank = 'resident';
        _capabilities.clear();
      });
    } on FunctionException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _errorFromResponse(error.details));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validateRequired(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  String _errorFromResponse(Object? data) {
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    return 'Could not invite doctor.';
  }
}

const _rankLabels = {
  'resident': 'Resident',
  'specialist': 'Specialist',
  'senior_specialist': 'Senior specialist',
  'consultant': 'Consultant',
  'head': 'Head',
};

const _capabilityLabels = {
  'can_lead': 'Can lead',
  'can_work_outpatient_clinic': 'Can work outpatient clinic',
  'can_do_neurosonography': 'Can do neurosonography',
  'can_do_night_duty': 'Can do night duty',
  'can_supervise': 'Can supervise',
};
