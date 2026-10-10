// Optional live check. No mutation adapter is constructed or supplied.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin/calendar_theme.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin/supabase_config.dart';
import 'package:neuro_admin/data/roster_reader.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_admin_services/supabase_admin_workspace.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('live month highlighting is read-only', (tester) async {
    const config = SupabaseConfig.fromEnvironment();
    if (!config.isConfigured || config.validationError != null) {
      markTestSkipped(
        'LIVE_NOT_VERIFIED: valid public configuration unavailable',
      );
      return;
    }
    await Supabase.initialize(
      url: config.url.trim(),
      publishableKey: config.publishableKey.trim(),
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
    final client = Supabase.instance.client;
    addTearDown(() => Supabase.instance.dispose());
    if (client.auth.currentSession == null) {
      markTestSkipped('LIVE_NOT_VERIFIED: no saved administrator session');
      return;
    }
    User? user;
    try {
      if (client.auth.currentSession!.isExpired) {
        await client.auth.refreshSession();
      }
      user = (await client.auth.getUser()).user;
    } on AuthException {
      markTestSkipped(
        'LIVE_NOT_VERIFIED: saved session expired; sign in and complete MFA in the desktop application',
      );
      return;
    }
    if (user == null) {
      markTestSkipped('LIVE_NOT_VERIFIED: session not verified');
      return;
    }
    final profile = await client
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile?['role'] != 'admin' ||
        client.auth.mfa.getAuthenticatorAssuranceLevel().currentLevel !=
            AuthenticatorAssuranceLevels.aal2) {
      markTestSkipped('LIVE_NOT_VERIFIED: administrator MFA session required');
      return;
    }
    final reader = SupabaseRosterReader(client);
    final months = await reader.listMonths();
    if (months.isEmpty) {
      markTestSkipped('LIVE_NOT_VERIFIED: no roster available');
      return;
    }
    final snapshot = await reader.loadMonth(months.first);
    final reporting = SupabaseReportingService(client);
    final version = RosterVersion(snapshot.month.id, snapshot.contentVersion!);
    final roleReport = await reporting.load(
      ReportRequest(version, ReportLayout.roles),
    );
    final physicianReport = await reporting.load(
      ReportRequest(version, ReportLayout.physicians),
    );
    final visibleRoles = roleReport.columns.map((c) => c.id).toSet();
    expect(
      roleReport.rows
          .expand((r) => r.cells.values)
          .expand((c) => c.assignments)
          .map((a) => a.id)
          .toSet(),
      snapshot.days
          .expand((d) => d.assignments)
          .where((a) => visibleRoles.contains(a.duty.role.id))
          .map((a) => a.id)
          .toSet(),
    );
    final assignedPhysicians = snapshot.days
        .expand((d) => d.assignments)
        .map((a) => a.doctor.id)
        .toSet();
    expect(
      assignedPhysicians.difference(
        physicianReport.columns.map((c) => c.id).toSet(),
      ),
      isEmpty,
    );
    debugPrint(
      'LIVE_REPORTS_VERIFIED: exact assignment facts and historical physician columns. Screen-only; no writes.',
    );
    try {
      await SupabaseWorkspaceService(client).preview(
        RosterGenerationRequest(
          AdminWriteIntent.create(),
          year: 2100,
          month: 12,
          expectedConfigurationVersion: 'server-preview',
        ),
      );
      debugPrint(
        'LIVE_GENERATION_PREVIEW_AVAILABLE: read-only preview completed. No generation or removal executed.',
      );
    } on AssignmentMutationFailure {
      debugPrint(
        'LIVE_WRITES_NOT_VERIFIED: workspace preview RPC unavailable; apply the workspace migration before deployment testing.',
      );
    }
    final roles = previewRoles(snapshot);
    if (roles.isEmpty || snapshot.doctors.isEmpty) {
      markTestSkipped('LIVE_NOT_VERIFIED: no role/physician pair');
      return;
    }
    AssignmentPreview? expected;
    StoredRole? role;
    for (final candidateRole in roles) {
      for (final doctor in snapshot.doctors) {
        final preview = await SnapshotAssignmentValidationService(snapshot)
            .preview(
              AssignmentValidationRequest(
                roster: snapshot.contentVersion == null
                    ? RosterVersion.unversioned(snapshot.month.id)
                    : RosterVersion(
                        snapshot.month.id,
                        snapshot.contentVersion!,
                      ),
                roleId: candidateRole.id,
                physicianId: doctor.id,
                targets: [
                  for (
                    var d = 1;
                    d <=
                        DateTime.utc(
                          snapshot.month.year,
                          snapshot.month.month + 1,
                          0,
                        ).day;
                    d++
                  )
                    AssignmentTarget(
                      HospitalDate(
                        snapshot.month.year,
                        snapshot.month.month,
                        d,
                      ),
                    ),
                ],
              ),
            );
        expected = preview;
        role = candidateRole;
        if (preview.proposedAdditions > 0) break;
      }
      if (expected!.proposedAdditions > 0) break;
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: adminTheme(Brightness.light),
        home: RosterDashboard(
          reader: _LoadedSnapshot(snapshot),
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Selection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all working days'));
    await tester.pumpAndSettle();
    final working = tester
        .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
        .selection
        .dates;
    expect(
      working.every(
        (d) => AustrianHolidays.isWorkingDay(
          HospitalDate.fromCalendarComponents(d),
        ),
      ),
      isTrue,
    );
    final holidayCount = AustrianHolidays.forYear(
      snapshot.month.year,
    ).keys.where((d) => d.month == snapshot.month.month).length;
    expect(
      find.byIcon(Icons.celebration_outlined),
      findsNWidgets(holidayCount),
    );
    debugPrint(
      'LIVE_HOLIDAYS_VERIFIED: $holidayCount national holiday dates; working-day selection excludes them.',
    );
    await tester.tap(find.byKey(ValueKey('role-chip-${role!.id}')));
    await tester.pumpAndSettle();
    final candidate = find.byKey(
      ValueKey('candidate-${expected!.request.physicianId}'),
    );
    await tester.scrollUntilVisible(
      candidate,
      100,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('physician-candidates')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(
      find.descendant(of: candidate, matching: find.byType(Text)).first,
    );
    await tester.pumpAndSettle();
    final validity = MonthAssignability(expected);
    for (final result in expected.results) {
      final cell = find.byKey(ValueKey('assignability-${result.date}'));
      final decoration =
          tester.widget<AnimatedContainer>(cell).decoration as BoxDecoration;
      expect(
        decoration.border!.top.width,
        validity.assignableDates.contains(result.date) ? 3 : 1,
      );
      if (validity.warningDates.contains(result.date)) {
        expect(
          find.descendant(of: cell, matching: find.byIcon(Icons.warning_amber)),
          findsOneWidget,
        );
      }
      if (validity.blockedDates.contains(result.date)) {
        expect(
          find.descendant(of: cell, matching: find.byIcon(Icons.block)),
          findsOneWidget,
        );
      }
    }
    expect(
      tester
          .widget<CalendarDayGrid>(find.byType(CalendarDayGrid))
          .selection
          .dates,
      validity.assignableDates.map((d) => d.asDateOnlyUtc).toSet(),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply assignments'),
          )
          .onPressed,
      isNull,
    );
    // Counts only: no tokens, identities, names or roster contents in the log.
    debugPrint(
      'LIVE_READ_ONLY_VERIFIED: ${expected.results.length} dates; ${validity.assignableDates.length} assignable; ${validity.blockedDates.length} blocked; ${validity.warningDates.length} warning-valid. Writes disabled.',
    );
  });
}

class _LoadedSnapshot implements RosterReader {
  final RosterSnapshot snapshot;
  _LoadedSnapshot(this.snapshot);
  @override
  Future<List<RosterChoice>> listMonths() async => [snapshot.month];
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice _) async => snapshot;
}
