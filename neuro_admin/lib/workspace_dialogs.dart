import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

String _wallTime(DateTime instant) {
  final wall = ViennaSchedulingTime.localTime(instant);
  return '${wall.hour.toString().padLeft(2, '0')}:${wall.minute.toString().padLeft(2, '0')}';
}

String _generationBlocker(String code) => switch (code) {
  'monthExists' =>
    'A roster already exists. Open that month and use draft regeneration.',
  'draftRequired' =>
    'Only a draft roster can be regenerated. Published history is protected.',
  'assignmentLoss' =>
    'Occupied slots would be removed. Reconcile those assignments before regeneration.',
  'ambiguousOrMissingWallTime' =>
    'A template time falls in a daylight-saving gap or repeated hour. Review the template.',
  'invalidMonthlyDay' => 'A monthly template has no valid day of month.',
  'rosterNotFound' => 'The original roster is no longer available. Reload.',
  _ => 'Generation is blocked. Reload and review the roster configuration.',
};

class GenerationDialog extends StatefulWidget {
  final RosterGenerationService service;
  final RosterSnapshot? existing;
  const GenerationDialog({super.key, required this.service, this.existing});
  @override
  State<GenerationDialog> createState() => _GenerationDialogState();
}

class _GenerationDialogState extends State<GenerationDialog> {
  late final year = TextEditingController(
    text: '${widget.existing?.month.year ?? DateTime.now().year}',
  );
  late int month = widget.existing?.month.month ?? DateTime.now().month;
  RosterGenerationPlan? plan;
  RosterGenerationCommitRequest? pending;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    year.dispose();
    super.dispose();
  }

  Future<void> preview() async {
    setState(() {
      busy = true;
      error = null;
      plan = null;
    });
    try {
      final snapshot = widget.existing;
      final result = await widget.service.preview(
        RosterGenerationRequest(
          AdminWriteIntent.create(),
          year: int.parse(year.text),
          month: month,
          expectedConfigurationVersion: 'server-preview',
        ),
        existing: snapshot == null
            ? null
            : RosterRevision(
                version: RosterVersion(
                  snapshot.month.id,
                  snapshot.contentVersion!,
                ),
                year: snapshot.month.year,
                month: snapshot.month.month,
                revisionNumber: 1,
                phase: snapshot.month.phase,
                isCurrentPublished:
                    snapshot.month.phase == RosterPhase.published,
              ),
      );
      if (mounted) setState(() => plan = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is AssignmentMutationFailure
              ? 'Preview unavailable (${e.code}). Check the workspace migration and access.'
              : 'Enter a valid year (2000–2100) and reload the roster if needed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      pending ??= RosterGenerationCommitRequest(plan!, now: DateTime.now());
      final result = await widget.service.apply(pending!);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          final unknown = e is AssignmentMutationFailure && e.outcomeUnknown;
          error = unknown
              ? 'Response uncertain. Retry the same request, or close and reload before starting another operation.'
              : 'Generation rejected. Reload the preview (${e is AssignmentMutationFailure ? e.code : 'expired preview'}).';
          if (!unknown) {
            pending = null;
            plan = null;
          }
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
      title: Text(
        widget.existing == null
            ? 'Create month roster'
            : 'Regenerate draft roster',
      ),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.existing == null)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: year,
                        enabled: !busy && pending == null,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Year'),
                        onChanged: (_) => setState(() => plan = null),
                      ),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<int>(
                      value: month,
                      onChanged: busy || pending != null
                          ? null
                          : (v) => setState(() {
                              month = v!;
                              plan = null;
                            }),
                      items: [
                        for (var n = 1; n <= 12; n++)
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                    ),
                  ],
                ),
              if (plan != null) ...[
                Text('${plan!.request.year}-${plan!.request.month} · DRAFT'),
                Text(
                  '${plan!.days.length} calendar days · ${plan!.days.where((d) => !d.isWeekend).length} weekdays · ${plan!.days.where((d) => d.isPublicHoliday).length} Austrian holidays',
                ),
                Text(
                  '${plan!.slots.where((s) => s.existingSlotId == null).length} slots to add · ${plan!.removedSlotIds.length} to remove · ${plan!.impactedAssignmentIds.length} assignments affected',
                ),
                const SizedBox(height: 8),
                for (final label
                    in plan!.slots
                        .map(
                          (s) =>
                              '${s.roleLabel ?? 'Duty'} · ${_wallTime(s.startsAt)}–${_wallTime(s.endsAt)}',
                        )
                        .toSet())
                  Text(label),
                for (final d in plan!.days.where((d) => d.isPublicHoliday))
                  Text(
                    '${HospitalDate.fromCalendarComponents(d.date)}: ${d.publicHolidayName}',
                  ),
                const Text(
                  'Weekday templates also create holiday slots. Existing assignments are preserved; destructive regeneration is blocked.',
                ),
                for (final blocker in plan!.blockers)
                  Text(
                    _generationBlocker(blocker),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: busy || pending != null ? null : preview,
          child: const Text('Preview'),
        ),
        FilledButton(
          onPressed: busy || plan == null || plan!.blockers.isNotEmpty
              ? null
              : apply,
          child: Text(
            pending != null
                ? 'Retry same request'
                : widget.existing == null
                ? 'Create roster'
                : 'Regenerate draft',
          ),
        ),
      ],
    ),
  );
}

class RemovalDialog extends StatefulWidget {
  final AssignmentRemovalPreview preview;
  final AssignmentRemovalService service;
  const RemovalDialog({
    super.key,
    required this.preview,
    required this.service,
  });
  @override
  State<RemovalDialog> createState() => _RemovalDialogState();
}

class _RemovalDialogState extends State<RemovalDialog> {
  final reason = TextEditingController();
  AdminWriteIntent? pending;
  bool busy = false, confirmed = false, rejected = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> apply() async {
    setState(() => busy = true);
    try {
      pending ??= AdminWriteIntent.create(reason: reason.text.trim());
      await widget.service.removeDates(widget.preview, pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          final unknown = e is AssignmentMutationFailure && e.outcomeUnknown;
          error = unknown
              ? 'Response uncertain. Retry the same request, or close and reload before another removal.'
              : 'Removal rejected (${e is AssignmentMutationFailure ? e.code : 'invalid request'}). Close and reload.';
          rejected = !unknown;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final locked = p.snapshot.month.phase == RosterPhase.locked;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          'Remove ${p.assignments.length} assignments across ${p.dates.length} selected days?',
        ),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.scope == RemovalScope.all
                      ? 'ALL ROLES on selected days'
                      : 'Selected role only',
                ),
                for (final a in p.assignments)
                  Text(
                    '${HospitalDate.fromCalendarComponents(a.duty.date)} · ${a.duty.role.name} · ${a.doctor.fullName} (${a.state.name})',
                  ),
                for (final d in p.noOpDates)
                  Text('$d: no matching assignments (no change)'),
                if (locked)
                  TextField(
                    controller: reason,
                    enabled: pending == null && !busy,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Correction reason (required)',
                    ),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: busy || pending != null
                      ? null
                      : (v) => setState(() => confirmed = v!),
                  title: const Text(
                    'I confirm removal of exactly the assignments listed above.',
                  ),
                ),
                if (error != null) Text(error!),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed:
                busy ||
                    rejected ||
                    !confirmed ||
                    p.assignments.isEmpty ||
                    (locked && reason.text.trim().isEmpty)
                ? null
                : apply,
            child: Text(
              pending != null ? 'Retry same request' : 'Remove assignments',
            ),
          ),
        ],
      ),
    );
  }
}
