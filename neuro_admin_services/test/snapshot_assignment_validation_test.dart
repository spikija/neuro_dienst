import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:test/test.dart';
import 'support/preview_fixture.dart';

Set<AssignmentErrorCode> codes(AssignmentPreview preview) =>
    preview.results.expand((r) => r.errors).map((e) => e.code).toSet();

void main() {
  test(
    'valid bulk additions are independent, advisory and leave the snapshot untouched',
    () async {
      final data = previewFixture();
      final preview = await validate(data, dates: [1, 2, 3]);
      expect(preview.validCount, 3);
      expect(preview.proposedAdditions, 3);
      expect(preview.blockedCount, 0);
      expect(preview.authority, ValidationAuthority.advisory);
      expect(preview.canConfirmAt(DateTime.now()), isFalse);
      expect(preview.request.roster.contentVersion, isNull);
      expect(data.facts, isEmpty);
      expect(data.days.expand((d) => d.assignments), isEmpty);
    },
  );

  test(
    'physician existence, activity, rank and capabilities are separate errors',
    () async {
      expect(
        codes(await validate(previewFixture(), physician: 'missing')),
        contains(AssignmentErrorCode.physicianNotFound),
      );
      expect(
        codes(await validate(previewFixture(inactive: {'ana'}))),
        contains(AssignmentErrorCode.inactivePhysician),
      );
      final ineligible = await validate(previewFixture(), physician: 'ben');
      expect(
        codes(ineligible),
        containsAll([
          AssignmentErrorCode.physicianNotEligible,
          AssignmentErrorCode.missingCapability,
        ]),
      );
      final noCapability = ana().copyWith(capabilities: {});
      final missing = await validate(previewFixture(doctors: [noCapability]));
      expect(codes(missing), {AssignmentErrorCode.missingCapability});
    },
  );

  test(
    'every other absence blocks the whole date, including a morning slot, but not next day',
    () async {
      for (final type in otherAbsenceTypes) {
        final physician = ana(
          absences: [
            AvailabilityPeriod(
              start: DateTime.utc(2026, 10, 2),
              end: DateTime.utc(2026, 10, 2),
              type: type,
            ),
          ],
        );
        final preview = await validate(
          previewFixture(doctors: [physician]),
          dates: [1, 2, 3],
        );
        expect(preview.results.map((r) => r.isValid), [
          true,
          false,
          true,
        ], reason: type.name);
        expect(
          preview.results[1].errors.single.code,
          AssignmentErrorCode.blockingAbsence,
        );
      }
    },
  );

  test(
    'duty24 marker and next-day post-duty preserve core absence semantics',
    () async {
      final physician = ana(
        absences: [
          AvailabilityPeriod(
            start: DateTime.utc(2026, 10, 1),
            end: DateTime.utc(2026, 10, 1),
            type: AvailabilityType.duty24,
          ),
          AvailabilityPeriod(
            start: DateTime.utc(2026, 10, 2),
            end: DateTime.utc(2026, 10, 2),
            type: AvailabilityType.postDuty,
          ),
        ],
      );
      final preview = await validate(
        previewFixture(doctors: [physician]),
        dates: [1, 2, 3],
      );
      expect(preview.results.map((r) => r.isValid), [true, false, true]);
    },
  );

  test(
    'duplicate and capacity identify current occupants without replacement',
    () async {
      final slot = duty(1);
      final fact = AssignmentFact(
        'existing',
        ana(),
        slot,
        AssignmentState.confirmed,
        RosterPhase.draft,
      );
      final data = previewFixture(facts: [fact]);
      final preview = await validate(data);
      expect(
        codes(preview),
        containsAll([
          AssignmentErrorCode.duplicateAssignment,
          AssignmentErrorCode.slotFull,
        ]),
      );
      expect(preview.results.single.currentAssignments.single.id, 'existing');
      expect(data.facts.single, same(fact));
      final occupied = AssignmentFact(
        'other',
        ben(),
        slot,
        AssignmentState.provisional,
        RosterPhase.draft,
      );
      final full = await validate(previewFixture(facts: [occupied]));
      expect(codes(full), {AssignmentErrorCode.slotFull});
      final twoPlaces = duty(1, capacity: 2);
      expect(
        (await validate(
          previewFixture(slots: [twoPlaces], facts: [occupied]),
        )).allValid,
        isTrue,
      );
    },
  );

  test(
    'overlap uses UTC intervals, allows touching endpoints, and shows conflicts',
    () async {
      final other = duty(1, role: ambulance, start: 11, end: 13);
      final fact = AssignmentFact(
        'conflict',
        ana(),
        other,
        AssignmentState.confirmed,
        RosterPhase.draft,
      );
      final preview = await validate(previewFixture(facts: [fact]));
      expect(
        codes(preview),
        contains(AssignmentErrorCode.overlappingAssignment),
      );
      expect(
        preview.results.single.conflictingAssignments.single.duty.role.id,
        'amb',
      );
      final touching = AssignmentFact(
        'touch',
        ana(),
        duty(1, role: ambulance, start: 12, end: 14),
        AssignmentState.confirmed,
        RosterPhase.draft,
      );
      expect(
        (await validate(previewFixture(facts: [touching]))).allValid,
        isTrue,
      );
    },
  );

  test(
    'core permitted role overlap is a warning, never an invented fairness threshold',
    () async {
      const board = StoredRole(
        'nvb',
        'NVB',
        'Board',
        allowedRanks: {DoctorRank.consultant},
        requiredCapabilities: {},
        isActive: true,
      );
      final fact = AssignmentFact(
        'board',
        ana(),
        duty(1, role: board),
        AssignmentState.confirmed,
        RosterPhase.draft,
      );
      final preview = await validate(previewFixture(facts: [fact]));
      expect(preview.allValid, isTrue);
      expect(preview.warningCount, 1);
      expect(
        preview.results.single.warnings.single.code,
        AssignmentWarningCode.allowedOverlap,
      );
      expect(
        DefaultOverlapRules.isAllowed(
          SlotKind.strokeUnitLeader,
          SlotKind.neurovascularBoard,
        ),
        isTrue,
      );
    },
  );

  test(
    'missing and ambiguous slots never choose a first match; explicit ID resolves ambiguity',
    () async {
      expect(codes(await validate(previewFixture(), dates: [4])), {
        AssignmentErrorCode.missingSlot,
      });
      final data = previewFixture(
        slots: [
          duty(1),
          duty(1, id: 'second'),
        ],
      );
      final ambiguous = await validate(data);
      expect(codes(ambiguous), {AssignmentErrorCode.ambiguousSlot});
      expect(ambiguous.results.single.matchingSlots, hasLength(2));
      expect((await validate(data, slotId: 'second')).allValid, isTrue);
    },
  );

  test(
    'AMB, ICB and custom roles retain exact database identity and eligibility',
    () async {
      final data = previewFixture();
      expect((await validate(data, dates: [2], role: 'amb')).allValid, isTrue);
      expect(codes(await validate(data, dates: [2], role: 'icb')), {
        AssignmentErrorCode.missingSlot,
      });
      expect(
        (await validate(data, dates: [3], role: 'icb')).results.single.slotId,
        'icb-3',
      );
      const custom = StoredRole(
        'custom',
        'NOT_SCI',
        'Custom',
        allowedRanks: {DoctorRank.resident},
        requiredCapabilities: {},
        isActive: true,
      );
      final customData = previewFixture(
        roles: [custom],
        slots: [duty(1, role: custom)],
      );
      expect(
        (await validate(customData, role: 'custom', physician: 'ben')).allValid,
        isTrue,
      );
      expect(codes(await validate(customData, role: 'custom')), {
        AssignmentErrorCode.physicianNotEligible,
      });
    },
  );

  test(
    'lifecycle permits draft/open, warns for locked, and blocks published',
    () async {
      for (final phase in [RosterPhase.draft, RosterPhase.openForSelection]) {
        expect((await validate(previewFixture(phase: phase))).validCount, 1);
      }
      final locked = await validate(previewFixture(phase: RosterPhase.locked));
      expect(locked.allValid, isTrue);
      expect(
        locked.results.single.warnings.single.code,
        AssignmentWarningCode.correctionReasonRequired,
      );
      expect(
        codes(await validate(previewFixture(phase: RosterPhase.published))),
        {AssignmentErrorCode.rosterNotEditable},
      );
    },
  );

  test(
    'incomplete read coverage/metadata fails closed; incomplete history is only a warning',
    () async {
      expect(
        codes(await validate(previewFixture(coverage: false))),
        contains(AssignmentErrorCode.validationUnavailable),
      );
      const unknown = StoredRole('sul', 'SUL', 'Unknown metadata');
      expect(
        codes(await validate(previewFixture(roles: [unknown]))),
        contains(AssignmentErrorCode.validationUnavailable),
      );
      final history = await validate(previewFixture(history: false));
      expect(history.allValid, isTrue);
      expect(history.warningCount, 1);
      expect(
        history.results.single.warnings.single.code,
        AssignmentWarningCode.incompleteWorkloadHistory,
      );
    },
  );

  test(
    'invalid roster date or identity is structured, not silently accepted',
    () async {
      final data = previewFixture();
      for (final target in [
        HospitalDate(2026, 9, 30),
        HospitalDate(2026, 11, 1),
      ]) {
        final preview = await SnapshotAssignmentValidationService(data).preview(
          AssignmentValidationRequest(
            roster: RosterVersion.unversioned('october'),
            physicianId: 'ana',
            roleId: 'sul',
            targets: [AssignmentTarget(target)],
          ),
        );
        expect(codes(preview), contains(AssignmentErrorCode.invalidDate));
      }
    },
  );

  test(
    'month-boundary overnight checks next-day assignments and absences',
    () async {
      final overnight = StoredDuty(
        'night',
        DateTime.utc(2026, 10, 31),
        leader,
        DateTime.utc(2026, 10, 31, 20),
        DateTime.utc(2026, 11, 1, 8),
        1,
      );
      final next = StoredDuty(
        'next',
        DateTime.utc(2026, 11, 1),
        ambulance,
        DateTime.utc(2026, 11, 1, 7),
        DateTime.utc(2026, 11, 1, 12),
        1,
      );
      final fact = AssignmentFact(
        'next',
        ana(),
        next,
        AssignmentState.confirmed,
        RosterPhase.published,
      );
      expect(
        codes(
          await validate(
            previewFixture(slots: [overnight], facts: [fact]),
            dates: [31],
          ),
        ),
        contains(AssignmentErrorCode.overlappingAssignment),
      );
      final absent = ana(
        absences: [
          AvailabilityPeriod(
            start: DateTime.utc(2026, 11, 1),
            end: DateTime.utc(2026, 11, 1),
            type: AvailabilityType.vacation,
          ),
        ],
      );
      expect(
        codes(
          await validate(
            previewFixture(slots: [overnight], doctors: [absent]),
            dates: [31],
          ),
        ),
        contains(AssignmentErrorCode.blockingAbsence),
      );
    },
  );

  test(
    'mutually overlapping proposed days are both blocked without altering dates',
    () async {
      final long = duty(1, end: 36);
      final preview = await validate(
        previewFixture(slots: [long, duty(2), duty(3)]),
        dates: [1, 2, 3],
      );
      expect(preview.results.map((r) => r.isValid), [false, false, true]);
      expect(preview.proposedAdditions, 1);
    },
  );
}
