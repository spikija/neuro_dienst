import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'only open selection permits physicians; published revisions never edit in place',
    () {
      for (final phase in RosterPhase.values) {
        expect(
          RosterLifecyclePolicy.allowsPhysicianSelection(phase),
          phase == RosterPhase.openForSelection,
        );
        expect(
          RosterLifecyclePolicy.isPublishedPhase(phase),
          phase == RosterPhase.published,
        );
        expect(
          RosterLifecyclePolicy.allowsAdminAssignment(phase),
          phase == RosterPhase.draft || phase == RosterPhase.openForSelection,
        );
        expect(
          RosterLifecyclePolicy.allowsAdminAssignment(
            phase,
            correctionReason: 'Approved correction',
          ),
          phase != RosterPhase.published,
        );
      }
      expect(
        RosterLifecyclePolicy.allowsAdminAssignment(
          RosterPhase.locked,
          correctionReason: '  ',
        ),
        isFalse,
      );
    },
  );

  test(
    'transition matrix requires locking before publication and forbids published rollback',
    () {
      const allowed = {
        (RosterPhase.draft, RosterPhase.openForSelection),
        (RosterPhase.draft, RosterPhase.locked),
        (RosterPhase.openForSelection, RosterPhase.locked),
        (RosterPhase.locked, RosterPhase.openForSelection),
        (RosterPhase.locked, RosterPhase.published),
      };
      for (final from in RosterPhase.values) {
        for (final to in RosterPhase.values) {
          expect(
            RosterLifecyclePolicy.allowsTransition(from, to),
            allowed.contains((from, to)),
          );
        }
      }
    },
  );

  test(
    'admin matrix allows authenticated reads at aal1 but all writes require aal2',
    () {
      const reads = {
        AdminOperation.readRoster,
        AdminOperation.readPhysicians,
        AdminOperation.readWorkload,
        AdminOperation.previewAssignment,
      };
      for (final operation in AdminOperation.values) {
        final policy = requirementFor(operation);
        expect(policy.requiresMfa, !reads.contains(operation));
        expect(
          policy.allows(
            validSession: true,
            profileRole: 'admin',
            assuranceLevel: 'aal1',
          ),
          reads.contains(operation),
        );
        expect(
          policy.allows(
            validSession: true,
            profileRole: 'admin',
            assuranceLevel: 'aal2',
          ),
          isTrue,
        );
        expect(
          policy.allows(
            validSession: false,
            profileRole: 'admin',
            assuranceLevel: 'aal2',
          ),
          isFalse,
        );
        for (final role in ['doctor', 'viewer', null]) {
          expect(
            policy.allows(
              validSession: true,
              profileRole: role,
              assuranceLevel: 'aal2',
            ),
            isFalse,
          );
        }
        for (final level in [null, 'unknown']) {
          expect(
            policy.allows(
              validSession: true,
              profileRole: 'admin',
              assuranceLevel: level,
            ),
            isFalse,
          );
        }
      }
    },
  );

  test('version metadata cannot declare a draft authoritative', () {
    expect(() => RosterVersion('', 1), throwsArgumentError);
    expect(() => RosterVersion('r', -1), throwsArgumentError);
    expect(
      () => RosterRevision(
        version: RosterVersion('r', 0),
        year: 2026,
        month: 10,
        revisionNumber: 1,
        phase: RosterPhase.draft,
        isCurrentPublished: true,
      ),
      throwsArgumentError,
    );
    final old = RosterRevision(
      version: RosterVersion('r', 2),
      year: 2026,
      month: 10,
      revisionNumber: 1,
      phase: RosterPhase.published,
      isCurrentPublished: false,
    );
    expect(old.isAuthoritative, isFalse);
    expect(
      old.phase,
      RosterPhase.published,
      reason: 'Archived publication retains historical phase',
    );
  });
}
