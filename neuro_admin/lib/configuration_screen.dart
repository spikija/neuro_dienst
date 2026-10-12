import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'administration_screen.dart' show directoryFailureText;
import 'localization.dart';
import 'role_indicators.dart';

class ConfigurationScreen extends StatefulWidget {
  final ConfigurationAdministrationService service;
  const ConfigurationScreen({super.key, required this.service});
  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  ConfigurationSnapshot? data;
  bool busy = false, templates = false;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await widget.service.configuration();
      if (mounted) setState(() => data = next);
    } catch (e) {
      if (mounted) setState(() => error = directoryFailureText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit({
    ConfiguredRole? role,
    ConfiguredTemplate? template,
    bool delete = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ConfigurationEditor(
        service: widget.service,
        data: data!,
        templates: templates,
        role: role,
        template: template,
        delete: delete,
      ),
    );
    if (result == true && mounted) await reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const AdminText('Roles / templates'),
      actions: [
        const LanguageButton(),
        IconButton(
          onPressed: busy ? null : reload,
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
            children: [
              ChoiceChip(
                label: const AdminText('Roles'),
                selected: !templates,
                onSelected: (_) => setState(() => templates = false),
              ),
              ChoiceChip(
                label: const AdminText('Templates'),
                selected: templates,
                onSelected: (_) => setState(() => templates = true),
              ),
              FilledButton.icon(
                onPressed:
                    busy ||
                        data == null ||
                        error != null ||
                        (templates && data!.roles.isEmpty)
                    ? null
                    : () => edit(),
                icon: const Icon(Icons.add),
                label: AdminText(templates ? 'Create template' : 'Create role'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: AdminText(
            'Template changes apply only to future generation or explicit draft regeneration. Times use Europe/Vienna.',
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: AdminText(error!)),
        if (data != null)
          Expanded(
            child: ListView(
              children: [
                if (!templates)
                  for (final r in data!.roles)
                    ListTile(
                      leading: Icon(
                        Icons.circle,
                        color: roleDisplayColor(context, r.id, r.colorKey),
                        size: 16,
                      ),
                      title: Text('${r.code} | ${r.name}'),
                      subtitle: AdminText(r.active ? 'Active' : 'Inactive'),
                      onTap: busy || error != null ? null : () => edit(role: r),
                      trailing: IconButton(
                        tooltip: AdminStrings.of(context).text('Delete'),
                        onPressed: busy || error != null
                            ? null
                            : () => edit(role: r, delete: true),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                if (templates)
                  for (final t in data!.templates)
                    ListTile(
                      title: Text(
                        '${data!.roles.where((r) => r.id == t.roleId).map((r) => r.name).firstOrNull ?? t.roleId} | ${t.start} - ${t.end}',
                      ),
                      subtitle: Text(
                        '${AdminStrings.of(context).text(t.active ? 'Active' : 'Inactive')} | ${t.monthly ? t.day : t.weekdays.join(', ')}',
                      ),
                      onTap: busy || error != null
                          ? null
                          : () => edit(template: t),
                      trailing: IconButton(
                        tooltip: AdminStrings.of(context).text('Delete'),
                        onPressed: busy || error != null
                            ? null
                            : () => edit(template: t, delete: true),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
              ],
            ),
          ),
      ],
    ),
  );
}

class ConfigurationEditor extends StatefulWidget {
  final ConfigurationAdministrationService service;
  final ConfigurationSnapshot data;
  final bool templates, delete;
  final ConfiguredRole? role;
  final ConfiguredTemplate? template;
  const ConfigurationEditor({
    super.key,
    required this.service,
    required this.data,
    required this.templates,
    this.role,
    this.template,
    this.delete = false,
  });
  @override
  State<ConfigurationEditor> createState() => _ConfigurationEditorState();
}

class _ConfigurationEditorState extends State<ConfigurationEditor> {
  final form = GlobalKey<FormState>();
  late final code = TextEditingController(text: widget.role?.code ?? '');
  late final name = TextEditingController(text: widget.role?.name ?? '');
  late final capacity = TextEditingController(
    text:
        '${widget.templates ? widget.template?.capacity ?? widget.data.roles.where((r) => r.id == (widget.template?.roleId ?? widget.data.roles.firstOrNull?.id)).firstOrNull?.capacity ?? 1 : widget.role?.capacity ?? 1}',
  );
  late final order = TextEditingController(
    text: '${widget.role?.displayOrder ?? 0}',
  );
  late final day = TextEditingController(text: '${widget.template?.day ?? 1}');
  late final start = TextEditingController(
    text: widget.template?.start.substring(0, 5) ?? '08:00',
  );
  late final end = TextEditingController(
    text: widget.template?.end.substring(0, 5) ?? '16:00',
  );
  late String? colorKey = widget.role?.colorKey;
  late bool active = widget.template?.active ?? widget.role?.active ?? true;
  late bool printVisible = widget.role?.printInReport ?? true;
  late bool monthly = widget.template?.monthly ?? false;
  late String? roleId =
      widget.template?.roleId ?? widget.data.roles.firstOrNull?.id;
  late Set<int> weekdays = {
    ...?widget.template?.weekdays,
    if (widget.template == null) ...[1, 2, 3, 4, 5],
  };
  late Set<DoctorRank> ranks = {...?widget.role?.ranks};
  late Set<Capability> capabilities = {...?widget.role?.capabilities};
  ConfigurationChange? pending;
  bool busy = false, rejected = false, acknowledged = false;
  String? error;
  @override
  void dispose() {
    for (final c in [code, name, capacity, order, day, start, end]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!widget.delete && !form.currentState!.validate()) return;
    if (widget.templates && !widget.delete && !monthly && weekdays.isEmpty) {
      setState(() => error = 'Select at least one weekday.');
      return;
    }
    if (widget.templates &&
        !widget.delete &&
        end.text.compareTo(start.text) <= 0) {
      setState(() => error = 'End time must be after start time.');
      return;
    }
    pending ??= ConfigurationChange(
      operation: AdminWriteIntent.create(),
      kind: widget.templates ? 'templates' : 'roles',
      id:
          widget.template?.id ??
          widget.role?.id ??
          AdminWriteIntent.create().requestId,
      updatedAt: widget.template?.updatedAt ?? widget.role?.updatedAt,
      delete: widget.delete,
      values: widget.delete
          ? {}
          : widget.templates
          ? {
              'role_id': roleId,
              'weekday_rule': monthly ? 'monthly_day' : 'every_weekday',
              'monthly_day': monthly ? int.parse(day.text) : null,
              'weekdays': monthly ? null : (weekdays.toList()..sort()),
              'start_time': start.text,
              'end_time': end.text,
              'capacity': int.parse(capacity.text),
              'is_active': active,
            }
          : {
              'code': code.text.trim(),
              'name': name.text.trim(),
              'max_doctors': int.parse(capacity.text),
              'display_order': int.parse(order.text),
              'is_active': active,
              'print_in_report': printVisible,
              'color_key': colorKey,
              'allowed_ranks': ranks.map(databaseEnum).toList(),
              'required_capabilities': capabilities.map(databaseEnum).toList(),
            },
    );
    setState(() => busy = true);
    try {
      await widget.service.saveConfiguration(pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = directoryFailureText(e);
          rejected = e is! DirectoryFailure || !e.outcomeUnknown;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String label,
    TextEditingController c, {
    bool integer = false,
    bool time = false,
    int? max,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(
        labelText: AdminStrings.of(context).text(label),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return AdminStrings.of(context).text('Required');
        }
        if (integer &&
            (int.tryParse(v) == null ||
                (label != 'Report order' && int.parse(v) < 1) ||
                (max != null && int.parse(v) > max))) {
          return AdminStrings.of(context).text('Enter a valid whole number.');
        }
        if (time && !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(v)) {
          return 'HH:mm';
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = AdminStrings.of(context);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: AdminText(
          widget.delete
              ? 'Delete'
              : widget.templates
              ? 'Template'
              : 'Role',
        ),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.delete)
                  CheckboxListTile(
                    value: acknowledged,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => acknowledged = v!),
                    title: const AdminText(
                      'Confirm deletion. Existing roster facts will remain unchanged.',
                    ),
                  )
                else
                  AbsorbPointer(
                    absorbing: busy || pending != null,
                    child: Form(
                      key: form,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!widget.templates) ...[
                            field('Code', code),
                            field('Display name', name),
                            field('Report order', order, integer: true),
                            DropdownButtonFormField<String>(
                              key: const ValueKey('role-color-field'),
                              initialValue: colorKey ?? '',
                              decoration: InputDecoration(
                                labelText: s.text('Color'),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: AdminText(
                                    'Automatic (stable by role)',
                                  ),
                                ),
                                for (final color in rolePalette)
                                  DropdownMenuItem(
                                    value: color.key,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 16,
                                          color: roleDisplayColor(
                                            context,
                                            widget.role?.id ?? '',
                                            color.key,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        AdminText(color.label),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => colorKey = v == '' ? null : v),
                            ),
                            CheckboxListTile(
                              title: const AdminText('Visible in reports'),
                              value: printVisible,
                              onChanged: (v) =>
                                  setState(() => printVisible = v!),
                            ),
                            const AdminText('Allowed ranks (empty means all)'),
                            Wrap(
                              children: [
                                for (final r in DoctorRank.values)
                                  FilterChip(
                                    label: AdminText(r.name),
                                    selected: ranks.contains(r),
                                    onSelected: (v) => setState(
                                      () => v ? ranks.add(r) : ranks.remove(r),
                                    ),
                                  ),
                              ],
                            ),
                            const AdminText('Required capabilities'),
                            Wrap(
                              children: [
                                for (final c in Capability.values)
                                  FilterChip(
                                    label: AdminText(c.name),
                                    selected: capabilities.contains(c),
                                    onSelected: (v) => setState(
                                      () => v
                                          ? capabilities.add(c)
                                          : capabilities.remove(c),
                                    ),
                                  ),
                              ],
                            ),
                          ] else ...[
                            DropdownButtonFormField<String>(
                              initialValue: roleId,
                              decoration: InputDecoration(
                                labelText: s.text('Role'),
                              ),
                              items: [
                                for (final r in widget.data.roles)
                                  DropdownMenuItem(
                                    value: r.id,
                                    child: Text('${r.code} | ${r.name}'),
                                  ),
                              ],
                              onChanged: (v) => setState(() => roleId = v),
                            ),
                            SwitchListTile(
                              title: const AdminText('Monthly day'),
                              value: monthly,
                              onChanged: (v) => setState(() => monthly = v),
                            ),
                            if (monthly)
                              field('Day of month', day, integer: true, max: 31)
                            else
                              Wrap(
                                children: [
                                  for (var i = 1; i <= 7; i++)
                                    FilterChip(
                                      label: Text(
                                        (s.language == 'de'
                                            ? [
                                                'Mo',
                                                'Di',
                                                'Mi',
                                                'Do',
                                                'Fr',
                                                'Sa',
                                                'So',
                                              ]
                                            : [
                                                'Mon',
                                                'Tue',
                                                'Wed',
                                                'Thu',
                                                'Fri',
                                                'Sat',
                                                'Sun',
                                              ])[i - 1],
                                      ),
                                      selected: weekdays.contains(i),
                                      onSelected: (v) => setState(
                                        () => v
                                            ? weekdays.add(i)
                                            : weekdays.remove(i),
                                      ),
                                    ),
                                ],
                              ),
                            field(
                              'Start time (Europe/Vienna)',
                              start,
                              time: true,
                            ),
                            field('End time (Europe/Vienna)', end, time: true),
                          ],
                          field('Capacity', capacity, integer: true),
                          SwitchListTile(
                            title: const AdminText('Active'),
                            value: active,
                            onChanged: (v) => setState(() => active = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (error != null) AdminText(error!),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const AdminText('Close'),
          ),
          FilledButton(
            onPressed: busy || rejected || (widget.delete && !acknowledged)
                ? null
                : save,
            child: AdminText(
              pending != null
                  ? 'Retry same request'
                  : widget.delete
                  ? 'Delete'
                  : 'Save',
            ),
          ),
        ],
      ),
    );
  }
}
