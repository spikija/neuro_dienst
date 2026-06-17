import 'package:flutter/material.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_app/extensions/time_formatting.dart';
import 'package:neuro_app/l10n/app_language.dart';
import 'package:neuro_app/l10n/app_localizations.dart';
import 'package:neuro_app/services/supabase_bootstrap.dart';
import 'package:neuro_app/services/supabase_roster_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/month_day_card.dart';
import 'admin_home_screen.dart';
import 'calendar_export_screen.dart';
import 'day_screen.dart';
import 'doctor_profile_screen.dart';
import 'doctor_selector_screen.dart';
import 'mfa_screen.dart';
import 'month_report_picker_screen.dart';
import 'month_report_screen.dart';
import 'vacation_import_screen.dart';

class MonthScreen extends StatefulWidget {
  final RosterMonth roster;
  final Doctor currentDoctor;
  final ValueChanged<Doctor> onDoctorChanged;
  final ValueChanged<Doctor> onDoctorUpdated;
  final VoidCallback? onAdminClosed;
  final ValueChanged<DateTime>? onVisibleMonthChanged;
  final List<Doctor> doctors;
  final bool showAdmin;
  final String? signedInEmail;
  final AppLanguage language;
  final ValueChanged<AppLanguage>? onLanguageChanged;
  final bool isDarkMode;
  final VoidCallback? onToggleDarkMode;

  const MonthScreen({
    super.key,
    required this.roster,
    required this.currentDoctor,
    required this.doctors,
    required this.onDoctorChanged,
    required this.onDoctorUpdated,
    this.onAdminClosed,
    this.onVisibleMonthChanged,
    this.showAdmin = false,
    this.signedInEmail,
    this.language = AppLanguage.english,
    this.onLanguageChanged,
    this.isDarkMode = false,
    this.onToggleDarkMode,
  });

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  static const int _weekdayColumns = 5;
  static const double _gridSpacing = 6;
  static const double _gridPadding = 6;
  static const double _weekendColumnWidthFactor = 0.52;

  late RosterMonth currentRoster;
  final Set<String> _selectedDateKeys = {};
  int? _pointerDownIndex;
  bool _isRangeSelecting = false;
  String? _statusMessage;
  bool _editorMode = false;
  Doctor? _editorDoctor;
  SlotKind? _editorSlotKind;
  late List<Doctor> _doctors;

  int _myAssignmentsThisMonthCount() {
    final currentDoctor = _currentDoctorFromList();

    return currentRoster.days
        .expand((day) => day.assignments)
        .where((assignment) => assignment.doctor.id == currentDoctor.id)
        .length;
  }

  @override
  void initState() {
    super.initState();
    currentRoster = widget.roster;
    _doctors = widget.doctors;
    _editorDoctor = widget.currentDoctor;
  }

  @override
  void didUpdateWidget(covariant MonthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.doctors != widget.doctors) {
      _doctors = widget.doctors;
    }

    if (oldWidget.roster != widget.roster) {
      currentRoster = widget.roster;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentDoctor = _currentDoctorFromList();
    final monthView = MonthViewService().getMonthView(currentRoster);
    final conflictsByDate = _buildConflictsByDate();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${currentRoster.month}/${currentRoster.year}'),
            Text(
              widget.signedInEmail == null
                  ? currentDoctor.fullName
                  : '${currentDoctor.fullName} · ${widget.signedInEmail}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.t('previousMonth'),
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _openRelativeMonth(-1),
          ),
          IconButton(
            tooltip: l10n.t('nextMonth'),
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _openRelativeMonth(1),
          ),
          PopupMenuButton<_MonthMenuAction>(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _MonthMenuAction.switchDoctor,
                child: _MenuRow(
                  icon: Icons.switch_account,
                  label: 'Switch doctor',
                ),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.profile,
                child: _MenuRow(icon: Icons.person, label: 'Profile'),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.myAssignments,
                child: _MenuRow(
                  icon: Icons.list,
                  label: l10n.t('mySlotsThisMonth'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _MonthMenuAction.importVacation,
                child: _MenuRow(icon: Icons.download, label: 'Import vacation'),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.exportCalendar,
                child: _MenuRow(
                  icon: Icons.calendar_month,
                  label: 'Export calendar',
                ),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.monthlyReport,
                child: _MenuRow(
                  icon: Icons.print,
                  label: l10n.t('monthlyReport'),
                ),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.statistics,
                child: _MenuRow(
                  icon: Icons.bar_chart,
                  label: l10n.t('coverage'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _MonthMenuAction.toggleTheme,
                child: _MenuRow(
                  icon: widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  label: widget.isDarkMode
                      ? l10n.t('lightMode')
                      : l10n.t('darkMode'),
                ),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.languageEnglish,
                child: _MenuRow(
                  icon: Icons.language,
                  label: l10n.t('language.english'),
                  trailing: widget.language == AppLanguage.english
                      ? Icons.check
                      : null,
                ),
              ),
              PopupMenuItem(
                value: _MonthMenuAction.languageGerman,
                child: _MenuRow(
                  icon: Icons.language,
                  label: l10n.t('language.german'),
                  trailing: widget.language == AppLanguage.german
                      ? Icons.check
                      : null,
                ),
              ),
              if (SupabaseConfig.isConfigured && widget.showAdmin) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _MonthMenuAction.admin,
                  child: _MenuRow(
                    icon: Icons.admin_panel_settings,
                    label: l10n.t('admin'),
                  ),
                ),
              ],
              if (SupabaseConfig.isConfigured) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _MonthMenuAction.signOut,
                  child: _MenuRow(icon: Icons.logout, label: l10n.t('signOut')),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _buildModeBar(),
          Expanded(
            child: Stack(
              children: [
                _buildMonthGrid(monthView, conflictsByDate),
                if (_statusMessage != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: _selectedDateKeys.isNotEmpty ? 76 : 16,
                    child: _buildStatusStrip(),
                  ),
                if (_selectedDateKeys.isNotEmpty)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: _buildBulkActionBar(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeBar() {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
      child: Row(
        children: [
          SegmentedButton<bool>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.person),
                label: Text(l10n.t('doctor')),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.edit_calendar),
                label: Text(l10n.t('editor')),
              ),
            ],
            selected: {_editorMode},
            onSelectionChanged: (selection) {
              setState(() {
                _editorMode = selection.first;
                _editorDoctor ??= _currentDoctorFromList();
              });
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _editorMode
                  ? l10n.t('bulkEditorHint')
                  : l10n.fill('personalPlanning', {
                      'name': _currentDoctorFromList().firstName,
                    }),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(_MonthMenuAction action) async {
    switch (action) {
      case _MonthMenuAction.switchDoctor:
        await _openDoctorSelector();
      case _MonthMenuAction.profile:
        _openDoctorProfile();
      case _MonthMenuAction.myAssignments:
        _showMyAssignmentsDialog();
      case _MonthMenuAction.importVacation:
        await _openVacationImport();
      case _MonthMenuAction.exportCalendar:
        _openCalendarExport();
      case _MonthMenuAction.monthlyReport:
        _openMonthlyReport();
      case _MonthMenuAction.statistics:
        _showStatisticsDialog();
      case _MonthMenuAction.toggleTheme:
        widget.onToggleDarkMode?.call();
      case _MonthMenuAction.languageEnglish:
        widget.onLanguageChanged?.call(AppLanguage.english);
      case _MonthMenuAction.languageGerman:
        widget.onLanguageChanged?.call(AppLanguage.german);
      case _MonthMenuAction.admin:
        await _openAdmin();
      case _MonthMenuAction.signOut:
        await Supabase.instance.client.auth.signOut();
    }
  }

  Future<void> _openDoctorSelector() async {
    final selectedDoctor = await Navigator.push<Doctor>(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorSelectorScreen(doctors: _doctors),
      ),
    );

    if (!mounted || selectedDoctor == null) {
      return;
    }

    widget.onDoctorChanged(selectedDoctor);
  }

  void _openDoctorProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorProfileScreen(doctor: _currentDoctorFromList()),
      ),
    );
  }

  Future<void> _openVacationImport() async {
    final dates = await Navigator.push<List<DateTime>>(
      context,
      MaterialPageRoute(
        builder: (_) => VacationImportScreen(
          year: currentRoster.year,
          month: currentRoster.month,
        ),
      ),
    );

    if (!mounted || dates == null || dates.isEmpty) {
      return;
    }

    await _setVacationDatesFromImport(dates);
  }

  Widget _buildMonthGrid(
    List<MonthDayViewModel> monthView,
    Map<String, List<Conflict>> conflictsByDate,
  ) {
    final weekRows = _buildWeekRows();

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridMetrics = _gridMetricsForWidth(constraints.maxWidth);

        return Listener(
          onPointerDown: (event) {
            _handleGridPointerDown(event.localPosition, constraints.biggest);
          },
          onPointerMove: (event) {
            _handleGridPointerMove(event.localPosition, constraints.biggest);
          },
          onPointerUp: (event) {
            _handleGridPointerUp(event.localPosition, constraints.biggest);
          },
          onPointerCancel: (_) => _resetPointerSelection(),
          child: Padding(
            padding: const EdgeInsets.all(_gridPadding),
            child: Column(
              children: [
                for (var row = 0; row < weekRows.length; row++) ...[
                  Expanded(
                    child: Row(
                      children: [
                        for (
                          var weekday = 0;
                          weekday < _weekdayColumns;
                          weekday++
                        ) ...[
                          SizedBox(
                            width: gridMetrics.weekdayCellWidth,
                            child: _buildDayCell(
                              weekRows[row][weekday],
                              monthView,
                              conflictsByDate: conflictsByDate,
                            ),
                          ),
                          const SizedBox(width: _gridSpacing),
                        ],
                        SizedBox(
                          width: gridMetrics.weekendColumnWidth,
                          child: Column(
                            children: [
                              Expanded(
                                child: _buildDayCell(
                                  weekRows[row][DateTime.saturday - 1],
                                  monthView,
                                  conflictsByDate: conflictsByDate,
                                  dense: true,
                                ),
                              ),
                              const SizedBox(height: _gridSpacing),
                              Expanded(
                                child: _buildDayCell(
                                  weekRows[row][DateTime.sunday - 1],
                                  monthView,
                                  conflictsByDate: conflictsByDate,
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row < weekRows.length - 1)
                    const SizedBox(height: _gridSpacing),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayCell(
    int? index,
    List<MonthDayViewModel> monthView, {
    required Map<String, List<Conflict>> conflictsByDate,
    bool dense = false,
  }) {
    if (index == null) {
      return const SizedBox.shrink();
    }

    final day = currentRoster.days[index];
    final dayView = monthView[index];

    return MonthDayCard(
      day: day,
      dayView: dayView,
      currentDoctor: _currentDoctorFromList(),
      isSelected: _selectedDateKeys.contains(_dateKey(day.date)),
      onTap: null,
      dense: dense,
      isEditorMode: _editorMode,
      hasConflict:
          _editorMode &&
          (conflictsByDate[_dateKey(day.date)]?.isNotEmpty ?? false),
    );
  }

  Map<String, List<Conflict>> _buildConflictsByDate() {
    final conflictsByDate = <String, List<Conflict>>{};
    final validator = RosterValidator();

    for (final day in currentRoster.days) {
      final conflicts = [
        ...validator.validateDay(day),
        ..._validateAbsenceConflicts(day),
      ];

      if (conflicts.isNotEmpty) {
        conflictsByDate[_dateKey(day.date)] = conflicts;
      }
    }

    return conflictsByDate;
  }

  List<Conflict> _validateAbsenceConflicts(RosterDay day) {
    final conflicts = <Conflict>[];

    for (final assignment in day.assignments) {
      final absence = assignment.doctor.absenceOn(day.date);

      if (absence != null) {
        conflicts.add(
          Conflict(
            '${assignment.doctor.fullName} assigned to '
            '${assignment.slot.template.name} while absent '
            '(${absence.label})',
          ),
        );
      }
    }

    return conflicts;
  }

  void _showConflictsDialog(Map<String, List<Conflict>> conflictsByDate) {
    final l10n = AppLocalizations.of(context);
    final entries = conflictsByDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.t('rosterWarnings')),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in entries) ...[
                Text(
                  _formatDateKey(entry.key),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (final conflict in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Text('- ${conflict.message}'),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('close')),
          ),
        ],
      ),
    );
  }

  void _showStatisticsDialog() {
    final l10n = AppLocalizations.of(context);
    final statistics = RosterStatisticsService();
    final conflictsByDate = _buildConflictsByDate();
    final conflictCount = conflictsByDate.values.fold<int>(
      0,
      (total, conflicts) => total + conflicts.length,
    );
    final openSlots = statistics.countOpenSlots(roster: currentRoster);
    final assignedSlots = statistics.countAssignedSlots(roster: currentRoster);
    final coverage = statistics.coveragePercentage(roster: currentRoster);
    final myAssignmentsThisMonth = _myAssignmentsThisMonthCount();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.t('coverage')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatisticRow(label: l10n.t('open'), value: '$openSlots'),
            _StatisticRow(label: l10n.t('assigned'), value: '$assignedSlots'),
            _StatisticRow(
              label: l10n.t('mine'),
              value: '$myAssignmentsThisMonth',
            ),
            _StatisticRow(
              label: l10n.t('coverage'),
              value: '${coverage.toStringAsFixed(0)}%',
            ),
            if (_editorMode)
              _StatisticRow(label: l10n.t('warnings'), value: '$conflictCount'),
          ],
        ),
        actions: [
          if (_editorMode && conflictCount > 0)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showConflictsDialog(conflictsByDate);
              },
              child: Text(l10n.t('warnings')),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('close')),
          ),
        ],
      ),
    );
  }

  List<List<int?>> _buildWeekRows() {
    final firstWeekday = currentRoster.days.first.date.weekday;
    final leadingEmptyCells = firstWeekday - DateTime.monday;
    final totalCells = leadingEmptyCells + currentRoster.days.length;
    final weekCount = (totalCells / DateTime.daysPerWeek).ceil();

    final rows = List.generate(
      weekCount,
      (_) => List<int?>.filled(DateTime.daysPerWeek, null),
    );

    for (var index = 0; index < currentRoster.days.length; index++) {
      final cell = leadingEmptyCells + index;
      final row = cell ~/ DateTime.daysPerWeek;
      final weekday = cell % DateTime.daysPerWeek;
      rows[row][weekday] = index;
    }

    return rows;
  }

  _MonthGridMetrics _gridMetricsForWidth(double gridWidth) {
    final contentWidth = (gridWidth - (_gridPadding * 2)).clamp(
      0.0,
      double.infinity,
    );
    final spacingWidth = _gridSpacing * _weekdayColumns;
    final availableCellWidth = (contentWidth - spacingWidth).clamp(
      0.0,
      double.infinity,
    );
    final weekdayCellWidth =
        availableCellWidth / (_weekdayColumns + _weekendColumnWidthFactor);

    return _MonthGridMetrics(
      weekdayCellWidth: weekdayCellWidth,
      weekendColumnWidth: weekdayCellWidth * _weekendColumnWidthFactor,
    );
  }

  Widget _buildBulkActionBar() {
    final l10n = AppLocalizations.of(context);
    final selectedCount = _selectedDateKeys.length;

    return SafeArea(
      top: false,
      child: Card(
        margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.fill('daysSelected', {
                    'count': selectedCount,
                    'plural': selectedCount == 1
                        ? ''
                        : widget.language == AppLanguage.german
                        ? 'e'
                        : 's',
                  }),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: l10n.t('deselect'),
                onPressed: _clearDateSelection,
                icon: const Icon(Icons.deselect),
              ),
              PopupMenuButton<_BulkAction>(
                tooltip: 'Actions',
                icon: const Icon(Icons.more_vert),
                onSelected: _handleBulkAction,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _BulkAction.setVacation,
                    child: _MenuRow(
                      icon: Icons.beach_access,
                      label: l10n.t('vacation'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _BulkAction.removeVacation,
                    child: _MenuRow(
                      icon: Icons.event_available,
                      label: l10n.t('removeVacation'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  if (_editorMode) ...[
                    PopupMenuItem(
                      value: _BulkAction.chooseDoctor,
                      child: _MenuRow(
                        icon: Icons.person,
                        label: (_editorDoctor ?? _currentDoctorFromList())
                            .firstName,
                      ),
                    ),
                    PopupMenuItem(
                      value: _BulkAction.chooseRole,
                      child: _MenuRow(
                        icon: Icons.assignment_ind,
                        label: _editorSlotKind == null
                            ? l10n.t('chooseRole')
                            : _slotKindLabel(_editorSlotKind!),
                      ),
                    ),
                    PopupMenuItem(
                      enabled: _editorSlotKind != null,
                      value: _BulkAction.applyEditorAssignment,
                      child: _MenuRow(
                        icon: Icons.check,
                        label: l10n.t('apply'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _BulkAction.removeRole,
                      child: _MenuRow(
                        icon: Icons.delete_outline,
                        label: l10n.t('removeRole'),
                      ),
                    ),
                  ] else ...[
                    PopupMenuItem(
                      value: _BulkAction.chooseRole,
                      child: _MenuRow(
                        icon: Icons.assignment_ind,
                        label: l10n.t('chooseRole'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _BulkAction.removeRole,
                      child: _MenuRow(
                        icon: Icons.delete_outline,
                        label: l10n.t('removeRole'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleBulkAction(_BulkAction action) async {
    switch (action) {
      case _BulkAction.setVacation:
        await _setSelectedDatesAsVacation();
      case _BulkAction.removeVacation:
        await _removeVacationFromSelectedDates();
      case _BulkAction.chooseDoctor:
        await _setEditorDoctor();
      case _BulkAction.chooseRole:
        if (_editorMode) {
          await _setEditorRole();
        } else {
          await _chooseRoleForSelectedDates();
        }
      case _BulkAction.removeRole:
        await _removeRoleFromSelectedDates();
      case _BulkAction.applyEditorAssignment:
        final editorDoctor = _editorDoctor ?? _currentDoctorFromList();
        final editorSlotKind = _editorSlotKind;

        if (editorSlotKind == null) {
          return;
        }

        await _assignSelectedDatesToSlotKind(
          slotKind: editorSlotKind,
          doctor: editorDoctor,
        );
    }
  }

  Widget _buildStatusStrip() {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(4),
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _clearStatusMessage,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  void _handleGridPointerDown(Offset position, Size gridSize) {
    _pointerDownIndex = _indexForGridPosition(position, gridSize);
    _isRangeSelecting = false;
  }

  void _handleGridPointerMove(Offset position, Size gridSize) {
    final startIndex = _pointerDownIndex;
    final currentIndex = _indexForGridPosition(position, gridSize);

    if (startIndex == null || currentIndex == null) {
      return;
    }

    if (currentIndex == startIndex && !_isRangeSelecting) {
      return;
    }

    _isRangeSelecting = true;
    _selectDateRange(startIndex, currentIndex);
  }

  void _handleGridPointerUp(Offset position, Size gridSize) {
    final startIndex = _pointerDownIndex;
    final endIndex = _indexForGridPosition(position, gridSize);
    final openedByTap =
        !_isRangeSelecting && startIndex != null && startIndex == endIndex;

    _resetPointerSelection();

    if (openedByTap) {
      _openDay(currentRoster.days[startIndex]);
    }
  }

  void _resetPointerSelection() {
    _pointerDownIndex = null;
    _isRangeSelecting = false;
  }

  int? _indexForGridPosition(Offset position, Size gridSize) {
    final weekRows = _buildWeekRows();
    final contentWidth = gridSize.width - (_gridPadding * 2);
    final contentHeight = gridSize.height - (_gridPadding * 2);

    if (weekRows.isEmpty || contentWidth <= 0 || contentHeight <= 0) {
      return null;
    }

    final gridMetrics = _gridMetricsForWidth(gridSize.width);
    final normalCellWidth = gridMetrics.weekdayCellWidth;
    final weekendColumnWidth = gridMetrics.weekendColumnWidth;
    final rowHeight =
        (contentHeight - (_gridSpacing * (weekRows.length - 1))) /
        weekRows.length;

    if (normalCellWidth <= 0 || weekendColumnWidth <= 0 || rowHeight <= 0) {
      return null;
    }

    final x = position.dx - _gridPadding;
    final y = position.dy - _gridPadding;

    if (x < 0 || y < 0) {
      return null;
    }

    final rowTrack = rowHeight + _gridSpacing;
    final row = y ~/ rowTrack;
    final yInsideRow = y - (row * rowTrack);

    if (row < 0 || row >= weekRows.length || yInsideRow > rowHeight) {
      return null;
    }

    final weekdayTrack = normalCellWidth + _gridSpacing;
    final weekendStart = _weekdayColumns * weekdayTrack;

    if (x < weekendStart) {
      final column = x ~/ weekdayTrack;
      final xInsideCell = x - (column * weekdayTrack);

      if (column < 0 ||
          column >= _weekdayColumns ||
          xInsideCell > normalCellWidth) {
        return null;
      }

      return weekRows[row][column];
    }

    final xInsideWeekend = x - weekendStart;

    if (xInsideWeekend < 0 || xInsideWeekend > weekendColumnWidth) {
      return null;
    }

    final weekendCellHeight = (rowHeight - _gridSpacing) / 2;

    if (yInsideRow <= weekendCellHeight) {
      return weekRows[row][DateTime.saturday - 1];
    }

    if (yInsideRow >= weekendCellHeight + _gridSpacing) {
      return weekRows[row][DateTime.sunday - 1];
    }

    return null;
  }

  void _selectDateRange(int startIndex, int endIndex) {
    final first = startIndex < endIndex ? startIndex : endIndex;
    final last = startIndex < endIndex ? endIndex : startIndex;

    setState(() {
      _selectedDateKeys
        ..clear()
        ..addAll(
          currentRoster.days
              .sublist(first, last + 1)
              .map((day) => _dateKey(day.date)),
        );
    });
  }

  Future<void> _openDay(RosterDay day) async {
    if (day.calendarInfo.isPublicHoliday || day.calendarInfo.isWeekend) {
      return;
    }

    final updatedDay = await Navigator.push<RosterDay>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DayScreen(day: day, currentDoctor: _currentDoctorFromList()),
      ),
    );

    if (updatedDay != null) {
      _replaceDay(updatedDay);
    }
  }

  void _openMonthlyReport() {
    if (SupabaseConfig.isConfigured) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MonthReportPickerScreen(doctors: _doctors),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MonthReportScreen(roster: currentRoster, doctors: _doctors),
      ),
    );
  }

  Future<void> _openRelativeMonth(int delta) async {
    final target = DateTime(currentRoster.year, currentRoster.month + delta, 1);

    if (SupabaseConfig.isConfigured) {
      try {
        final roster = await SupabaseRosterService().loadRoster(
          year: target.year,
          month: target.month,
          doctors: _doctors,
        );

        if (roster == null) {
          _setStatusMessage(
            'No generated roster for ${target.month}/${target.year}',
          );
          return;
        }

        setState(() {
          currentRoster = roster;
          _selectedDateKeys.clear();
        });
        widget.onVisibleMonthChanged?.call(DateTime(target.year, target.month));
      } on PostgrestException catch (error) {
        _setStatusMessage(error.message);
      } catch (_) {
        _setStatusMessage('Could not load ${target.month}/${target.year}.');
      }

      return;
    }

    setState(() {
      currentRoster =
          RosterMonthFactory(
            holidayProvider: ManualHolidayProvider(),
            slotFactory: SlotFactory(),
          ).generateMonth(
            year: target.year,
            month: target.month,
            departmentTemplate: NeurologyDepartmentFactory.create(),
          );
      _selectedDateKeys.clear();
    });
    widget.onVisibleMonthChanged?.call(DateTime(target.year, target.month));
  }

  Future<void> _openAdmin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const MfaScreen(verifiedDestinationBuilder: _buildAdminHomeScreen),
      ),
    );

    widget.onAdminClosed?.call();
  }

  void _clearDateSelection() {
    setState(_selectedDateKeys.clear);
  }

  void _setStatusMessage(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _clearStatusMessage() {
    setState(() {
      _statusMessage = null;
    });
  }

  Future<void> _setSelectedDatesAsVacation() async {
    final l10n = AppLocalizations.of(context);
    final selectedDays = _selectedDays();

    if (selectedDays.isEmpty) {
      return;
    }

    final doctor = _currentDoctorFromList();
    final vacationPeriod = AvailabilityPeriod(
      start: selectedDays.first.date,
      end: selectedDays.last.date,
      type: AvailabilityType.vacation,
    );

    if (SupabaseConfig.isConfigured) {
      try {
        await _insertAbsenceInSupabase(doctor: doctor, period: vacationPeriod);
      } on PostgrestException catch (error) {
        _setStatusMessage(error.message);
        return;
      } catch (_) {
        _setStatusMessage(l10n.t('couldNotSaveVacation'));
        return;
      }
    }

    final updatedDoctor = doctor.copyWith(
      availabilities: [...doctor.availabilities, vacationPeriod],
    );

    final selectedKeys = _selectedDateKeys.toSet();
    final updatedDays = currentRoster.days.map((day) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        return day;
      }

      return RosterDay(
        calendarInfo: day.calendarInfo,
        slots: day.slots,
        availabilities: day.availabilities,
        assignments: day.assignments
            .where((assignment) => assignment.doctor.id != doctor.id)
            .toList(),
      );
    }).toList();

    setState(() {
      _doctors = _replaceDoctorInList(_doctors, updatedDoctor);
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
      _selectedDateKeys.clear();
      if (_editorDoctor?.id == updatedDoctor.id) {
        _editorDoctor = updatedDoctor;
      }
    });

    widget.onDoctorUpdated(updatedDoctor);

    _setStatusMessage(
      l10n.fill('vacationSet', {
        'count': selectedDays.length,
        'plural': _dayPlural(selectedDays.length),
      }),
    );
  }

  Future<void> _setVacationDatesFromImport(List<DateTime> dates) async {
    final l10n = AppLocalizations.of(context);
    final normalizedDates = dates.map(_dateOnly).toSet().toList()
      ..sort((a, b) => a.compareTo(b));

    if (normalizedDates.isEmpty) {
      return;
    }

    final periods = _contiguousVacationPeriods(normalizedDates);
    final doctor = _currentDoctorFromList();

    if (SupabaseConfig.isConfigured) {
      try {
        for (final period in periods) {
          await _insertAbsenceInSupabase(doctor: doctor, period: period);
        }
      } on PostgrestException catch (error) {
        _setStatusMessage(error.message);
        return;
      } catch (_) {
        _setStatusMessage(l10n.t('couldNotSaveVacation'));
        return;
      }
    }

    final selectedKeys = normalizedDates.map(_dateKey).toSet();
    final updatedDoctor = doctor.copyWith(
      availabilities: [...doctor.availabilities, ...periods],
    );
    final updatedDays = currentRoster.days.map((day) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        return day;
      }

      return RosterDay(
        calendarInfo: day.calendarInfo,
        slots: day.slots,
        availabilities: day.availabilities,
        assignments: day.assignments
            .where((assignment) => assignment.doctor.id != doctor.id)
            .toList(),
      );
    }).toList();

    setState(() {
      _doctors = _replaceDoctorInList(_doctors, updatedDoctor);
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
      if (_editorDoctor?.id == updatedDoctor.id) {
        _editorDoctor = updatedDoctor;
      }
    });

    widget.onDoctorUpdated(updatedDoctor);

    _setStatusMessage(
      l10n.fill('vacationSet', {
        'count': normalizedDates.length,
        'plural': _dayPlural(normalizedDates.length),
      }),
    );
  }

  List<AvailabilityPeriod> _contiguousVacationPeriods(List<DateTime> dates) {
    if (dates.isEmpty) {
      return const [];
    }

    final periods = <AvailabilityPeriod>[];
    var start = dates.first;
    var previous = dates.first;

    for (final date in dates.skip(1)) {
      final expectedNext = previous.add(const Duration(days: 1));

      if (_dateOnly(date) == _dateOnly(expectedNext)) {
        previous = date;
        continue;
      }

      periods.add(
        AvailabilityPeriod(
          start: start,
          end: previous,
          type: AvailabilityType.vacation,
        ),
      );
      start = date;
      previous = date;
    }

    periods.add(
      AvailabilityPeriod(
        start: start,
        end: previous,
        type: AvailabilityType.vacation,
      ),
    );

    return periods;
  }

  Future<void> _removeVacationFromSelectedDates() async {
    final l10n = AppLocalizations.of(context);
    final selectedDays = _selectedDays();

    if (selectedDays.isEmpty) {
      return;
    }

    final selectedKeys = _selectedDateKeys.toSet();
    final updatedAvailabilities = <AvailabilityPeriod>[];
    var removedDays = 0;
    final doctor = _currentDoctorFromList();

    if (SupabaseConfig.isConfigured) {
      try {
        await _removeVacationFromSupabase(
          doctor: doctor,
          selectedKeys: selectedKeys,
        );
      } on PostgrestException catch (error) {
        _setStatusMessage(error.message);
        return;
      } catch (_) {
        _setStatusMessage(l10n.t('couldNotRemoveVacation'));
        return;
      }
    }

    for (final availability in doctor.availabilities) {
      if (availability.type != AvailabilityType.vacation) {
        updatedAvailabilities.add(availability);
        continue;
      }

      final retainedRanges = _removeSelectedDatesFromPeriod(
        availability,
        selectedKeys,
      );

      removedDays += _countSelectedDaysInPeriod(availability, selectedKeys);
      updatedAvailabilities.addAll(retainedRanges);
    }

    if (removedDays == 0) {
      _clearDateSelection();
      _setStatusMessage(l10n.t('noVacationFound'));
      return;
    }

    final updatedDoctor = doctor.copyWith(
      availabilities: updatedAvailabilities,
    );

    setState(() {
      _doctors = _replaceDoctorInList(_doctors, updatedDoctor);
      _selectedDateKeys.clear();
      if (_editorDoctor?.id == updatedDoctor.id) {
        _editorDoctor = updatedDoctor;
      }
    });

    widget.onDoctorUpdated(updatedDoctor);

    _setStatusMessage(
      l10n.fill('vacationRemoved', {
        'count': removedDays,
        'plural': _dayPlural(removedDays),
      }),
    );
  }

  Future<void> _insertAbsenceInSupabase({
    required Doctor doctor,
    required AvailabilityPeriod period,
  }) async {
    await Supabase.instance.client.from('absences').insert({
      'doctor_id': doctor.id,
      'starts_on': _dateIso(period.start),
      'ends_on': _dateIso(period.end),
      'type': _availabilityTypeDatabaseValue(period.type),
      'created_by': Supabase.instance.client.auth.currentUser?.id,
    });
  }

  Future<void> _removeVacationFromSupabase({
    required Doctor doctor,
    required Set<String> selectedKeys,
  }) async {
    final selectedDates = selectedKeys.map(_dateFromKey).toList()
      ..sort((a, b) => a.compareTo(b));

    if (selectedDates.isEmpty) {
      return;
    }

    final firstSelected = selectedDates.first;
    final lastSelected = selectedDates.last;
    final rows = await Supabase.instance.client
        .from('absences')
        .select('id, starts_on, ends_on, type')
        .eq('doctor_id', doctor.id)
        .eq('type', 'vacation')
        .lte('starts_on', _dateIso(lastSelected))
        .gte('ends_on', _dateIso(firstSelected));

    for (final row in rows) {
      final absenceId = row['id'] as String;
      final period = AvailabilityPeriod(
        start: DateTime.parse(row['starts_on'] as String),
        end: DateTime.parse(row['ends_on'] as String),
        type: AvailabilityType.vacation,
      );
      final retainedRanges = _removeSelectedDatesFromPeriod(
        period,
        selectedKeys,
      );

      await Supabase.instance.client
          .from('absences')
          .delete()
          .eq('id', absenceId);

      for (final retainedRange in retainedRanges) {
        await _insertAbsenceInSupabase(doctor: doctor, period: retainedRange);
      }
    }
  }

  List<AvailabilityPeriod> _removeSelectedDatesFromPeriod(
    AvailabilityPeriod period,
    Set<String> selectedKeys,
  ) {
    final retainedRanges = <AvailabilityPeriod>[];
    DateTime? rangeStart;
    DateTime? previousRetainedDate;

    for (
      var date = _dateOnly(period.start);
      !date.isAfter(_dateOnly(period.end));
      date = date.add(const Duration(days: 1))
    ) {
      final selected = selectedKeys.contains(_dateKey(date));

      if (selected) {
        if (rangeStart != null && previousRetainedDate != null) {
          retainedRanges.add(
            AvailabilityPeriod(
              start: rangeStart,
              end: previousRetainedDate,
              type: period.type,
            ),
          );
        }

        rangeStart = null;
        previousRetainedDate = null;
        continue;
      }

      rangeStart ??= date;
      previousRetainedDate = date;
    }

    if (rangeStart != null && previousRetainedDate != null) {
      retainedRanges.add(
        AvailabilityPeriod(
          start: rangeStart,
          end: previousRetainedDate,
          type: period.type,
        ),
      );
    }

    return retainedRanges;
  }

  int _countSelectedDaysInPeriod(
    AvailabilityPeriod period,
    Set<String> selectedKeys,
  ) {
    var count = 0;

    for (
      var date = _dateOnly(period.start);
      !date.isAfter(_dateOnly(period.end));
      date = date.add(const Duration(days: 1))
    ) {
      if (selectedKeys.contains(_dateKey(date))) {
        count++;
      }
    }

    return count;
  }

  Future<void> _chooseRoleForSelectedDates() async {
    final choices = _slotChoicesForSelectedDays();

    if (choices.isEmpty) {
      _setStatusMessage(AppLocalizations.of(context).t('noSlotsAvailable'));
      return;
    }

    final targetDoctor = _editorMode
        ? await _chooseDoctorForBulkAssignment()
        : _currentDoctorFromList();

    if (!mounted) {
      return;
    }

    if (targetDoctor == null) {
      return;
    }

    final selectedKind = await _chooseSlotKindForBulkAssignment(choices);

    if (selectedKind == null) {
      return;
    }

    _assignSelectedDatesToSlotKind(
      slotKind: selectedKind,
      doctor: targetDoctor,
    );
  }

  Future<void> _setEditorDoctor() async {
    final doctor = await _chooseDoctorForBulkAssignment();

    if (!mounted || doctor == null) {
      return;
    }

    setState(() {
      _editorDoctor = doctor;
    });
  }

  Future<void> _setEditorRole() async {
    final choices = _slotChoicesForSelectedDays();

    if (choices.isEmpty) {
      _setStatusMessage(AppLocalizations.of(context).t('noSlotsAvailable'));
      return;
    }

    final slotKind = await _chooseSlotKindForBulkAssignment(choices);

    if (!mounted || slotKind == null) {
      return;
    }

    setState(() {
      _editorSlotKind = slotKind;
    });
  }

  Future<SlotKind?> _chooseSlotKindForBulkAssignment(
    List<_SlotChoice> choices,
  ) {
    return showModalBottomSheet<SlotKind>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(l10n.t('assignSelectedDays'))),
              for (final choice in choices)
                ListTile(
                  leading: const Icon(Icons.assignment_ind),
                  title: Text(choice.name),
                  subtitle: Text(choice.area),
                  selected: choice.kind == _editorSlotKind,
                  onTap: () => Navigator.pop(context, choice.kind),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Doctor?> _chooseDoctorForBulkAssignment() {
    return showModalBottomSheet<Doctor>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(l10n.t('assignDoctor'))),
              for (final doctor in _doctors)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(doctor.fullName),
                  subtitle: Text(doctor.rank.name),
                  selected: doctor.id == _currentDoctorFromList().id,
                  onTap: () => Navigator.pop(context, doctor),
                ),
            ],
          ),
        );
      },
    );
  }

  String _slotKindLabel(SlotKind kind) {
    switch (kind) {
      case SlotKind.science:
        return 'Science';
      case SlotKind.strokeUnitLeader:
        return 'SUL';
      case SlotKind.strokeUnitTeam1:
        return 'SU1';
      case SlotKind.strokeUnitTeam2:
        return 'SU2';
      case SlotKind.ambulance:
        return 'Ambulance';
      case SlotKind.neurosonology:
        return 'Sono';
      case SlotKind.neurovascularBoard:
        return 'NVB';
      case SlotKind.ofoBoard:
        return 'OFO';
    }
  }

  Future<void> _assignSelectedDatesToSlotKind({
    required SlotKind slotKind,
    required Doctor doctor,
  }) async {
    final l10n = AppLocalizations.of(context);
    final selectedKeys = _selectedDateKeys.toSet();
    final updatedDays = <RosterDay>[];
    int assigned = 0;
    int skipped = 0;
    final failureReasons = <String>{};

    for (final day in currentRoster.days) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        updatedDays.add(day);
        continue;
      }

      final matchingSlots = day.slots.where(
        (slot) => slot.template.kind == slotKind,
      );

      if (matchingSlots.isEmpty) {
        skipped++;
        updatedDays.add(day);
        continue;
      }

      final targetSlot = matchingSlots.first;
      final retainedAssignments = day.assignments
          .where(
            (assignment) =>
                assignment.slot.id != targetSlot.id &&
                !_isConflictingAssignmentForDoctor(
                  assignment,
                  targetSlot,
                  doctor,
                ),
          )
          .toList();
      final removedAssignments = day.assignments
          .where((assignment) => !retainedAssignments.contains(assignment))
          .toList();
      final dayWithRoleCleared = RosterDay(
        calendarInfo: day.calendarInfo,
        slots: day.slots,
        availabilities: day.availabilities,
        assignments: retainedAssignments,
      );

      final result = AssignmentService().assignDoctorToSlot(
        doctor: doctor,
        slot: targetSlot,
        day: dayWithRoleCleared,
      );

      if (result.success) {
        if (SupabaseConfig.isConfigured) {
          try {
            await _persistAssignmentChanges(
              removedAssignments: removedAssignments,
              addedAssignment: Assignment(doctor: doctor, slot: targetSlot),
            );
          } on PostgrestException catch (error) {
            skipped++;
            failureReasons.add(error.message);
            updatedDays.add(day);
            continue;
          } catch (_) {
            skipped++;
            failureReasons.add(l10n.t('couldNotSaveAssignment'));
            updatedDays.add(day);
            continue;
          }
        }

        assigned++;
        updatedDays.add(result.updatedDay!);
      } else {
        skipped++;
        failureReasons.add(result.reason ?? l10n.t('assignmentFailed'));
        updatedDays.add(day);
      }
    }

    setState(() {
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
      if (!_editorMode) {
        _selectedDateKeys.clear();
      }
    });

    final reasonSuffix = failureReasons.isEmpty
        ? ''
        : ' (${failureReasons.take(2).join('; ')})';

    _setStatusMessage(
      l10n.fill('assignedStatus', {
        'doctor': doctor.firstName,
        'assigned': assigned,
        'assignedPlural': _dayPlural(assigned),
        'skipped': skipped,
        'reason': reasonSuffix,
      }),
    );
  }

  Future<void> _removeRoleFromSelectedDates() async {
    final l10n = AppLocalizations.of(context);
    final selectedKeys = _selectedDateKeys.toSet();
    final doctor = _editorMode
        ? (_editorDoctor ?? _currentDoctorFromList())
        : _currentDoctorFromList();
    final scopedSlotKind = _editorMode ? _editorSlotKind : null;
    final updatedDays = <RosterDay>[];
    final removedAssignments = <Assignment>[];

    for (final day in currentRoster.days) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        updatedDays.add(day);
        continue;
      }

      final retainedAssignments = <Assignment>[];

      for (final assignment in day.assignments) {
        final sameDoctor = assignment.doctor.id == doctor.id;
        final sameRole =
            scopedSlotKind == null ||
            assignment.slot.template.kind == scopedSlotKind;

        if (sameDoctor && sameRole) {
          removedAssignments.add(assignment);
        } else {
          retainedAssignments.add(assignment);
        }
      }

      updatedDays.add(
        RosterDay(
          calendarInfo: day.calendarInfo,
          slots: day.slots,
          availabilities: day.availabilities,
          assignments: retainedAssignments,
        ),
      );
    }

    if (removedAssignments.isEmpty) {
      _setStatusMessage(l10n.t('noRoleFound'));
      return;
    }

    if (SupabaseConfig.isConfigured) {
      try {
        await _persistAssignmentChanges(removedAssignments: removedAssignments);
      } on PostgrestException catch (error) {
        _setStatusMessage(error.message);
        return;
      } catch (_) {
        _setStatusMessage(l10n.t('couldNotRemoveAssignment'));
        return;
      }
    }

    setState(() {
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
      _selectedDateKeys.clear();
    });

    _setStatusMessage(
      l10n.fill('roleRemoved', {
        'count': removedAssignments.length,
        'plural': _dayPlural(removedAssignments.length),
      }),
    );
  }

  Future<void> _persistAssignmentChanges({
    required List<Assignment> removedAssignments,
    Assignment? addedAssignment,
  }) async {
    for (final assignment in removedAssignments) {
      await Supabase.instance.client
          .from('assignments')
          .delete()
          .eq('roster_slot_id', assignment.slot.id)
          .eq('doctor_id', assignment.doctor.id);
    }

    if (addedAssignment == null) {
      return;
    }

    await Supabase.instance.client.from('assignments').insert({
      'roster_slot_id': addedAssignment.slot.id,
      'doctor_id': addedAssignment.doctor.id,
      'state': 'provisional',
      'created_by': Supabase.instance.client.auth.currentUser?.id,
    });
  }

  bool _isConflictingAssignmentForDoctor(
    Assignment assignment,
    DailySlot targetSlot,
    Doctor doctor,
  ) {
    if (assignment.doctor.id != doctor.id) {
      return false;
    }

    final overlaps = assignment.slot.template.timeRange.overlaps(
      targetSlot.template.timeRange,
    );

    if (!overlaps) {
      return false;
    }

    return !DefaultOverlapRules.isAllowed(
      assignment.slot.template.kind,
      targetSlot.template.kind,
    );
  }

  List<_SlotChoice> _slotChoicesForSelectedDays() {
    final selectedKeys = _selectedDateKeys.toSet();
    final choicesByKind = <SlotKind, _SlotChoice>{};

    for (final day in currentRoster.days) {
      if (!selectedKeys.contains(_dateKey(day.date))) {
        continue;
      }

      for (final slot in day.slots) {
        choicesByKind.putIfAbsent(
          slot.template.kind,
          () => _SlotChoice(
            kind: slot.template.kind,
            name: slot.template.name,
            area: slot.template.area,
          ),
        );
      }
    }

    final choices = choicesByKind.values.toList();
    choices.sort((a, b) => a.name.compareTo(b.name));
    return choices;
  }

  List<RosterDay> _selectedDays() {
    final selectedKeys = _selectedDateKeys.toSet();
    final days = currentRoster.days
        .where((day) => selectedKeys.contains(_dateKey(day.date)))
        .toList();

    days.sort((a, b) => a.date.compareTo(b.date));
    return days;
  }

  Doctor _currentDoctorFromList() {
    for (final doctor in _doctors) {
      if (doctor.id == widget.currentDoctor.id) {
        return doctor;
      }
    }

    return widget.currentDoctor;
  }

  List<Doctor> _replaceDoctorInList(
    List<Doctor> doctors,
    Doctor updatedDoctor,
  ) {
    var replaced = false;
    final updatedDoctors = doctors.map((doctor) {
      if (doctor.id != updatedDoctor.id) {
        return doctor;
      }

      replaced = true;
      return updatedDoctor;
    }).toList();

    if (replaced) {
      return updatedDoctors;
    }

    return [...updatedDoctors, updatedDoctor];
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month}-${date.day}';
  }

  String _dateIso(DateTime date) {
    final normalized = _dateOnly(date);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  DateTime _dateFromKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  String _availabilityTypeDatabaseValue(AvailabilityType type) {
    switch (type) {
      case AvailabilityType.available:
        return 'available';
      case AvailabilityType.vacation:
        return 'vacation';
      case AvailabilityType.sickLeave:
        return 'sick_leave';
      case AvailabilityType.conference:
        return 'conference';
      case AvailabilityType.externalRoatation:
        return 'external_rotation';
    }
  }

  String _formatDateKey(String key) {
    final parts = key.split('-');

    if (parts.length != 3) {
      return key;
    }

    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  String _dayPlural(int count) {
    if (count == 1) {
      return '';
    }

    return widget.language == AppLanguage.german ? 'e' : 's';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  void _replaceDay(RosterDay updatedDay) {
    final updatedDays = currentRoster.days.map((day) {
      final sameDate =
          day.date.year == updatedDay.date.year &&
          day.date.month == updatedDay.date.month &&
          day.date.day == updatedDay.date.day;

      return sameDate ? updatedDay : day;
    }).toList();

    setState(() {
      currentRoster = RosterMonth(
        year: currentRoster.year,
        month: currentRoster.month,
        phase: currentRoster.phase,
        days: updatedDays,
      );
    });
  }

  // method
  void _openCalendarExport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarExportScreen(
          roster: currentRoster,
          doctor: _currentDoctorFromList(),
        ),
      ),
    );
  }

  void _showMyAssignmentsDialog() {
    final l10n = AppLocalizations.of(context);
    final myAssignments = RosterStatisticsService()
        .getAssignmentsForDoctorInMonth(
          roster: currentRoster,
          doctor: _currentDoctorFromList(),
        );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.t('mySlotsThisMonth')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (myAssignments.isEmpty) Text(l10n.t('noSlotsAssignedYet')),
            for (final assignment in myAssignments)
              Text(
                '${assignment.slot.date.day}.${assignment.slot.date.month}. '
                '${assignment.slot.template.name} '
                '(${assignment.slot.template.timeRange.display})',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('close')),
          ),
        ],
      ),
    );
  }
}

class _SlotChoice {
  final SlotKind kind;
  final String name;
  final String area;

  _SlotChoice({required this.kind, required this.name, required this.area});
}

class _MonthGridMetrics {
  final double weekdayCellWidth;
  final double weekendColumnWidth;

  const _MonthGridMetrics({
    required this.weekdayCellWidth,
    required this.weekendColumnWidth,
  });
}

class _StatisticRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatisticRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          const SizedBox(width: 24),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData? trailing;

  const _MenuRow({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Icon(trailing, size: 18),
          ],
        ],
      ),
    );
  }
}

Widget _buildAdminHomeScreen(BuildContext context) {
  return const AdminHomeScreen();
}

enum _MonthMenuAction {
  switchDoctor,
  profile,
  myAssignments,
  importVacation,
  exportCalendar,
  monthlyReport,
  statistics,
  toggleTheme,
  languageEnglish,
  languageGerman,
  admin,
  signOut,
}

enum _BulkAction {
  setVacation,
  removeVacation,
  chooseDoctor,
  chooseRole,
  removeRole,
  applyEditorAssignment,
}
