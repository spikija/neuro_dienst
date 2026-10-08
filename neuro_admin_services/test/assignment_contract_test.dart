import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'package:neuro_core/neuro_core.dart';
import 'package:test/test.dart';

final date = HospitalDate(2026, 10, 1);
final now = DateTime.utc(2026, 10, 1, 8);
AssignmentValidationRequest request({
  List<AssignmentTarget>? targets,
  String? replaces,
}) => AssignmentValidationRequest(
  roster: RosterVersion('roster', 3),
  roleId: 'role',
  physicianId: 'doctor',
  targets: targets ?? [AssignmentTarget(date)],
  replacesAssignmentId: replaces,
);
AssignmentValidationResult result({
  HospitalDate? targetDate,
  String? slot = 'slot',
  String physician = 'doctor',
  List<AssignmentValidationError> errors = const [],
  List<AssignmentValidationWarning> warnings = const [],
}) => AssignmentValidationResult(
  date: targetDate ?? date,
  slotId: slot,
  physicianId: physician,
  roleId: 'role',
  errors: errors,
  warnings: warnings,
);

void main() {
  test(
    'hard errors and warnings remain separate and result collections cannot mutate',
    () {
      const warning = AssignmentValidationWarning(
        AssignmentWarningCode.heavyRecentDutyBurden,
        'Recorded burden',
      );
      final input = <AssignmentValidationError>[];
      final valid = result(errors: input, warnings: [warning]);
      input.add(
        const AssignmentValidationError(AssignmentErrorCode.slotFull, 'Full'),
      );
      expect(valid.isValid, isTrue);
      expect(valid.warnings, hasLength(1));
      expect(() => valid.errors.clear(), throwsUnsupportedError);
      expect(result(errors: input, warnings: [warning]).isValid, isFalse);
      expect(
        result(slot: null).errors.single.code,
        AssignmentErrorCode.missingSlot,
      );
      expect(result(slot: '').isValid, isFalse);
    },
  );

  test(
    'requests reject empty and duplicate targets and snapshot the supplied collection',
    () {
      expect(() => request(targets: []), throwsArgumentError);
      expect(
        () =>
            request(targets: [AssignmentTarget(date), AssignmentTarget(date)]),
        throwsArgumentError,
      );
      final targets = [AssignmentTarget(date)];
      final value = request(targets: targets);
      targets.clear();
      expect(value.targets, hasLength(1));
      expect(() => value.targets.clear(), throwsUnsupportedError);
    },
  );

  test(
    'preview must cover every date once and match physician and explicit slot',
    () {
      final value = request(
        targets: [AssignmentTarget(date), AssignmentTarget(date.addDays(1))],
      );
      expect(
        () => AssignmentPreview(request: value, results: [result()]),
        throwsArgumentError,
      );
      expect(
        () => AssignmentPreview(request: value, results: [result(), result()]),
        throwsArgumentError,
      );
      expect(
        () => AssignmentPreview(
          request: request(),
          results: [result(physician: 'another')],
        ),
        throwsArgumentError,
      );
      expect(
        () => AssignmentPreview(
          request: request(targets: [AssignmentTarget(date, slotId: 'chosen')]),
          results: [result()],
        ),
        throwsArgumentError,
      );
      final mixed = AssignmentPreview(
        request: value,
        results: [
          result(),
          result(targetDate: date.addDays(1), slot: null),
        ],
      );
      expect(mixed.allValid, isFalse);
      final disappeared = AssignmentPreview(
        request: request(
          targets: [AssignmentTarget(date, slotId: 'deleted-slot')],
        ),
        results: [result(slot: null)],
      );
      expect(
        disappeared.allValid,
        isFalse,
        reason: 'Missing explicit slots still need a per-date error preview',
      );
    },
  );

  test('advisory, expired or invalid previews cannot form write requests', () {
    final intent = AdminWriteIntent('request');
    expect(
      () => RosterWriteIntent(intent, RosterVersion.unversioned('roster')),
      throwsArgumentError,
    );
    expect(
      () => AssignmentPreview(
        request: AssignmentValidationRequest(
          roster: RosterVersion.unversioned('roster'),
          roleId: 'role',
          physicianId: 'doctor',
          targets: [AssignmentTarget(date)],
        ),
        results: [result()],
        authority: ValidationAuthority.backend,
        confirmationToken: 'token',
        expiresAt: now.add(const Duration(minutes: 2)),
      ),
      throwsArgumentError,
    );
    final advisory = AssignmentPreview(request: request(), results: [result()]);
    expect(advisory.allValid, isTrue);
    expect(advisory.canConfirmAt(now), isFalse);
    expect(
      () => AssignmentCommitRequest(intent, advisory, now: now),
      throwsStateError,
    );
    expect(
      () => AssignmentPreview(
        request: request(),
        results: [result()],
        authority: ValidationAuthority.backend,
      ),
      throwsArgumentError,
    );
    final valid = AssignmentPreview(
      request: request(),
      results: [result()],
      authority: ValidationAuthority.backend,
      confirmationToken: 'opaque-server-token',
      expiresAt: now.add(const Duration(minutes: 2)),
    );
    expect(valid.canConfirmAt(now), isTrue);
    expect(valid.canConfirmAt(now.add(const Duration(minutes: 2))), isFalse);
    expect(
      AssignmentCommitRequest(intent, valid, now: now).preview,
      same(valid),
    );
    final failed = AssignmentPreview(
      request: request(),
      results: [result(slot: null)],
      authority: ValidationAuthority.backend,
      confirmationToken: 'token',
      expiresAt: now.add(const Duration(minutes: 2)),
    );
    expect(
      () => AssignmentCommitRequest(intent, failed, now: now),
      throwsStateError,
    );
  });

  test('replacement binds exactly the assignment excluded during preview', () {
    final preview = AssignmentPreview(
      request: request(replaces: 'old'),
      results: [result()],
      authority: ValidationAuthority.backend,
      confirmationToken: 'token',
      expiresAt: now.add(const Duration(minutes: 2)),
    );
    final addition = AssignmentCommitRequest(
      AdminWriteIntent('request'),
      preview,
      now: now,
    );
    expect(
      AssignmentReplacementRequest(addition, 'old').replacedAssignmentId,
      'old',
    );
    expect(
      () => AssignmentReplacementRequest(addition, 'different'),
      throwsArgumentError,
    );
    expect(
      () => request(
        replaces: 'old',
        targets: [AssignmentTarget(date), AssignmentTarget(date.addDays(1))],
      ),
      throwsArgumentError,
    );
  });

  test(
    'invitation contract distinguishes doctor data from viewer accounts',
    () {
      InvitationRequest invite(ManagedAccountRole role, {DoctorRank? rank}) =>
          InvitationRequest(
            operation: AdminWriteIntent('request'),
            accountRole: role,
            email: 'user@example.invalid',
            firstName: 'Test',
            lastName: 'User',
            language: ProfileLanguage.de,
            rank: rank,
          );
      expect(invite(ManagedAccountRole.viewer).rank, isNull);
      expect(
        invite(ManagedAccountRole.doctor, rank: DoctorRank.consultant).rank,
        DoctorRank.consultant,
      );
      expect(() => invite(ManagedAccountRole.doctor), throwsArgumentError);
      expect(
        () => invite(ManagedAccountRole.viewer, rank: DoctorRank.consultant),
        throwsArgumentError,
      );
      expect(ManagedAccountRole.values.map((value) => value.name), [
        'doctor',
        'viewer',
      ]);
      expect(() => AdminWriteIntent(' '), throwsArgumentError);
    },
  );
}
