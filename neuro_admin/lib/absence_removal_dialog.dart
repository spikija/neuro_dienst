import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';

import 'localization.dart';

class AbsenceRemovalDialog extends StatefulWidget {
  final AbsenceDayRemovalService service;
  final AbsenceDayRemovalRequest request;
  final String physicianName;
  const AbsenceRemovalDialog({
    super.key,
    required this.service,
    required this.request,
    required this.physicianName,
  });

  @override
  State<AbsenceRemovalDialog> createState() => _AbsenceRemovalDialogState();
}

class _AbsenceRemovalDialogState extends State<AbsenceRemovalDialog> {
  String get _periodLabel => AvailabilityPeriod(
    start: widget.request.date.asDateOnlyUtc,
    end: widget.request.date.asDateOnlyUtc,
    type: widget.request.type,
  ).label;

  bool _busy = false;
  bool _uncertain = false;
  bool _reloadRequired = false;
  String? _error;

  Future<void> _remove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.removeDay(widget.request);
      if (mounted) Navigator.pop(context, true);
    } on AssignmentMutationFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _uncertain = error.outcomeUnknown;
        _reloadRequired = {'staleVersion', 'noAbsence'}.contains(error.code);
        _error = _uncertain
            ? 'The removal outcome is unknown. Retry the same request to check safely.'
            : switch (error.code) {
                'staleVersion' || 'noAbsence' =>
                  'Absence data changed. Reload the roster before trying again.',
                'absenceMigrationRequired' =>
                  'Absence removal requires the backend migration.',
                'unauthorized' ||
                'mfaRequired' => 'Verified administrator MFA session required',
                _ => 'Absence could not be removed. Reload and try again.',
              };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uncertain = true;
        _error =
            'The removal outcome is unknown. Retry the same request to check safely.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: AdminText(
        'Remove {type}',
        args: {'type': AdminStrings.of(context).text(_periodLabel)},
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminText(
            'Remove {type} for {name} on {date}?',
            args: {
              'name': widget.physicianName,
              'type': AdminStrings.of(context).text(_periodLabel),
              'date':
                  '${widget.request.date.day}.${widget.request.date.month}.${widget.request.date.year}',
            },
          ),
          const SizedBox(height: 8),
          const AdminText(
            'Only this entry and date are removed. Other absences, dates and duties are retained.',
          ),
          if (widget.request.type == AvailabilityType.duty24) ...[
            const SizedBox(height: 8),
            const AdminText(
              'Post-duty markers are separate entries and can be removed on their own dates.',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AdminText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, _reloadRequired || _uncertain),
          child: AdminText(_reloadRequired || _uncertain ? 'Reload' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _reloadRequired ? null : _remove,
          child: AdminText(
            _busy
                ? 'Removing...'
                : _uncertain
                ? 'Retry same request'
                : 'Remove entry',
          ),
        ),
      ],
    ),
  );
}
