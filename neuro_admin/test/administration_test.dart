import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_admin/administration_screen.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'workspace_test.dart' show display;

class FakeDirectory implements DirectoryAdministrationService {
  final invitations = <InvitationRequest>[];
  final changes = <DirectoryChange>[];
  bool active = true, revoked = false, uncertain = false;
  @override
  Future<List<ManagedPhysician>> physicians() async => [
    ManagedPhysician(
      id: 'doctor',
      firstName: 'Ana',
      lastName: 'Historical',
      updatedAt: '2026-10-10',
      rank: DoctorRank.consultant,
      capabilities: {Capability.canLead},
      isActive: active,
      printOrder: 1,
    ),
  ];
  @override
  Future<List<ManagedViewer>> viewers() async => [
    ManagedViewer(
      id: 'viewer',
      displayName: 'Test Viewer',
      updatedAt: '2026-10-10',
      email: 'viewer@example.invalid',
      language: ProfileLanguage.de,
      accessRevoked: revoked,
    ),
  ];
  @override
  Future<void> change(DirectoryChange r) async {
    changes.add(r);
    if (r.changes['delete'] == true) {
      throw const DirectoryFailure('physicianHasDependencies');
    }
    if (uncertain) {
      uncertain = false;
      throw const DirectoryFailure('unavailable', outcomeUnknown: true);
    }
    if (r.directory == 'physicians') {
      active = r.changes['is_active'] as bool? ?? active;
    }
    if (r.directory == 'viewers') {
      revoked = r.changes['access_revoked'] as bool? ?? revoked;
    }
  }

  @override
  Future<InvitationReceipt> invite(InvitationRequest r) async {
    invitations.add(r);
    return InvitationReceipt(
      r.operation.requestId,
      r.accountRole,
      r.accountRole == ManagedAccountRole.doctor ? 'new-doctor' : null,
      InvitationDeliveryStatus.sent,
    );
  }

  @override
  Future<void> updateProfile(UserProfileChange c) async {}
}

void main() {
  for (final role in ManagedAccountRole.values) {
    testWidgets(
      'invite ${role.name} uses shared service and validates fields',
      (tester) async {
        final service = FakeDirectory();
        await display(tester, AdministrationScreen(service: service));
        if (role == ManagedAccountRole.viewer) {
          await tester.tap(find.text('Viewers'));
          await tester.pumpAndSettle();
          expect(find.text('Ana Historical'), findsNothing);
        }
        await tester.tap(
          find.text(
            role == ManagedAccountRole.doctor
                ? 'Invite physician'
                : 'Invite viewer',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Invite'));
        await tester.pumpAndSettle();
        expect(service.invitations, isEmpty);
        Finder field(String name) => find.widgetWithText(TextFormField, name);
        await tester.enterText(field('First name'), 'Test');
        await tester.enterText(field('Last name'), 'Person');
        await tester.enterText(field('Email'), 'test@example.invalid');
        if (role == ManagedAccountRole.viewer) {
          expect(find.text('Rank'), findsNothing);
        }
        await tester.tap(find.text('Invite'));
        await tester.pumpAndSettle();
        final sent = service.invitations.single;
        expect(sent.accountRole, role);
        expect(
          sent.rank,
          role == ManagedAccountRole.doctor ? DoctorRank.resident : null,
        );
        expect(find.byType(DirectoryEditor), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'delete with history offers archival and retains historical physician',
    (tester) async {
      final service = FakeDirectory();
      await display(tester, AdministrationScreen(service: service));
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('History or dependent records prevent deletion'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await tester.pumpAndSettle();
      expect(service.active, isFalse);
      expect(find.text('Ana Historical'), findsOneWidget);
      expect(service.changes.last.changes, {'is_active': false});
    },
  );
  testWidgets(
    'viewer revocation retries same UUID without duplicating intent',
    (tester) async {
      final service = FakeDirectory()..uncertain = true;
      await display(tester, AdministrationScreen(service: service));
      await tester.tap(find.text('Viewers'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Revoke access'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(
        service.changes.map((r) => r.operation.requestId).toSet(),
        hasLength(1),
      );
      expect(service.revoked, isTrue);
      expect(find.textContaining('Access revoked'), findsOneWidget);
    },
  );
  testWidgets('physician edit preserves capabilities and search filters list', (
    tester,
  ) async {
    final service = FakeDirectory();
    await display(tester, AdministrationScreen(service: service));
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Updated',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.changes.single.changes['first_name'], 'Updated');
    expect(service.changes.single.changes['capabilities'], ['can_lead']);
    await tester.enterText(find.byType(TextField), 'No matching person');
    await tester.pumpAndSettle();
    expect(find.text('Ana Historical'), findsNothing);
  });
}
