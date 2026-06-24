import 'package:flutter/widgets.dart';

import 'app_language.dart';

class AppLocalizations extends InheritedWidget {
  final AppLanguage language;

  const AppLocalizations({
    super.key,
    required this.language,
    required super.child,
  });

  static AppLocalizations of(BuildContext context) {
    final result = context
        .dependOnInheritedWidgetOfExactType<AppLocalizations>();

    assert(result != null, 'No AppLocalizations found in context');
    return result!;
  }

  String t(String key) {
    return switch (language) {
      AppLanguage.german => _de[key] ?? _en[key] ?? key,
      AppLanguage.english => _en[key] ?? key,
    };
  }

  @override
  bool updateShouldNotify(AppLocalizations oldWidget) {
    return language != oldWidget.language;
  }
}

const _en = <String, String>{
  'app.name': 'NeuroDienst',
  'language': 'Language',
  'language.english': 'English',
  'language.german': 'Deutsch',
  'previousMonth': 'Previous month',
  'nextMonth': 'Next month',
  'lightMode': 'Light mode',
  'darkMode': 'Dark mode',
  'admin': 'Admin',
  'signOut': 'Sign out',
  'monthlyReport': 'Monthly report',
  'doctor': 'Doctor',
  'editor': 'Editor',
  'open': 'Open',
  'assigned': 'Assigned',
  'mine': 'Mine',
  'coverage': 'Coverage',
  'warnings': 'Warnings',
  'bulkEditorHint': 'Bulk edits can assign any doctor.',
  'personalPlanning': 'Personal planning for {name}.',
  'daysSelected': '{count} day{plural} selected',
  'deselect': 'Deselect',
  'vacation': 'Vacation',
  'removeVacation': 'Remove vacation',
  'removeRole': 'Remove role',
  'apply': 'Apply',
  'chooseRole': 'Role',
  'noDoctorsConfigured': 'No doctors configured',
  'noDoctorsConfiguredAdmin':
      'Add the first active doctor in Admin to start using the roster with Supabase data.',
  'noDoctorsConfiguredUser':
      'Ask an administrator to add active doctors before using the roster.',
  'openAdmin': 'Open Admin',
  'retry': 'Retry',
  'close': 'Close',
  'rosterWarnings': 'Roster warnings',
  'couldNotSaveVacation': 'Could not save vacation.',
  'couldNotRemoveVacation': 'Could not remove vacation.',
  'vacationSet': 'Vacation set for {count} day{plural}',
  'vacationRemoved': 'Vacation removed from {count} day{plural}',
  'noVacationFound': 'No vacation found on selected days',
  'noSlotsAvailable': 'No slots available on selected days',
  'noEligibleSlotsAvailable':
      'No eligible roles available for {doctor} on selected days',
  'noRoleFound': 'No role found on selected days',
  'assignSelectedDays': 'Assign selected days to role',
  'assignDoctor': 'Assign doctor',
  'assignmentFailed': 'Assignment failed',
  'couldNotSaveAssignment': 'Could not save assignment',
  'couldNotRemoveAssignment': 'Could not remove assignment',
  'assignedStatus':
      'Assigned {doctor} on {assigned} day{assignedPlural}, skipped {skipped}{reason}',
  'roleRemoved': 'Removed {count} role assignment{plural}',
  'mySlotsThisMonth': 'My slots this month',
  'noSlotsAssignedYet': 'No slots assigned yet.',
};

const _de = <String, String>{
  'app.name': 'NeuroDienst',
  'language': 'Sprache',
  'language.english': 'Englisch',
  'language.german': 'Deutsch',
  'previousMonth': 'Vorheriger Monat',
  'nextMonth': 'Naechster Monat',
  'lightMode': 'Heller Modus',
  'darkMode': 'Dunkler Modus',
  'admin': 'Admin',
  'signOut': 'Abmelden',
  'monthlyReport': 'Monatsbericht',
  'doctor': 'Arzt',
  'editor': 'Editor',
  'open': 'Offen',
  'assigned': 'Besetzt',
  'mine': 'Meine',
  'coverage': 'Abdeckung',
  'warnings': 'Warnungen',
  'bulkEditorHint': 'Sammelbearbeitung kann jeden Arzt zuweisen.',
  'personalPlanning': 'Persoenliche Planung fuer {name}.',
  'daysSelected': '{count} Tag{plural} ausgewaehlt',
  'deselect': 'Auswahl aufheben',
  'vacation': 'Urlaub',
  'removeVacation': 'Urlaub entfernen',
  'removeRole': 'Rolle entfernen',
  'apply': 'Anwenden',
  'chooseRole': 'Rolle',
  'noDoctorsConfigured': 'Keine Aerzte konfiguriert',
  'noDoctorsConfiguredAdmin':
      'Fuegen Sie den ersten aktiven Arzt im Admin-Bereich hinzu, um den Dienstplan mit Supabase-Daten zu nutzen.',
  'noDoctorsConfiguredUser':
      'Bitte bitten Sie einen Administrator, aktive Aerzte hinzuzufuegen.',
  'openAdmin': 'Admin oeffnen',
  'retry': 'Erneut versuchen',
  'close': 'Schliessen',
  'rosterWarnings': 'Dienstplan-Warnungen',
  'couldNotSaveVacation': 'Urlaub konnte nicht gespeichert werden.',
  'couldNotRemoveVacation': 'Urlaub konnte nicht entfernt werden.',
  'vacationSet': 'Urlaub fuer {count} Tag{plural} eingetragen',
  'vacationRemoved': 'Urlaub von {count} Tag{plural} entfernt',
  'noVacationFound': 'Kein Urlaub an den ausgewaehlten Tagen gefunden',
  'noSlotsAvailable': 'Keine Dienste an den ausgewaehlten Tagen verfuegbar',
  'noEligibleSlotsAvailable':
      'Keine passenden Rollen fuer {doctor} an den ausgewaehlten Tagen verfuegbar',
  'noRoleFound': 'Keine Rolle an den ausgewaehlten Tagen gefunden',
  'assignSelectedDays': 'Ausgewaehlte Tage einer Rolle zuweisen',
  'assignDoctor': 'Arzt zuweisen',
  'assignmentFailed': 'Zuweisung fehlgeschlagen',
  'couldNotSaveAssignment': 'Zuweisung konnte nicht gespeichert werden',
  'couldNotRemoveAssignment': 'Zuweisung konnte nicht entfernt werden',
  'assignedStatus':
      '{doctor} an {assigned} Tag{assignedPlural} zugewiesen, {skipped} uebersprungen{reason}',
  'roleRemoved': '{count} Rollenzuweisung{plural} entfernt',
  'mySlotsThisMonth': 'Meine Dienste in diesem Monat',
  'noSlotsAssignedYet': 'Noch keine Dienste zugewiesen.',
};

extension AppLocalizationFormatting on AppLocalizations {
  String fill(String key, Map<String, Object> values) {
    var text = t(key);

    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value.toString());
    }

    return text;
  }
}
