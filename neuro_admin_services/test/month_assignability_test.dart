import 'package:test/test.dart';
import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'support/preview_fixture.dart';

void main() {
  test(
    'month sets distinguish warning-valid, hard blocked, ambiguous and absent slots',
    () async {
      final slot = duty(2);
      final snapshot = previewFixture(
        phase: RosterPhase.locked,
        slots: [duty(1), slot, duty(3), duty(3)],
        facts: [
          AssignmentFact(
            'full',
            ben(),
            slot,
            AssignmentState.confirmed,
            RosterPhase.locked,
          ),
        ],
      );
      final validity = MonthAssignability(
        await validate(snapshot, dates: [1, 2, 3, 4]),
      );
      expect(validity.assignableDates, {HospitalDate(2026, 10, 1)});
      expect(validity.warningDates, validity.assignableDates);
      expect(validity.blockedDates, {
        HospitalDate(2026, 10, 2),
        HospitalDate(2026, 10, 3),
      });
      expect(validity.missingSlotDates, {HospitalDate(2026, 10, 4)});
      expect(() => validity.assignableDates.clear(), throwsUnsupportedError);
      final selected = validity.selectedPreview({
        HospitalDate(2026, 10, 1),
        HospitalDate(2026, 10, 2),
        HospitalDate(2026, 10, 4),
      })!;
      expect(selected.results, hasLength(1));
      expect(selected.warningCount, 1);
      expect(selected.authority, ValidationAuthority.advisory);
      expect(validity.selectedPreview({HospitalDate(2026, 10, 2)}), isNull);
      expect(validity.selectedPreview({}), isNull);
    },
  );

  test(
    'deselecting dates changes only the proposed subset, not month validity',
    () async {
      final validity = MonthAssignability(
        await validate(previewFixture(), dates: [1, 2, 3]),
      );
      final selected = validity.selectedPreview({
        HospitalDate(2026, 10, 1),
        HospitalDate(2026, 10, 3),
      })!;
      expect(selected.request.targets.map((t) => t.date), [
        HospitalDate(2026, 10, 1),
        HospitalDate(2026, 10, 3),
      ]);
      expect(validity.assignableDates, hasLength(3));
    },
  );

  test(
    'generation contract rejects published/locked, destructive, stale and unreviewed plans',
    () {
      final now = DateTime.utc(2026, 10, 1);
      final request = RosterGenerationRequest(
        AdminWriteIntent('generation'),
        year: 2026,
        month: 10,
        expectedConfigurationVersion: 'config-1',
      );
      RosterGenerationPlan plan({
        RosterPhase? phase,
        bool impacted = false,
        bool expired = false,
        bool reviewed = true,
      }) => RosterGenerationPlan(
        request: request,
        existing: phase == null
            ? null
            : RosterRevision(
                version: RosterVersion('roster', 1),
                year: 2026,
                month: 10,
                revisionNumber: 1,
                phase: phase,
                isCurrentPublished: phase == RosterPhase.published,
              ),
        days: [],
        slots: [],
        holidaySource: 'verified-calendar-2026',
        impactedAssignmentIds: impacted ? ['existing-assignment'] : [],
        backendToken: reviewed ? 'server-review' : null,
        expiresAt: expired ? now : now.add(const Duration(minutes: 5)),
      );
      for (final bad in [
        plan(phase: RosterPhase.published),
        plan(phase: RosterPhase.locked),
        plan(phase: RosterPhase.openForSelection),
        plan(phase: RosterPhase.draft, impacted: true),
        plan(expired: true),
        plan(reviewed: false),
      ]) {
        expect(
          () => RosterGenerationCommitRequest(bad, now: now),
          throwsStateError,
        );
      }
      expect(
        RosterGenerationCommitRequest(plan(), now: now).plan.existing,
        isNull,
      );
      expect(
        RosterGenerationCommitRequest(
          plan(phase: RosterPhase.draft),
          now: now,
        ).plan.existing!.phase,
        RosterPhase.draft,
      );
    },
  );

  test('report requests keep personal identity explicit', () {
    final roster = RosterVersion('roster', 1);
    expect(
      () => ReportRequest(roster, ReportLayout.personal),
      throwsArgumentError,
    );
    expect(
      () => ReportRequest(roster, ReportLayout.roles, physicianId: 'doctor'),
      throwsArgumentError,
    );
    expect(
      ReportRequest(
        roster,
        ReportLayout.personal,
        physicianId: 'doctor',
      ).physicianId,
      'doctor',
    );
  });
}
