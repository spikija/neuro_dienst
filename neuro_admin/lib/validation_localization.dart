import 'package:neuro_admin_services/neuro_admin_services.dart';
import 'localization.dart';

String validationErrorText(
  AdminStrings strings,
  AssignmentValidationError error,
) => strings.language != 'de'
    ? error.message
    : switch (error.code) {
        AssignmentErrorCode.unauthorized =>
          'Administratorzugriff erforderlich.',
        AssignmentErrorCode.mfaRequired =>
          'Zwei-Faktor-Authentifizierung erforderlich.',
        AssignmentErrorCode.internalError =>
          'Interner Serverfehler. Keine Zuweisungen gespeichert.',
        AssignmentErrorCode.idempotencyConflict =>
          'Die Anfragekennung wurde bereits für einen anderen Vorgang verwendet.',
        AssignmentErrorCode.physicianNotFound =>
          'Person nicht im geladenen Verzeichnis gefunden.',
        AssignmentErrorCode.missingCapability =>
          'Erforderliche Qualifikationen fehlen.',
        AssignmentErrorCode.invalidDate =>
          'Datum gehört nicht zu diesem Dienstplan.',
        AssignmentErrorCode.roleInactive => 'Die Dienstrolle ist inaktiv.',
        AssignmentErrorCode.invalidSlot =>
          'Datum, Zeitintervall oder Kapazität des Dienstes ist ungültig.',
        AssignmentErrorCode.physicianNotEligible =>
          'Der Rang ist für diese Rolle nicht zugelassen.',
        AssignmentErrorCode.blockingAbsence =>
          'Eine Abwesenheit verhindert die Zuweisung.',
        AssignmentErrorCode.overlappingAssignment =>
          'Ein bestehender oder ebenfalls ausgewählter Dienst überschneidet sich zeitlich.',
        AssignmentErrorCode.slotFull =>
          'Dienst vollständig besetzt. Bestehende Zuweisungen werden nicht entfernt.',
        AssignmentErrorCode.duplicateAssignment =>
          'Person ist diesem Dienst bereits zugewiesen.',
        AssignmentErrorCode.rosterNotEditable =>
          'Dienstplan kann in dieser Phase nicht bearbeitet werden.',
        AssignmentErrorCode.missingSlot =>
          'Kein konkreter Dienst für diese Rolle an diesem Datum.',
        AssignmentErrorCode.inactivePhysician =>
          'Person ist inaktiv und kann nicht neu zugewiesen werden.',
        AssignmentErrorCode.invalidPhase => 'Ungültige Dienstplanphase.',
        AssignmentErrorCode.ambiguousSlot =>
          'Mehrere Dienste passen zu dieser Rolle und diesem Datum. Eindeutige Dienstauswahl erforderlich.',
        AssignmentErrorCode.staleVersion =>
          'Dienstplan geändert. Neu laden und Vorschau prüfen.',
        AssignmentErrorCode.validationUnavailable =>
          'Prüfdaten sind unvollständig. Dienstplan neu laden.',
      };
String validationWarningText(
  AdminStrings strings,
  AssignmentValidationWarning warning,
) => strings.language != 'de'
    ? warning.message
    : switch (warning.code) {
        AssignmentWarningCode.correctionReasonRequired =>
          'Gesperrter Dienstplan: Korrekturbegründung erforderlich.',
        AssignmentWarningCode.allowedOverlap =>
          'Zeitliche Überschneidung; die gemeinsame Rollenregel erlaubt diese Kombination.',
        AssignmentWarningCode.incompleteWorkloadHistory =>
          'Die Dienstplanhistorie der vorherigen 90 Tage ist unvollständig.',
        AssignmentWarningCode.heavyRecentDutyBurden =>
          'Hohe Dienstbelastung im vorangegangenen Zeitraum.',
        AssignmentWarningCode.weekendImbalance =>
          'Ungleichmäßige Wochenendbelastung.',
        AssignmentWarningCode.targetRoleOverAllocation =>
          'Überdurchschnittliche Belastung in dieser Rolle.',
      };
