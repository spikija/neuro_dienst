enum AdminOperation {
  readRoster,
  readPhysicians,
  readWorkload,
  previewAssignment,
  createPhysician,
  editPhysician,
  deactivatePhysician,
  editUserProfile,
  inviteDoctor,
  inviteViewer,
  editRole,
  editTemplate,
  createRoster,
  regenerateRoster,
  changeAssignment,
  changeAbsence,
  publishRoster,
  changeRosterPhase,
  createDraftRevision,
  editReportConfiguration,
}

/// Intended application policy, NOT proof of authorization. The backend must
/// validate the authenticated user/profile/JWT afresh for every command.
final class AdminAuthorizationRequirement {
  final bool requiresMfa;
  const AdminAuthorizationRequirement({required this.requiresMfa});

  bool allows({
    required bool validSession,
    required String? profileRole,
    required String? assuranceLevel,
  }) =>
      validSession &&
      profileRole == 'admin' &&
      (assuranceLevel == 'aal2' || (!requiresMfa && assuranceLevel == 'aal1'));
}

AdminAuthorizationRequirement requirementFor(AdminOperation operation) =>
    AdminAuthorizationRequirement(
      requiresMfa: switch (operation) {
        AdminOperation.readRoster ||
        AdminOperation.readPhysicians ||
        AdminOperation.readWorkload ||
        AdminOperation.previewAssignment => false,
        AdminOperation.createPhysician ||
        AdminOperation.editPhysician ||
        AdminOperation.deactivatePhysician ||
        AdminOperation.editUserProfile ||
        AdminOperation.inviteDoctor ||
        AdminOperation.inviteViewer ||
        AdminOperation.editRole ||
        AdminOperation.editTemplate ||
        AdminOperation.createRoster ||
        AdminOperation.regenerateRoster ||
        AdminOperation.changeAssignment ||
        AdminOperation.changeAbsence ||
        AdminOperation.publishRoster ||
        AdminOperation.changeRosterPhase ||
        AdminOperation.createDraftRevision ||
        AdminOperation.editReportConfiguration => true,
      },
    );
