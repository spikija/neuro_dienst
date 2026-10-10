// Public configuration + a previously authenticated administrator/AAL2 session.
// Writes are opt-in: an explicitly authorized email and June 2027 only.
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:neuro_admin/supabase_config.dart';
import 'package:neuro_admin/report_table.dart';
import 'package:neuro_admin/reports_screen.dart';
import 'package:neuro_admin/report_pdf.dart';
import 'package:neuro_admin/localization.dart';
import 'package:neuro_admin/roster_dashboard.dart';
import 'package:neuro_admin/calendar_day_grid.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:neuro_admin_services/supabase_admin_reader.dart';
import 'package:neuro_admin_services/supabase_admin_workspace.dart';
import 'package:neuro_admin_services/supabase_admin_directory.dart';
import 'package:neuro_admin_services/supabase_admin_mutations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _JuneReader implements RosterReader {
  final RosterReader source;
  _JuneReader(this.source);
  @override
  Future<List<RosterChoice>> listMonths() async => (await source.listMonths())
      .where((m) => m.year == 2027 && m.month == 6)
      .toList();
  @override
  Future<RosterSnapshot> loadMonth(RosterChoice month) =>
      source.loadMonth(month);
}

class _RecordedWrites implements AssignmentMutationService {
  final AssignmentMutationService source;
  AssignmentMutationReceipt? receipt;
  _RecordedWrites(this.source);
  @override
  Future<bool> canApply() => source.canApply();
  @override
  Future<AssignmentMutationReceipt> bulkAssign(
    AssignmentCommitRequest r,
  ) async => receipt = await source.bulkAssign(r);
  @override
  Future<AssignmentMutationReceipt> assign(AssignmentCommitRequest r) =>
      bulkAssign(r);
  @override
  Future<AssignmentMutationReceipt> remove(AssignmentRemovalRequest r) =>
      throw UnsupportedError('Not part of live test');
  @override
  Future<AssignmentMutationReceipt> replace(AssignmentReplacementRequest r) =>
      throw UnsupportedError('Not part of live test');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Phase 2F live verification with explicit write opt-ins', (
    tester,
  ) async {
    const config = SupabaseConfig.fromEnvironment();
    if (!config.isConfigured || config.validationError != null) {
      markTestSkipped('LIVE_NOT_VERIFIED: public configuration unavailable');
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
    try {
      if (client.auth.currentSession == null) {
        markTestSkipped('LIVE_NOT_VERIFIED: no saved session');
        return;
      }
      if (client.auth.currentSession!.isExpired) {
        await client.auth.refreshSession();
      }
      final user = (await client.auth.getUser()).user;
      if (user == null) {
        markTestSkipped('LIVE_NOT_VERIFIED: session invalid');
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
        markTestSkipped('LIVE_NOT_VERIFIED: admin+AAL2 required');
        return;
      }
    } on AuthException {
      markTestSkipped('LIVE_NOT_VERIFIED: renew administrator MFA session');
      return;
    }
    final reader = SupabaseRosterReader(client);
    final months = await reader.listMonths();
    expect(months, isNotEmpty);
    final snapshot = await reader.loadMonth(months.first);
    final service = SupabaseReportingService(client);
    final version = RosterVersion(snapshot.month.id, snapshot.contentVersion!);
    Widget shell(Widget child) => MaterialApp(
      locale: const Locale('de'),
      supportedLocales: const [Locale('en'), Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );
    await tester.pumpWidget(
      shell(ReportsScreen(service: service, roster: version)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Berichte'), findsOneWidget);
    expect(find.byType(ReportTable), findsOneWidget);
    final horizontal = tester
        .widget<SingleChildScrollView>(
          find.byKey(const ValueKey('report-body')),
        )
        .controller!;
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final output = await Directory.systemTemp.createTemp(
      'neuro-admin-phase2f-live-',
    );
    for (final layout in [ReportLayout.roles, ReportLayout.physicians]) {
      final report = await service.load(ReportRequest(version, layout));
      for (final orientation in ReportOrientation.values) {
        final pdf = await buildReportPdf(
          report,
          orientation,
          const AdminStrings('de'),
        );
        await File(
          '${output.path}/${layout.name}-${orientation.name}.pdf',
        ).writeAsBytes(pdf.bytes);
        expect(pdf.pageCount, greaterThan(0));
      }
    }
    debugPrint(
      'LIVE_REPORTS_VERIFIED: German UI, horizontal scroll, role/physician PDF in both A4 orientations. Output: ${output.path}',
    );
    final directory = SupabaseDirectoryService(client);
    var directoryAvailable = false;
    try {
      await directory.physicians();
      await directory.viewers();
      directoryAvailable = true;
      debugPrint('LIVE_DIRECTORY_AVAILABLE');
    } on PostgrestException catch (e) {
      debugPrint(
        'LIVE_DIRECTORY_NOT_VERIFIED: RPC unavailable (${e.code}). Migration not deployed by this test.',
      );
    }

    for (final invitation in [
      (
        ManagedAccountRole.viewer,
        const String.fromEnvironment('LIVE_TEST_INVITE_EMAIL'),
      ),
      (
        ManagedAccountRole.doctor,
        const String.fromEnvironment('LIVE_TEST_PHYSICIAN_EMAIL'),
      ),
    ]) {
      final (role, email) = invitation;
      if (email.isEmpty || !directoryAvailable) continue;
      // Repeat verification must not send duplicate invitations or change an
      // existing account. Test physicians start inactive to avoid staffing use.
      final physicians = await directory.physicians();
      final viewers = await directory.viewers();
      if (physicians.any(
            (p) => p.email?.toLowerCase() == email.toLowerCase(),
          ) ||
          viewers.any((p) => p.email?.toLowerCase() == email.toLowerCase())) {
        debugPrint(
          'LIVE_INVITATION_SKIPPED: ${role.name} address already exists; retained.',
        );
        continue;
      }
      try {
        final result = await directory.invite(
          InvitationRequest(
            operation: AdminWriteIntent.create(),
            accountRole: role,
            email: email,
            firstName: 'Desktop',
            lastName: 'Verification',
            language: ProfileLanguage.de,
            rank: role == ManagedAccountRole.doctor
                ? DoctorRank.resident
                : null,
            isActive: role != ManagedAccountRole.doctor,
          ),
        );
        if (role == ManagedAccountRole.viewer) {
          expect(result.physicianId, isNull);
          final viewer = (await directory.viewers()).singleWhere(
            (v) => v.email?.toLowerCase() == email.toLowerCase(),
          );
          final linked = await client
              .from('doctors')
              .select('id')
              .eq('auth_user_id', viewer.id);
          expect(linked, isEmpty);
          debugPrint(
            'LIVE_VIEWER_INVITATION_SENT: directory entry verified; no physician record or staffing identity.',
          );
        } else {
          final physician = (await directory.physicians()).singleWhere(
            (p) => p.id == result.physicianId,
          );
          expect(physician.isActive, isFalse);
          expect(physician.rank, DoctorRank.resident);
          debugPrint(
            'LIVE_PHYSICIAN_INVITATION_SENT: directory entry verified; inactive test physician retained.',
          );
        }
      } on DirectoryFailure catch (e) {
        debugPrint(
          'LIVE_INVITATION_NOT_VERIFIED: ${role.name}: ${e.code}; not retried.',
        );
      }
    }

    if (const bool.fromEnvironment('LIVE_CREATE_JUNE_2027')) {
      if (months.any((m) => m.year == 2027 && m.month == 6)) {
        debugPrint(
          'LIVE_CREATION_NOT_RUN: June 2027 already exists. Existing data retained.',
        );
      } else {
        // Read-only capability check before invoking the actual desktop dialog.
        final workspace = SupabaseWorkspaceService(client);
        try {
          final plan = await workspace.preview(
            RosterGenerationRequest(
              AdminWriteIntent.create(),
              year: 2027,
              month: 6,
              expectedConfigurationVersion: 'server-preview',
            ),
          );
          if (plan.blockers.isNotEmpty) {
            debugPrint(
              'LIVE_CREATION_NOT_RUN: server preview blocks generation.',
            );
            return;
          }
        } on AssignmentMutationFailure catch (e) {
          debugPrint(
            'LIVE_CREATION_NOT_VERIFIED: preview RPC unavailable (${e.code}).',
          );
          return;
        }
        await tester.pumpWidget(
          shell(
            RosterDashboard(
              reader: reader,
              generation: workspace,
              onSignOut: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Dienstplanaktionen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Monatsdienstplan erstellen'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '2027');
        await tester.tap(find.byType(DropdownButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('6').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vorschau'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dienstplan erstellen'));
        await tester.pump();
        expect(find.byType(CalendarDayGrid), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          (await reader.listMonths()).where(
            (m) => m.year == 2027 && m.month == 6,
          ),
          hasLength(1),
        );
        debugPrint(
          'LIVE_JUNE_2027_CREATED: desktop dialog completed without an error frame; no existing roster deleted.',
        );
      }
    }
    if (const bool.fromEnvironment('LIVE_ASSIGN_JUNE_2027')) {
      final june = (await reader.listMonths())
          .where((m) => m.year == 2027 && m.month == 6)
          .firstOrNull;
      if (june == null) {
        debugPrint('LIVE_ASSIGNMENT_NOT_RUN: June 2027 unavailable');
        return;
      }
      final data = await reader.loadMonth(june);
      AssignmentPreview? candidate;
      search:
      for (final day in data.days) {
        for (final slot in day.slots) {
          if (day.assignments.any((a) => a.duty.role.id == slot.role.id)) {
            continue;
          }
          for (final doctor in data.doctors.where(
            (d) => !data.inactiveDoctorIds.contains(d.id),
          )) {
            final preview = await SnapshotAssignmentValidationService(data)
                .preview(
                  AssignmentValidationRequest(
                    roster: RosterVersion(june.id, data.contentVersion!),
                    roleId: slot.role.id,
                    physicianId: doctor.id,
                    targets: [
                      AssignmentTarget(
                        HospitalDate.fromCalendarComponents(day.date),
                      ),
                    ],
                  ),
                );
            if (preview.allValid) {
              candidate = preview;
              break search;
            }
          }
        }
      }
      if (candidate == null) {
        debugPrint('LIVE_ASSIGNMENT_NOT_RUN: no eligible empty role/day');
        return;
      }
      final target = candidate.request;
      final writes = _RecordedWrites(SupabaseAssignmentMutationService(client));
      await tester.pumpWidget(
        shell(
          RosterDashboard(
            reader: _JuneReader(reader),
            mutations: writes,
            onSignOut: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final role = find.byKey(ValueKey('role-chip-${target.roleId}'));
      await tester.ensureVisible(role);
      await tester.tap(role);
      await tester.pumpAndSettle();
      final physician = find.byKey(ValueKey('candidate-${target.physicianId}'));
      await tester.scrollUntilVisible(
        physician,
        150,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('physician-candidates')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(physician);
      await tester.tap(physician);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Auswahlaktionen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auswahl aufheben'));
      await tester.pumpAndSettle();
      final cell = find.byKey(
        ValueKey(target.targets.single.date.asDateOnlyUtc),
      );
      await tester.ensureVisible(cell);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(cell));
      await mouse.down(tester.getCenter(cell));
      await mouse.up();
      await mouse.removePointer();
      await tester.pumpAndSettle();
      try {
        await tester.tap(find.text('Zuweisungen speichern'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bestätigen und speichern'));
        await tester.pump();
        expect(find.byType(CalendarDayGrid), findsOneWidget);
        await tester.pumpAndSettle();
        expect(writes.receipt?.addedAssignmentIds, hasLength(1));
        expect(find.byType(CalendarDayGrid), findsOneWidget);
        expect(tester.takeException(), isNull);
        debugPrint(
          'LIVE_ASSIGNMENT_VERIFIED: one June 2027 assignment through desktop confirmation; calendar retained.',
        );
      } finally {
        final receipt = writes.receipt;
        if (receipt != null) {
          final current = await reader.loadMonth(june);
          final removal = AssignmentRemovalPreview(
            current,
            [target.targets.single.date],
            scope: RemovalScope.role,
            roleId: target.roleId,
          );
          expect(
            removal.assignments.map((a) => a.id).toSet(),
            receipt.addedAssignmentIds.toSet(),
            reason:
                'Cleanup must never include a pre-existing or concurrent assignment',
          );
          await SupabaseWorkspaceService(
            client,
          ).removeDates(removal, AdminWriteIntent.create());
          debugPrint(
            'LIVE_TEST_ASSIGNMENT_REMOVED: only the assignment created by this test; June roster retained.',
          );
        }
      }
    }
  });
}
