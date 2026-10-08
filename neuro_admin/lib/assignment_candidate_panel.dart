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
  const AssignmentCandidatePanel({
    super.key,
    required this.snapshot,
    required this.role,
    required this.dates,
    required this.physicianId,
    required this.onPhysician,
    required this.onCancel,
    this.serviceFactory,
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
        !setEquals(oldWidget.dates, widget.dates) ||
        oldWidget.serviceFactory != widget.serviceFactory) {
      _invalidate();
    }
  }

  void _invalidate() {
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
      final dates = widget.dates.toList()..sort();
      final doctors = widget.snapshot.doctors;
      final previews = await Future.wait([
        for (final doctor in doctors)
          service.preview(
            AssignmentValidationRequest(
              roster: RosterVersion.unversioned(widget.snapshot.month.id),
              roleId: widget.role.id,
              physicianId: doctor.id,
              targets: dates.map(AssignmentTarget.new),
            ),
          ),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _previews = {
          for (var i = 0; i < doctors.length; i++) doctors[i].id: previews[i],
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error =
            'Preview could not be calculated. Reload the roster and retry.';
      });
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
    final selected = _previews[widget.physicianId];
    final doctors = widget.snapshot.doctors.where((doctor) {
      final preview = _previews[doctor.id];
      return _filter == _Filter.all ||
          preview != null &&
              (_filter == _Filter.eligible
                  ? _eligible(preview)
                  : preview.allValid);
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
                  onPressed: widget.onCancel,
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
              const Text('Select a physician to inspect every selected date.'),
            const SizedBox(height: 6),
            const Text(
              'Preview only - assignment writes are not enabled yet.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Tooltip(
              message: 'Backend writes are not enabled',
              child: FilledButton(
                onPressed: null,
                child: Text('Apply assignments'),
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
      onTap: () => widget.onPhysician(doctor.id),
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
