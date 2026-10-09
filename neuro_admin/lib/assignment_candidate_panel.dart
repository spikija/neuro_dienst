import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

typedef PreviewServiceFactory =
    AssignmentValidationService Function(RosterSnapshot snapshot);

/// Presentation and async input invalidation only; validation lives in the shared package.
class AssignmentCandidatePanel extends StatefulWidget {
  final RosterSnapshot snapshot;
  final StoredRole role;
  final Set<HospitalDate> dates;
  final String? physicianId;
  final ValueChanged<String> onPhysician;
  final VoidCallback onCancel;
  final PreviewServiceFactory? serviceFactory;
  final AssignmentMutationService? mutations;
  final ValueChanged<bool>? onBusyChanged;
  final Future<void> Function(bool stale)? onReload;
  final void Function(MonthAssignability validity, bool preselect)?
  onAssignability;
  final VoidCallback? onValidationFailed;
  const AssignmentCandidatePanel({
    super.key,
    required this.snapshot,
    required this.role,
    required this.dates,
    required this.physicianId,
    required this.onPhysician,
    required this.onCancel,
    this.serviceFactory,
    this.mutations,
    this.onBusyChanged,
    this.onReload,
    this.onAssignability,
    this.onValidationFailed,
  });

  @override
  State<AssignmentCandidatePanel> createState() =>
      _AssignmentCandidatePanelState();
}

enum _Filter { all, eligible, available }

class _AssignmentCandidatePanelState extends State<AssignmentCandidatePanel> {
  final WorkloadReadService _workload = const RecordedWorkloadService();
  Map<String, AssignmentPreview> _previews = {};
  _Filter _filter = _Filter.all;
  Timer? _timer;
  int _generation = 0;
  bool _loading = true;
  String? _error;
  bool _authorized = false;
  bool _applying = false;
  AssignmentCommitRequest? _pending;

  @override
  void initState() {
    super.initState();
    _invalidate();
  }

  @override
  void didUpdateWidget(AssignmentCandidatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot) ||
        oldWidget.role.id != widget.role.id ||
        oldWidget.physicianId != widget.physicianId ||
        oldWidget.serviceFactory != widget.serviceFactory) {
      _invalidate();
    } else if (!setEquals(oldWidget.dates, widget.dates)) {
      _pending = null;
    }
  }

  void _invalidate() {
    _pending = null;
    _authorized = false;
    final generation = ++_generation;
    _timer?.cancel();
    _previews = {};
    _error = null;
    _loading = true;
    // Clear immediately; debounce work while the calendar drag is changing dates.
    _timer = Timer(const Duration(milliseconds: 60), () => _load(generation));
  }

  Future<void> _load(int generation) async {
    try {
      final service =
          (widget.serviceFactory ?? SnapshotAssignmentValidationService.new)(
            widget.snapshot,
          );
      final month = widget.snapshot.month;
      final dates = [
        for (
          var day = 1;
          day <= DateTime.utc(month.year, month.month + 1, 0).day;
          day++
        )
          HospitalDate(month.year, month.month, day),
      ];
      final doctors = widget.snapshot.doctors;
      final previews = await Future.wait([
        for (final doctor in doctors)
          service.preview(
            AssignmentValidationRequest(
              roster: widget.snapshot.contentVersion == null
                  ? RosterVersion.unversioned(widget.snapshot.month.id)
                  : RosterVersion(
                      widget.snapshot.month.id,
                      widget.snapshot.contentVersion!,
                    ),
              roleId: widget.role.id,
              physicianId: doctor.id,
              targets: dates.map(AssignmentTarget.new),
            ),
          ),
      ]);
      final authorized = await widget.mutations?.canApply() ?? false;
      if (!mounted || generation != _generation) return;
      setState(() {
        _previews = {
          for (var i = 0; i < doctors.length; i++) doctors[i].id: previews[i],
        };
        _loading = false;
        _authorized = authorized;
      });
      _publishAssignability(true);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error =
            'Preview could not be calculated. Reload the roster and retry.';
      });
      widget.onValidationFailed?.call();
    }
  }

  void _publishAssignability(bool preselect) {
    final preview = _previews[widget.physicianId];
    if (preview != null) {
      widget.onAssignability?.call(MonthAssignability(preview), preselect);
    }
  }

  Future<void> _apply(AssignmentPreview preview) async {
    if (_applying ||
        !_authorized ||
        !preview.allValid ||
        widget.mutations == null ||
        widget.snapshot.contentVersion == null) {
      return;
    }
    final generation = _generation;
    final selectedDates = Set<HospitalDate>.of(widget.dates);
    final physicianId = widget.physicianId;
    final mutations = widget.mutations!;
    final onBusyChanged = widget.onBusyChanged;
    setState(() {
      _applying = true;
      _error = null;
    });
    onBusyChanged?.call(true);
    try {
      if (_pending == null) {
        final reason = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _AssignmentConfirmation(
            preview: preview,
            physicianName: widget.snapshot.doctors
                .firstWhere((d) => d.id == physicianId)
                .fullName,
            roleName: '${widget.role.code}: ${widget.role.name}',
            requiresReason: widget.snapshot.month.phase == RosterPhase.locked,
          ),
        );
        if (!mounted ||
            reason == null ||
            generation != _generation ||
            !setEquals(selectedDates, widget.dates) ||
            physicianId != widget.physicianId) {
          return;
        }
        final old = preview.request;
        final intent = AssignmentValidationRequest(
          roster: old.roster,
          roleId: old.roleId,
          physicianId: old.physicianId,
          targets: old.targets,
          correctionReason: reason.trim().isEmpty ? null : reason.trim(),
        );
        _pending = AssignmentCommitRequest.atomicApply(
          AdminWriteIntent.create(reason: intent.correctionReason),
          AssignmentPreview(request: intent, results: preview.results),
        );
      }
      // Access may have changed while the confirmation dialog was open.
      final operation = _pending!;
      if (!await mutations.canApply()) {
        if (mounted) {
          setState(() {
            _authorized = false;
            _error =
                'Administrator MFA access could not be verified. Sign in again.';
          });
        }
        return;
      }
      if (!mounted ||
          generation != _generation ||
          !setEquals(selectedDates, widget.dates) ||
          physicianId != widget.physicianId ||
          !identical(operation, _pending)) {
        return;
      }
      await mutations.bulkAssign(operation);
      _pending = null;
      if (mounted) await widget.onReload?.call(false);
    } on AssignmentMutationFailure catch (error) {
      if (!mounted) return;
      if (!error.outcomeUnknown) _pending = null;
      if (error.code == 'staleVersion') {
        await widget.onReload?.call(true);
      } else {
        setState(() {
          _error = error.outcomeUnknown
              ? 'The response was not received. The operation may have succeeded. Retry the same request to check safely.'
              : 'Server rejected the operation (${error.code}). No assignments were added.';
          if (error.results.isNotEmpty) {
            final month = _previews[physicianId!]!;
            final byDate = {
              for (final result in error.results) result.date: result,
            };
            _previews[physicianId] = AssignmentPreview(
              request: month.request,
              results: month.results.map((r) => byDate[r.date] ?? r),
            );
          }
          if (error.code == 'unauthorized' || error.code == 'mfaRequired') {
            _authorized = false;
          }
        });
        _publishAssignability(false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Operation outcome is unknown. Retry the same request to check safely.';
        });
      }
    } finally {
      if (mounted) setState(() => _applying = false);
      onBusyChanged?.call(false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _generation++;
    super.dispose();
  }

  bool _eligible(AssignmentPreview preview) => !preview.results.any(
    (result) => result.errors.any(
      (error) => {
        AssignmentErrorCode.physicianNotFound,
        AssignmentErrorCode.inactivePhysician,
        AssignmentErrorCode.physicianNotEligible,
        AssignmentErrorCode.missingCapability,
        AssignmentErrorCode.roleInactive,
        AssignmentErrorCode.validationUnavailable,
      }.contains(error.code),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final monthPreview = _previews[widget.physicianId];
    final selected = monthPreview == null
        ? null
        : MonthAssignability(monthPreview).selectedPreview(widget.dates);
    final doctors = widget.snapshot.doctors.where((doctor) {
      final preview = _previews[doctor.id];
      return _filter == _Filter.all ||
          preview != null &&
              (_filter == _Filter.eligible
                  ? _eligible(preview)
                  : preview.proposedAdditions > 0);
    }).toList();
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Physician candidates',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel preview',
                  onPressed: _applying ? null : widget.onCancel,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              '${widget.role.code}: ${widget.role.name}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final filter in _Filter.values)
                  ChoiceChip(
                    label: Text(switch (filter) {
                      _Filter.all => 'All',
                      _Filter.eligible => 'Eligible',
                      _Filter.available => 'Available',
                    }),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Expanded(
              child: ListView(
                key: const ValueKey('physician-candidates'),
                children: [
                  if (doctors.isEmpty && !_loading)
                    const Text('No physicians match this filter.'),
                  for (final doctor in doctors)
                    _candidate(doctor, _previews[doctor.id]),
                ],
              ),
            ),
            if (selected != null) ...[
              const Divider(),
              Expanded(
                child: AssignmentPreviewDetails(
                  preview: selected,
                  physicianName: widget.snapshot.doctors
                      .firstWhere((d) => d.id == widget.physicianId)
                      .fullName,
                ),
              ),
            ] else
              Text(
                widget.physicianId == null
                    ? 'Select a physician to check the whole month.'
                    : 'Select an assignable date to preview additions.',
              ),
            const SizedBox(height: 6),
            Text(
              widget.mutations == null
                  ? 'Preview only - assignment writes are not enabled yet.'
                  : widget.snapshot.contentVersion == null
                  ? 'Preview only: backend versioning migration is required.'
                  : 'All dates must pass server validation; no partial assignments.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Tooltip(
              message: !_authorized
                  ? 'Verified administrator MFA session required'
                  : 'Confirm all selected dates',
              child: FilledButton(
                onPressed:
                    !_loading &&
                        !_applying &&
                        _authorized &&
                        selected?.allValid == true &&
                        widget.snapshot.contentVersion != null &&
                        widget.snapshot.month.phase != RosterPhase.published
                    ? () => _apply(selected!)
                    : null,
                child: Text(
                  _applying
                      ? 'Applying...'
                      : _pending != null
                      ? 'Retry same request'
                      : 'Apply assignments',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidate(Doctor doctor, AssignmentPreview? preview) {
    final snapshot = widget.snapshot;
    final history = _workload.forPhysician(
      snapshot,
      doctor,
      WorkloadWindow(snapshot.historyStart, snapshot.historyEnd),
    );
    final current = _workload.forPhysician(
      snapshot,
      doctor,
      WorkloadWindow(
        DateTime.utc(snapshot.month.year, snapshot.month.month),
        DateTime.utc(snapshot.month.year, snapshot.month.month + 1),
      ),
    );
    final text = preview == null
        ? 'Checking...'
        : preview.blockedCount > 0
        ? '${preview.proposedAdditions}/${preview.results.length} dates available; ${preview.blockedCount} blocked'
        : preview.warningCount > 0
        ? 'Eligible with warnings'
        : 'Eligible and available';
    final icon = preview == null
        ? Icons.hourglass_empty
        : preview.blockedCount > 0
        ? Icons.block
        : preview.warningCount > 0
        ? Icons.warning_amber
        : Icons.check_circle_outline;
    final reason = preview?.results
        .expand((r) => r.errors)
        .firstOrNull
        ?.message;
    return ListTile(
      key: ValueKey('candidate-${doctor.id}'),
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      selected: widget.physicianId == doctor.id,
      title: Text(
        '${doctor.fullName}${snapshot.inactiveDoctorIds.contains(doctor.id) ? ' (inactive)' : ''}',
      ),
      onTap: _applying
          ? null
          : () {
              _pending = null;
              widget.onPhysician(doctor.id);
            },
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rank: ${doctor.rank.name}'),
          Text(
            'Capabilities: ${doctor.capabilities.isEmpty ? 'None' : doctor.capabilities.map((c) => c.name).join(', ')}',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 4),
              Expanded(child: Text(text)),
            ],
          ),
          if (reason != null)
            Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            '90 days: 24h ${history.recordedDuty24Days} (weekend ${history.recordedWeekendDuty24Days}) | station ${history.daysFor(WorkloadCategory.station)} | ambulance ${history.daysFor(WorkloadCategory.ambulance)} | science ${history.daysFor(WorkloadCategory.science)}',
          ),
          Text(
            'Current month: ${current.assignments} assignments / ${current.assignedDays} days; ${current.confirmed} confirmed / ${current.provisional} provisional',
          ),
        ],
      ),
    );
  }
}

class AssignmentPreviewDetails extends StatelessWidget {
  final AssignmentPreview preview;
  final String physicianName;
  const AssignmentPreviewDetails({
    super.key,
    required this.preview,
    required this.physicianName,
  });

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('assignment-preview-details'),
    children: [
      Text(
        'Assignment preview - ${preview.results.length} target dates',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(
        '${preview.validCount} valid | ${preview.warningCount} valid with warnings | ${preview.blockedCount} blocked',
      ),
      Text('${preview.proposedAdditions} proposed additions; no replacements'),
      for (final result in preview.results)
        Padding(
          key: ValueKey('preview-${result.date}'),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.date}: ${!result.isValid
                    ? 'Blocked'
                    : result.warnings.isNotEmpty
                    ? 'Valid with warnings'
                    : 'Valid'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final slot in result.matchingSlots)
                Text(
                  '${slot.role.code} ${_time(slot.startsAt)} - ${_time(slot.endsAt)}; capacity ${slot.capacity}',
                ),
              Text(
                'Current: ${result.currentAssignments.isEmpty ? 'Unassigned' : result.currentAssignments.map((a) => '${a.doctor.fullName} (${a.state.name})').join(', ')}',
              ),
              Text('Proposed: $physicianName'),
              for (final error in result.errors)
                Text(
                  '${error.code.name}: ${error.message}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final warning in result.warnings)
                Text('Warning: ${warning.message}'),
            ],
          ),
        ),
    ],
  );
}

String _time(DateTime instant) {
  final time = ViennaSchedulingTime.localTime(instant);
  return '${HospitalDate.fromCalendarComponents(time)} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class _AssignmentConfirmation extends StatefulWidget {
  final AssignmentPreview preview;
  final String physicianName;
  final String roleName;
  final bool requiresReason;
  const _AssignmentConfirmation({
    required this.preview,
    required this.physicianName,
    required this.roleName,
    required this.requiresReason,
  });
  @override
  State<_AssignmentConfirmation> createState() =>
      _AssignmentConfirmationState();
}

class _AssignmentConfirmationState extends State<_AssignmentConfirmation> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm assignments'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.physicianName),
            Text(widget.roleName),
            Text('${widget.preview.results.length} dates; all-or-nothing'),
            Text('${widget.preview.warningCount} selected dates with warnings'),
            Text(
              widget.preview.results.map((r) => r.date.toString()).join(', '),
            ),
            if (widget.requiresReason)
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Correction reason (required)',
                ),
                onChanged: (_) => setState(() {}),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: widget.requiresReason && _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text),
        child: const Text('Confirm and apply'),
      ),
    ],
  );
}
