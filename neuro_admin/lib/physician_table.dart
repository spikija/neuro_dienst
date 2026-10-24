import 'package:flutter/material.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';

import 'localization.dart';

/// Shared directory for both the workload and assignment candidate views.
class PhysicianTable extends StatefulWidget {
  final RosterSnapshot snapshot;
  final List<Doctor> doctors;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final Widget Function(Doctor doctor) detailsBuilder;

  const PhysicianTable({
    super.key,
    required this.snapshot,
    required this.doctors,
    required this.selectedId,
    required this.onSelected,
    required this.detailsBuilder,
  });

  @override
  State<PhysicianTable> createState() => _PhysicianTableState();
}

class _PhysicianTableState extends State<PhysicianTable> {
  final _search = TextEditingController();
  int _sortColumn = 0;
  bool _ascending = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _qualifications(Doctor doctor) {
    final strings = AdminStrings.of(context);
    final capabilities =
        doctor.capabilities.map((c) => strings.text(c.name)).toList()..sort();
    return [strings.text(doctor.rank.name), ...capabilities].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final strings = AdminStrings.of(context);
    final month = widget.snapshot.month;
    final window = WorkloadWindow(
      DateTime.utc(month.year, month.month),
      DateTime.utc(month.year, month.month + 1),
    );
    final counts = {
      for (final doctor in widget.doctors)
        doctor.id: workloadFor(widget.snapshot, doctor, window).assignments,
    };
    final query = _search.text.trim().toLowerCase();
    final doctors =
        widget.doctors
            .where(
              (doctor) =>
                  !widget.snapshot.inactiveDoctorIds.contains(doctor.id) &&
                  !widget.snapshot.unknownActivityDoctorIds.contains(
                    doctor.id,
                  ) &&
                  doctor.fullName.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) {
            var order = switch (_sortColumn) {
              1 => _qualifications(
                a,
              ).toLowerCase().compareTo(_qualifications(b).toLowerCase()),
              2 => counts[a.id]!.compareTo(counts[b.id]!),
              _ => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
            };
            if (order == 0) {
              order = a.fullName.toLowerCase().compareTo(
                b.fullName.toLowerCase(),
              );
            }
            if (order == 0) order = a.id.compareTo(b.id);
            return _ascending ? order : -order;
          });
    final header = <Widget>[
      TextField(
        key: const ValueKey('physician-search'),
        controller: _search,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          if (doctors.length == 1) widget.onSelected?.call(doctors.single.id);
        },
        decoration: InputDecoration(
          isDense: true,
          labelText: strings.text('Search physicians'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: strings.text('Clear search'),
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(_search.clear),
                ),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      _columns([
        _heading('Name', 0),
        _heading('Rank / qualifications', 1),
        _heading('Slots', 2),
      ]),
      const Divider(height: 1),
    ];
    final rows = <Widget>[
      if (doctors.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: AdminText('No physicians match this filter.'),
        ),
      for (final doctor in doctors)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: widget.selectedId == doctor.id
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Colors.transparent,
              child: InkWell(
                key: ValueKey('candidate-${doctor.id}'),
                onTap: widget.onSelected == null
                    ? null
                    : () => widget.onSelected!(doctor.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _columns([
                    Row(
                      children: [
                        Icon(
                          widget.selectedId == doctor.id
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 16,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            widget.snapshot.inactiveDoctorIds.contains(
                                  doctor.id,
                                )
                                ? strings.text('{name} (inactive)', {
                                    'name': doctor.fullName,
                                  })
                                : doctor.fullName,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _qualifications(doctor),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Tooltip(
                      message: strings.text(
                        'Assignments in selected month (confirmed and provisional)',
                      ),
                      child: Text(
                        '${counts[doctor.id]}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (widget.selectedId == doctor.id)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: widget.detailsBuilder(doctor),
              ),
            const Divider(height: 1),
          ],
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // A short resized window can scroll the controls with the rows.
        final compact = constraints.maxHeight < 180;
        final list = ListView(
          key: const ValueKey('physician-candidates'),
          children: [if (compact) ...header, ...rows],
        );
        return compact
            ? list
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...header,
                  Expanded(child: list),
                ],
              );
      },
    );
  }

  Widget _columns(List<Widget> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(flex: 4, child: cells[0]),
      const SizedBox(width: 6),
      Expanded(flex: 4, child: cells[1]),
      const SizedBox(width: 6),
      Expanded(flex: 2, child: cells[2]),
    ],
  );

  Widget _heading(String label, int column) => Tooltip(
    message: AdminStrings.of(context).text(
      _sortColumn == column && _ascending
          ? 'Sort descending'
          : 'Sort ascending',
    ),
    child: InkWell(
      key: ValueKey('physician-sort-$column'),
      onTap: () => setState(() {
        _ascending = _sortColumn == column ? !_ascending : true;
        _sortColumn = column;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: AdminText(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              _sortColumn == column
                  ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 14,
            ),
          ],
        ),
      ),
    ),
  );
}
