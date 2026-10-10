import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'localization.dart';

class AdministrationScreen extends StatefulWidget {
  final DirectoryAdministrationService service;
  const AdministrationScreen({super.key, required this.service});
  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  List<ManagedPhysician> _physicians = [];
  List<ManagedViewer> _viewers = [];
  bool _busy = true, _failed = false, _viewingViewers = false;
  String _search = '';
  bool? _active;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final physicians = await widget.service.physicians();
      final viewers = await widget.service.viewers();
      if (mounted) {
        setState(() {
          _physicians = physicians;
          _viewers = viewers;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({
    ManagedPhysician? physician,
    ManagedViewer? viewer,
    bool invite = false,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DirectoryEditor(
        service: widget.service,
        physician: physician,
        viewer: viewer,
        inviteRole: invite
            ? (_viewingViewers
                  ? ManagedAccountRole.viewer
                  : ManagedAccountRole.doctor)
            : null,
      ),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _action(
    String title,
    DirectoryChange change, {
    bool deleting = false,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DirectoryCommandDialog(
        service: widget.service,
        request: change,
        title: title,
        deleting: deleting,
      ),
    );
    if (saved == true && mounted) await _reload();
  }

  DirectoryChange _physicianChange(
    ManagedPhysician p,
    Map<String, Object?> changes,
  ) => DirectoryChange(
    operation: AdminWriteIntent.create(),
    directory: 'physicians',
    id: p.id,
    updatedAt: p.updatedAt,
    changes: changes,
  );
  @override
  Widget build(BuildContext context) {
    final strings = AdminStrings.of(context);
    bool matches(String name, String? email, bool active) =>
        (_active == null || active == _active) &&
        '$name ${email ?? ''}'.toLowerCase().contains(_search.toLowerCase());
    return Scaffold(
      appBar: AppBar(
        title: const AdminText('Administration'),
        actions: [
          const LanguageButton(),
          IconButton(
            tooltip: strings.text('Refresh'),
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const AdminText('Physicians'),
                  selected: !_viewingViewers,
                  onSelected: (_) => setState(() => _viewingViewers = false),
                ),
                ChoiceChip(
                  label: const AdminText('Viewers'),
                  selected: _viewingViewers,
                  onSelected: (_) => setState(() => _viewingViewers = true),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: strings.text('Search name or email'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                for (final value in <bool?>[null, true, false])
                  FilterChip(
                    label: AdminText(
                      value == null
                          ? 'All'
                          : value
                          ? 'Active'
                          : 'Inactive',
                    ),
                    selected: _active == value,
                    onSelected: (_) => setState(() => _active = value),
                  ),
                FilledButton.icon(
                  onPressed: _busy || _failed
                      ? null
                      : () => _edit(invite: true),
                  icon: Icon(
                    _viewingViewers ? Icons.visibility : Icons.person_add,
                  ),
                  label: AdminText(
                    _viewingViewers ? 'Invite viewer' : 'Invite physician',
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_failed)
            MaterialBanner(
              content: const AdminText(
                'Directory unavailable. Check the migration, connection and administrator access.',
              ),
              actions: [
                TextButton(onPressed: _reload, child: const AdminText('Retry')),
              ],
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _viewingViewers
                  ? _viewers
                        .where(
                          (p) =>
                              matches(p.displayName, p.email, !p.accessRevoked),
                        )
                        .length
                  : _physicians
                        .where((p) => matches(p.fullName, p.email, p.isActive))
                        .length,
              itemBuilder: (context, index) {
                if (_viewingViewers) {
                  final p = _viewers
                      .where(
                        (p) =>
                            matches(p.displayName, p.email, !p.accessRevoked),
                      )
                      .elementAt(index);
                  return ListTile(
                    title: Text(p.displayName),
                    subtitle: Text(
                      '${p.email ?? ''}\n${strings.text(p.accessRevoked ? 'Access revoked' : 'Active')}',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: strings.text('Edit'),
                          onPressed: _busy || _failed
                              ? null
                              : () => _edit(viewer: p),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          tooltip: strings.text(
                            p.accessRevoked
                                ? 'Restore access'
                                : 'Revoke access',
                          ),
                          icon: Icon(
                            p.accessRevoked
                                ? Icons.person_add
                                : Icons.person_off,
                          ),
                          onPressed: _busy || _failed
                              ? null
                              : () => _action(
                                  p.accessRevoked
                                      ? 'Restore access'
                                      : 'Revoke access',
                                  DirectoryChange(
                                    operation: AdminWriteIntent.create(),
                                    directory: 'viewers',
                                    id: p.id,
                                    updatedAt: p.updatedAt,
                                    changes: {
                                      'access_revoked': !p.accessRevoked,
                                    },
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                }
                final p = _physicians
                    .where((p) => matches(p.fullName, p.email, p.isActive))
                    .elementAt(index);
                return ListTile(
                  title: Text(p.fullName),
                  subtitle: Text(
                    '${p.email ?? strings.text('No account linked')} · ${strings.text(p.isActive ? 'Active' : 'Inactive')}\n${strings.text(p.rank.name)} · ${p.capabilities.map((c) => strings.text(c.name)).join(', ')}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: strings.text('Edit'),
                        onPressed: _busy || _failed
                            ? null
                            : () => _edit(physician: p),
                        icon: const Icon(Icons.edit),
                      ),
                      IconButton(
                        tooltip: strings.text(
                          p.isActive ? 'Deactivate' : 'Reactivate',
                        ),
                        icon: Icon(
                          p.isActive ? Icons.archive : Icons.unarchive,
                        ),
                        onPressed: _busy || _failed
                            ? null
                            : () => _action(
                                p.isActive ? 'Deactivate' : 'Reactivate',
                                _physicianChange(p, {'is_active': !p.isActive}),
                              ),
                      ),
                      IconButton(
                        tooltip: strings.text('Delete'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _busy || _failed
                            ? null
                            : () => _action(
                                'Delete',
                                _physicianChange(p, {'delete': true}),
                                deleting: true,
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String directoryFailureText(Object e) => e is DirectoryFailure
    ? switch (e.code) {
        'physicianHasDependencies' =>
          'History or dependent records prevent deletion. Deactivate the physician instead.',
        'staleVersion' =>
          'Data changed. Close and reload before editing again.',
        'accountExists' => 'An account with this email already exists.',
        'invalidSession' =>
          'The invitation endpoint rejected the session. Sign in again and check the Edge Function deployment.',
        'adminAal2Required' => 'Verified administrator MFA session required',
        'invitationEndpointOutdated' =>
          'Deploy the updated invite-doctor function before inviting viewers.',
        'invitationUnknown' =>
          'Invitation outcome unknown. Close and reload the directory before retrying.',
        _ =>
          e.outcomeUnknown
              ? 'Outcome unknown. Retry the same request safely.'
              : 'Operation failed. Check your access and connection.',
      }
    : 'Operation failed. Check your access and connection.';

class _DirectoryCommandDialog extends StatefulWidget {
  final DirectoryAdministrationService service;
  final DirectoryChange request;
  final String title;
  final bool deleting;
  const _DirectoryCommandDialog({
    required this.service,
    required this.request,
    required this.title,
    required this.deleting,
  });
  @override
  State<_DirectoryCommandDialog> createState() =>
      _DirectoryCommandDialogState();
}

class _DirectoryCommandDialogState extends State<_DirectoryCommandDialog> {
  DirectoryChange? _archiveRequest;
  bool busy = false, rejected = false, dependencies = false;
  String? error;
  Future<void> apply({bool archive = false}) async {
    setState(() => busy = true);
    try {
      final r = widget.request;
      if (archive) {
        _archiveRequest ??= DirectoryChange(
          operation: AdminWriteIntent.create(),
          directory: r.directory,
          id: r.id,
          updatedAt: r.updatedAt,
          changes: {'is_active': false},
        );
      }
      await widget.service.change(_archiveRequest ?? r);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = directoryFailureText(e);
          rejected = e is! DirectoryFailure || !e.outcomeUnknown;
          dependencies =
              e is DirectoryFailure && e.code == 'physicianHasDependencies';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: AdminText(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminText(
            widget.deleting
                ? 'Delete this unused physician record? The login account will remain.'
                : 'Historical records are retained.',
          ),
          if (error != null)
            AdminText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const AdminText('Close'),
        ),
        if (dependencies)
          FilledButton.icon(
            onPressed: busy ? null : () => apply(archive: true),
            icon: const Icon(Icons.archive),
            label: const AdminText('Deactivate'),
          )
        else
          FilledButton(
            onPressed: busy || rejected ? null : apply,
            child: AdminText(
              error == null ? widget.title : 'Retry same request',
            ),
          ),
      ],
    ),
  );
}

class DirectoryEditor extends StatefulWidget {
  final DirectoryAdministrationService service;
  final ManagedPhysician? physician;
  final ManagedViewer? viewer;
  final ManagedAccountRole? inviteRole;
  const DirectoryEditor({
    super.key,
    required this.service,
    this.physician,
    this.viewer,
    this.inviteRole,
  });
  @override
  State<DirectoryEditor> createState() => _DirectoryEditorState();
}

class _DirectoryEditorState extends State<DirectoryEditor> {
  final form = GlobalKey<FormState>();
  late final first = TextEditingController(
    text: widget.physician?.firstName ?? widget.viewer?.displayName ?? '',
  );
  late final last = TextEditingController(
    text: widget.physician?.lastName ?? '',
  );
  final email = TextEditingController();
  late final order = TextEditingController(
    text: '${widget.physician?.printOrder ?? 0}',
  );
  late DoctorRank rank = widget.physician?.rank ?? DoctorRank.resident;
  late Set<Capability> capabilities = {...?widget.physician?.capabilities};
  late bool active = widget.physician?.isActive ?? true;
  late ProfileLanguage language = widget.viewer?.language ?? ProfileLanguage.en;
  bool busy = false, rejected = false, uncertainInvite = false;
  String? error;
  DirectoryChange? pending;
  bool get isPhysician =>
      widget.physician != null ||
      widget.inviteRole == ManagedAccountRole.doctor;
  @override
  void dispose() {
    first.dispose();
    last.dispose();
    email.dispose();
    order.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (widget.inviteRole != null) {
        await widget.service.invite(
          InvitationRequest(
            operation: AdminWriteIntent.create(),
            accountRole: widget.inviteRole!,
            email: email.text,
            firstName: first.text,
            lastName: last.text,
            language: language,
            rank: isPhysician ? rank : null,
            capabilities: isPhysician ? capabilities : [],
            isActive: active,
            printOrder: isPhysician ? int.parse(order.text) : null,
          ),
        );
      } else {
        pending ??= DirectoryChange(
          operation: AdminWriteIntent.create(),
          directory: isPhysician ? 'physicians' : 'viewers',
          id: widget.physician?.id ?? widget.viewer!.id,
          updatedAt: widget.physician?.updatedAt ?? widget.viewer!.updatedAt,
          changes: isPhysician
              ? {
                  'first_name': first.text.trim(),
                  'last_name': last.text.trim(),
                  'rank': databaseEnum(rank),
                  'capabilities': capabilities.map(databaseEnum).toList(),
                  'is_active': active,
                  'print_order': int.parse(order.text),
                }
              : {
                  'display_name': first.text.trim(),
                  'preferred_language': language.name,
                },
        );
        await widget.service.change(pending!);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = directoryFailureText(e);
          uncertainInvite =
              widget.inviteRole != null &&
              e is DirectoryFailure &&
              e.outcomeUnknown;
          rejected =
              widget.inviteRole == null &&
              (e is! DirectoryFailure || !e.outcomeUnknown);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AdminStrings.of(context);
    final enabled = !busy && pending == null && !uncertainInvite;
    Widget field(
      TextEditingController controller,
      String label, {
      bool mail = false,
      bool number = false,
    }) => TextFormField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(labelText: strings.text(label)),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return strings.text('Required');
        if (mail && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())) {
          return strings.text('Enter a valid email address.');
        }
        if (number && int.tryParse(v) == null) {
          return strings.text('Enter a whole number.');
        }
        return null;
      },
    );
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: AdminText(
          widget.inviteRole != null
              ? (isPhysician ? 'Invite physician' : 'Invite viewer')
              : 'Edit',
        ),
        content: SizedBox(
          width: 530,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(
                    first,
                    widget.viewer != null ? 'Display name' : 'First name',
                  ),
                  if (widget.viewer == null) field(last, 'Last name'),
                  if (widget.inviteRole != null)
                    field(email, 'Email', mail: true),
                  if (isPhysician) ...[
                    DropdownButtonFormField<DoctorRank>(
                      initialValue: rank,
                      decoration: InputDecoration(
                        labelText: strings.text('Rank'),
                      ),
                      items: [
                        for (final r in DoctorRank.values)
                          DropdownMenuItem(value: r, child: AdminText(r.name)),
                      ],
                      onChanged: enabled
                          ? (v) => setState(() => rank = v!)
                          : null,
                    ),
                    const AdminText('Capabilities'),
                    for (final c in Capability.values)
                      CheckboxListTile(
                        title: AdminText(c.name),
                        value: capabilities.contains(c),
                        onChanged: enabled
                            ? (v) => setState(
                                () => v!
                                    ? capabilities.add(c)
                                    : capabilities.remove(c),
                              )
                            : null,
                      ),
                    SwitchListTile(
                      title: const AdminText('Active'),
                      value: active,
                      onChanged: enabled
                          ? (v) => setState(() => active = v)
                          : null,
                    ),
                    field(order, 'Print order', number: true),
                  ],
                  if (widget.inviteRole != null || widget.viewer != null)
                    DropdownButtonFormField<ProfileLanguage>(
                      initialValue: language,
                      decoration: InputDecoration(
                        labelText: strings.text('Language'),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ProfileLanguage.de,
                          child: Text('Deutsch'),
                        ),
                        DropdownMenuItem(
                          value: ProfileLanguage.en,
                          child: Text('English'),
                        ),
                      ],
                      onChanged: enabled
                          ? (v) => setState(() => language = v!)
                          : null,
                    ),
                  if (error != null)
                    AdminText(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () => Navigator.pop(context, uncertainInvite || rejected),
            child: const AdminText('Close'),
          ),
          FilledButton(
            onPressed: busy || rejected || uncertainInvite ? null : save,
            child: AdminText(
              pending != null
                  ? 'Retry same request'
                  : widget.inviteRole != null
                  ? 'Invite'
                  : 'Save',
            ),
          ),
        ],
      ),
    );
  }
}
