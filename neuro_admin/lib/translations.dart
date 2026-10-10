// English source keys, German values. Parameters are named and tested.
const englishLabels = <String, String>{
  'resident': 'Resident',
  'specialist': 'Specialist',
  'seniorSpecialist': 'Senior specialist',
  'consultant': 'Consultant',
  'head': 'Head of department',
  'canLead': 'Leadership',
  'canWorkOutpatientClinic': 'Outpatient clinic',
  'canDoNeurosonography': 'Neurosonography',
  'canDoNightDuty': 'Night duty',
  'canSupervise': 'Supervision',
};
const german = <String, String>{
  'SUPABASE_URL must be a valid HTTP or HTTPS URL.':
      'SUPABASE_URL muss eine gültige HTTP- oder HTTPS-Adresse sein.',
  'Use a Supabase publishable key, never a secret key.':
      'Einen öffentlichen Supabase-Schlüssel verwenden, keinen geheimen Schlüssel.',
  'Use a Supabase publishable key, never a service-role key.':
      'Einen öffentlichen Supabase-Schlüssel verwenden, keinen Service-Role-Schlüssel.',
  'Invalid Supabase public key.': 'Ungültiger öffentlicher Supabase-Schlüssel.',
  'The invitation endpoint rejected the session. Sign in again and check the Edge Function deployment.':
      'Der Einladungsdienst hat die Sitzung abgelehnt. Erneut anmelden und die Bereitstellung der Edge Function prüfen.',
  'Deploy the updated invite-doctor function before inviting viewers.':
      'Vor dem Einladen von Lesekonten die aktualisierte Funktion invite-doctor bereitstellen.',
  'Vacation': 'Urlaub',
  'Sick leave': 'Krankenstand',
  'Conference': 'Kongress',
  'External rotation': 'Externe Rotation',
  '24h duty': '24-h-Dienst',
  'Post-duty': 'Nach Dienst',
  'EF day': 'EF-Tag',
  'ZAM late shift': 'Spätdienst im ZAM',
  'ZAM daytime': 'ZAM tagsüber',
  'Other outpatient clinic': 'Andere Ambulanz',
  'Other absence': 'Andere Abwesenheit',
  '24-hour counts use recorded day markers, not duty-role assignments.':
      '24-Stunden-Dienste werden anhand gespeicherter Tagesmarkierungen gezählt, nicht anhand von Rollenzuweisungen.',
  'Invalid email or password.': 'E-Mail-Adresse oder Passwort ungültig.',
  'Roster calendar': 'Dienstplankalender',
  'Desktop administrator client': 'Desktop-Administratoranwendung',
  'Supabase configuration not provided': 'Supabase-Konfiguration fehlt',
  'Supabase is not initialized. Restart with valid configuration.':
      'Supabase ist nicht initialisiert. Mit gültiger Konfiguration neu starten.',
  'Could not initialize Supabase. Check configuration and restart the app.':
      'Supabase konnte nicht initialisiert werden. Konfiguration prüfen und App neu starten.',
  '{p0} target dates': '{p0} Zieltage',
  '{p0} assignments / {p1} days': '{p0} Zuweisungen / {p1} Tage',
  'Rank: {p0}': 'Rang: {p0}',
  'Capabilities: {p0}': 'Qualifikationen: {p0}',
  'Current month: {p0} confirmed / {p1} provisional':
      'Aktueller Monat: {p0} bestätigt / {p1} vorläufig',
  'Previous 90 days: {p0} to {p1}': 'Vorherige 90 Tage: {p0} bis {p1}',
  '{p0}/90 roster dates available. Missing dates may mean incomplete history.':
      '{p0}/90 Dienstplantage vorhanden. Fehlende Tage können auf eine unvollständige Historie hinweisen.',
  '{p0} recorded 24-hour duty days': '{p0} gespeicherte 24-Stunden-Diensttage',
  '{p0} on Saturdays/Sundays': '{p0} an Samstagen/Sonntagen',
  '{p0} station-role days': '{p0} Stationstage',
  '{p0} ambulance-role days': '{p0} Ambulanztage',
  '{p0} science-role days': '{p0} Wissenschaftstage',
  '{p0} other-role days': '{p0} Tage in anderen Rollen',
  '{p0} confirmed / {p1} provisional assignments':
      '{p0} bestätigte / {p1} vorläufige Zuweisungen',
  '{p0} - {p1}: {p2} days / {p3} assignments':
      '{p0} - {p1}: {p2} Tage / {p3} Zuweisungen',
  '90 days: 24h {p0} (weekend {p1}) | station {p2} | ambulance {p3} | science {p4}':
      '90 Tage: 24h {p0} (Wochenende {p1}) | Station {p2} | Ambulanz {p3} | Wissenschaft {p4}',
  'Current month: {p0} assignments / {p1} days; {p2} confirmed / {p3} provisional':
      'Aktueller Monat: {p0} Zuweisungen / {p1} Tage; {p2} bestätigt / {p3} vorläufig',
  'Assignment preview - {p0} target dates':
      'Zuweisungsvorschau – {p0} Zieltage',
  '{p0} valid | {p1} valid with warnings | {p2} blocked':
      '{p0} gültig | {p1} gültig mit Warnungen | {p2} gesperrt',
  '{p0} proposed additions; no replacements':
      '{p0} vorgeschlagene Zuweisungen; keine Ersetzungen',
  '{p0} {p1} - {p2}; capacity {p3}': '{p0} {p1} - {p2}; Kapazität {p3}',
  'Current: {p0}': 'Aktuell: {p0}',
  'Proposed: {p0}': 'Vorgeschlagen: {p0}',
  'Warning: {p0}': 'Warnung: {p0}',
  '{p0} dates; all-or-nothing': '{p0} Tage; nur gemeinsam speicherbar',
  '{p0} selected dates with warnings': '{p0} ausgewählte Tage mit Warnungen',
  '{p0}-{p1} · DRAFT': '{p0}-{p1} · ENTWURF',
  '{p0} calendar days · {p1} weekdays · {p2} Austrian holidays':
      '{p0} Kalendertage · {p1} Wochentage · {p2} österreichische Feiertage',
  '{p0} slots to add · {p1} to remove · {p2} assignments affected':
      '{p0} Dienste hinzufügen · {p1} entfernen · {p2} betroffene Zuweisungen',
  'Remove {p0} assignments across {p1} selected days?':
      '{p0} Zuweisungen an {p1} ausgewählten Tagen entfernen?',
  '{p0}: no matching assignments (no change)':
      '{p0}: keine passenden Zuweisungen (keine Änderung)',
  'ALL ROLES on selected days': 'ALLE ROLLEN an ausgewählten Tagen',
  'I confirm removal of exactly the assignments listed above.':
      'Ich bestätige, dass genau die oben aufgeführten Zuweisungen entfernt werden.',
  'Click to select a day. Drag to select a range. In assignment mode, valid days toggle and drag adds valid days. Use removal selection to select occupied days.':
      'Klicken wählt einen Tag aus. Ziehen wählt einen Bereich aus. Im Zuweisungsmodus werden gültige Tage umgeschaltet; Ziehen fügt gültige Tage hinzu. Zum Auswählen belegter Tage die Auswahl zum Entfernen verwenden.',
  '{available} assignable | {selected} selected | {blocked} blocked | {warnings} warning-only':
      '{available} zuweisbar | {selected} ausgewählt | {blocked} gesperrt | {warnings} nur Warnungen',
  'No generated roster day for {date}.':
      'Kein angelegter Dienstplantag für {date}.',
  '{count} duties': '{count} Dienste',
  '{name} (inactive)': '{name} (inaktiv)',
  '{available}/{total} dates available; {blocked} blocked':
      '{available}/{total} Tage verfügbar; {blocked} gesperrt',
  'Server rejected the operation ({code}). No assignments were added.':
      'Server hat den Vorgang abgelehnt ({code}). Keine Zuweisungen hinzugefügt.',
  'Preview unavailable ({code}). Check the workspace migration and access.':
      'Vorschau nicht verfügbar ({code}). Workspace-Migration und Zugriff prüfen.',
  'Generation rejected. Reload the preview ({code}).':
      'Generierung abgelehnt. Vorschau neu laden ({code}).',
  'Removal rejected ({code}). Close and reload.':
      'Entfernen abgelehnt ({code}). Schließen und neu laden.',
  'expired preview': 'Vorschau abgelaufen',
  'invalid request': 'Ungültige Anfrage',
  'Language': 'Sprache',
  'Reports': 'Berichte',
  'Roster': 'Dienstplan',
  'Selection ?': 'Auswahl',
  'Roster ?': 'Dienstplan',
  'Selection actions': 'Auswahlaktionen',
  'Roster actions': 'Dienstplanaktionen',
  'Select all working days': 'Alle Arbeitstage auswählen',
  'Select all assignable days': 'Alle zuweisbaren Tage auswählen',
  'Clear selection': 'Auswahl aufheben',
  'Select occupied days for removal': 'Belegte Tage zum Entfernen auswählen',
  'Unassign selected role': 'Zuweisungen der ausgewählten Rolle entfernen',
  'Unassign all roles on selected days':
      'Alle Zuweisungen an ausgewählten Tagen entfernen',
  'Create month roster': 'Monatsdienstplan erstellen',
  'Regenerate draft roster': 'Dienstplanentwurf neu generieren',
  'Removal selection': 'Auswahl zum Entfernen',
  'Refresh': 'Neu laden',
  'Reload report': 'Bericht neu laden',
  'Sign out': 'Abmelden',
  'Retry': 'Erneut versuchen',
  'No rosters have been generated yet.':
      'Es wurden noch keine Dienstpläne erstellt.',
  'Could not load roster data. Check your connection and access, then retry.':
      'Dienstplan konnte nicht geladen werden. Verbindung und Zugriffsrechte prüfen und erneut versuchen.',
  'Could not sign out. Please retry.':
      'Abmeldung fehlgeschlagen. Bitte erneut versuchen.',
  'Roster changed; reload failed. Retry loading before previewing.':
      'Dienstplan geändert; Laden fehlgeschlagen. Vor der Vorschau erneut laden.',
  'Assignments saved, but reload failed. Retry loading to refresh workload.':
      'Zuweisungen gespeichert; Laden fehlgeschlagen. Zur Aktualisierung der Belastung erneut laden.',
  'Roster changed. Data reloaded; review the updated preview.':
      'Dienstplan geändert und neu geladen. Bitte die aktualisierte Vorschau prüfen.',
  'Assignments saved. Roster and workload refreshed.':
      'Zuweisungen gespeichert. Dienstplan und Belastung aktualisiert.',
  'Read-only totals include all roster phases. Times use Europe/Vienna; calendar dates follow the stored roster day.':
      'Die Statistik berücksichtigt alle Dienstplanphasen. Zeitzone: Europe/Vienna; maßgeblich ist das gespeicherte Dienstplandatum.',
  'Month validation failed. Reload to retry.':
      'Monatsprüfung fehlgeschlagen. Bitte erneut laden.',
  'Checking month assignability...': 'Zuweisbarkeit des Monats wird geprüft …',
  'Published roster requires a new revision before editing.':
      'Ein veröffentlichter Dienstplan benötigt vor der Bearbeitung eine neue Revision.',
  'Locked roster: corrections require a reason.':
      'Gesperrter Dienstplan: Korrekturen benötigen eine Begründung.',
  'Mon': 'Mo',
  'Tue': 'Di',
  'Wed': 'Mi',
  'Thu': 'Do',
  'Fri': 'Fr',
  'Sat': 'Sa',
  'Sun': 'So',
  'Daily roster': 'Tagesdienstplan',
  'Current role occupants (no replacements)':
      'Aktuelle Besetzung der Rolle (ohne Ersetzungen)',
  'Select a generated day to inspect its duties.':
      'Einen angelegten Tag auswählen, um seine Dienste anzuzeigen.',
  'Public holiday': 'Feiertag',
  'No duties on this day.': 'Keine Dienste an diesem Tag.',
  'Absences / day markers': 'Abwesenheiten / Tagesmarkierungen',
  'Blocked': 'Gesperrt',
  'Assignable with warning': 'Zuweisbar mit Warnung',
  'Assignable': 'Zuweisbar',
  'No matching slot or awaiting validation':
      'Kein passender Dienst oder Prüfung ausstehend',
  'Calendar day': 'Kalendertag',
  'Selected': 'Ausgewählt',
  'No roster day': 'Kein Dienstplantag',
  'No slot': 'Kein Dienst',
  'Unassigned': 'Unbesetzt',
  'Multiple slots - ambiguous. ': 'Mehrere Dienste – nicht eindeutig. ',
  'Physicians / workload': 'Ärzt:innen / Belastung',
  'Select a physician to inspect workload by stored role.':
      'Eine Person auswählen, um die Belastung nach gespeicherter Rolle anzuzeigen.',
  'Clear physician selection': 'Ärzt:innenauswahl aufheben',
  'No physicians available.': 'Keine Ärzt:innen vorhanden.',
  'Categories use SUL/SU1/SU2, AMB and SCI. Other codes remain separate. All phases and assignment states are included.':
      'Kategorien: SUL/SU1/SU2, AMB und SCI. Andere Codes bleiben getrennt. Alle Phasen und Zuweisungsstände sind enthalten.',
  'No recorded role assignments.': 'Keine gespeicherten Rollenzuweisungen.',
  'Draft': 'Entwurf',
  'Open for selection': 'Zur Auswahl geöffnet',
  'Locked': 'Gesperrt',
  'Published': 'Veröffentlicht',
  'Administrator working plan': 'Arbeitsplan der Administration',
  'Selection period — not published': 'Auswahlphase – nicht veröffentlicht',
  'Selection closed — not published':
      'Auswahl geschlossen – nicht veröffentlicht',
  'Authoritative roster for end users':
      'Verbindlicher Dienstplan für Benutzer:innen',
  'Preview could not be calculated. Reload the roster and retry.':
      'Vorschau konnte nicht berechnet werden. Dienstplan neu laden und erneut versuchen.',
  'Administrator MFA access could not be verified. Sign in again.':
      'Administratorzugriff mit Zwei-Faktor-Authentifizierung konnte nicht bestätigt werden. Bitte erneut anmelden.',
  'The response was not received. The operation may have succeeded. Retry the same request to check safely.':
      'Keine Antwort erhalten. Der Vorgang könnte erfolgreich gewesen sein. Dieselbe Anfrage zur sicheren Prüfung wiederholen.',
  'Operation outcome is unknown. Retry the same request to check safely.':
      'Ergebnis unbekannt. Dieselbe Anfrage zur sicheren Prüfung wiederholen.',
  'Physician candidates': 'Ärzt:innenauswahl',
  'Cancel preview': 'Vorschau schließen',
  'All': 'Alle',
  'Eligible': 'Qualifiziert',
  'Available': 'Verfügbar',
  'No physicians match this filter.':
      'Keine Ärzt:innen entsprechen diesem Filter.',
  'Select a physician to check the whole month.':
      'Eine Person auswählen, um den gesamten Monat zu prüfen.',
  'Select an assignable date to preview additions.':
      'Ein zuweisbares Datum für die Vorschau auswählen.',
  'Preview only - assignment writes are not enabled yet.':
      'Nur Vorschau – Zuweisungen können noch nicht gespeichert werden.',
  'Preview only: backend versioning migration is required.':
      'Nur Vorschau: Die Backend-Migration zur Versionierung ist erforderlich.',
  'All dates must pass server validation; no partial assignments.':
      'Alle Tage müssen die Serverprüfung bestehen; keine Teilzuweisungen.',
  'Verified administrator MFA session required':
      'Bestätigte Administrator-Sitzung mit Zwei-Faktor-Authentifizierung erforderlich',
  'Confirm all selected dates': 'Alle ausgewählten Tage bestätigen',
  'Applying...': 'Wird gespeichert …',
  'Retry same request': 'Dieselbe Anfrage wiederholen',
  'Apply assignments': 'Zuweisungen speichern',
  'Checking...': 'Wird geprüft …',
  'Eligible with warnings': 'Qualifiziert mit Warnungen',
  'Eligible and available': 'Qualifiziert und verfügbar',
  'None': 'Keine',
  'Valid with warnings': 'Gültig mit Warnungen',
  'Valid': 'Gültig',
  'Confirm assignments': 'Zuweisungen bestätigen',
  'Correction reason (required)': 'Korrekturbegründung (erforderlich)',
  'Cancel': 'Abbrechen',
  'Confirm and apply': 'Bestätigen und speichern',
  'A roster already exists. Open that month and use draft regeneration.':
      'Dienstplan bereits vorhanden. Monat öffnen und den Entwurf neu generieren.',
  'Only a draft roster can be regenerated. Published history is protected.':
      'Nur Entwürfe können neu generiert werden. Veröffentlichte Dienstpläne sind geschützt.',
  'Occupied slots would be removed. Reconcile those assignments before regeneration.':
      'Belegte Dienste würden entfernt. Diese Zuweisungen vor dem Generieren bearbeiten.',
  'A template time falls in a daylight-saving gap or repeated hour. Review the template.':
      'Eine Vorlagenzeit liegt in einer Zeitumstellungslücke oder doppelt vorkommenden Stunde. Vorlage prüfen.',
  'A monthly template has no valid day of month.':
      'Eine Monatsvorlage enthält keinen gültigen Monatstag.',
  'The original roster is no longer available. Reload.':
      'Der ursprüngliche Dienstplan ist nicht mehr verfügbar. Neu laden.',
  'Generation is blocked. Reload and review the roster configuration.':
      'Generierung gesperrt. Neu laden und die Dienstplankonfiguration prüfen.',
  'Enter a valid year (2000–2100) and reload the roster if needed.':
      'Gültiges Jahr (2000–2100) eingeben und den Dienstplan gegebenenfalls neu laden.',
  'Response uncertain. Retry the same request, or close and reload before starting another operation.':
      'Ergebnis unklar. Dieselbe Anfrage wiederholen oder schließen und vor einem neuen Vorgang neu laden.',
  'Response uncertain. Retry the same request, or close and reload before another removal.':
      'Ergebnis unklar. Dieselbe Anfrage wiederholen oder schließen und vor einer weiteren Entfernung neu laden.',
  'Year': 'Jahr',
  'Duty': 'Dienst',
  'Weekday templates also create holiday slots. Existing assignments are preserved; destructive regeneration is blocked.':
      'Wochentagsvorlagen erzeugen auch Dienste an Feiertagen. Bestehende Zuweisungen bleiben erhalten; ihre Entfernung durch Neugenerierung wird verhindert.',
  'Close': 'Schließen',
  'Preview': 'Vorschau',
  'Create roster': 'Dienstplan erstellen',
  'Regenerate draft': 'Entwurf neu generieren',
  'Selected role only': 'Nur ausgewählte Rolle',
  'Remove assignments': 'Zuweisungen entfernen',
  'Administrator sign-in': 'Administrator-Anmeldung',
  'Email': 'E-Mail',
  'Password': 'Passwort',
  'Hide password': 'Passwort verbergen',
  'Show password': 'Passwort anzeigen',
  'Sign in': 'Anmelden',
  'Use your existing NeuroDienst administrator account. Password recovery and MFA enrollment are available in the existing app.':
      'Mit dem bestehenden NeuroDienst-Administratorkonto anmelden. Passwortwiederherstellung und Einrichtung der Zwei-Faktor-Authentifizierung sind in der bestehenden App verfügbar.',
  'Session verification unavailable.': 'Sitzungsprüfung nicht verfügbar.',
  'Session verification failed. Sign out and try again.':
      'Sitzungsprüfung fehlgeschlagen. Abmelden und erneut versuchen.',
  'Could not complete authentication. Please retry.':
      'Anmeldung konnte nicht abgeschlossen werden. Bitte erneut versuchen.',
  'Could not verify administrator access.':
      'Administratorzugriff konnte nicht bestätigt werden.',
  'Administrator access required. This desktop client is not available to doctor or viewer accounts.':
      'Administratorzugriff erforderlich. Diese Desktop-App steht Arzt- und Lesekonten nicht zur Verfügung.',
  'Set up an authenticator in the existing NeuroDienst app, then retry.':
      'Authentifikator in der bestehenden NeuroDienst-App einrichten und erneut versuchen.',
  'Two-factor verification': 'Zwei-Faktor-Authentifizierung',
  'Authenticator code': 'Authentifikator-Code',
  'Authenticator': 'Authentifikator',
  'Verify': 'Bestätigen',
  'Enter a six-digit authenticator code.':
      'Sechsstelligen Authentifikator-Code eingeben.',
  'Date': 'Datum',
  'Absences / holiday': 'Abwesenheiten / Feiertag',
  'By role': 'Nach Rolle',
  'By physician': 'Nach Ärzt:in',
  'Unknown physician': 'Unbekannte Person',
  'Report unavailable or changed. Retry (reload roster if changed).':
      'Bericht nicht verfügbar oder geändert. Erneut versuchen (bei Änderung Dienstplan neu laden).',
  'Print / PDF': 'Drucken / PDF',
  'A4 Portrait': 'A4 Hochformat',
  'A4 Landscape': 'A4 Querformat',
  'Save PDF': 'PDF speichern',
  'Print': 'Drucken',
  'Page {page} of {total}': 'Seite {page} von {total}',
  'Administration': 'Administration',
  'Physicians': 'Ärzt:innen',
  'Viewers': 'Lesekonten',
  'Users': 'Benutzer:innen',
  'Invite physician': 'Ärzt:in einladen',
  'Invite viewer': 'Lesekonto einladen',
  'First name': 'Vorname',
  'Last name': 'Nachname',
  'Display name': 'Anzeigename',
  'Rank': 'Rang',
  'Capabilities': 'Qualifikationen',
  'Active': 'Aktiv',
  'Inactive': 'Inaktiv',
  'Print order': 'Druckreihenfolge',
  'Search name or email': 'Name oder E-Mail suchen',
  'Edit': 'Bearbeiten',
  'Deactivate': 'Deaktivieren',
  'Reactivate': 'Reaktivieren',
  'Delete': 'Löschen',
  'Revoke access': 'Zugriff entziehen',
  'Restore access': 'Zugriff wiederherstellen',
  'Access revoked': 'Zugriff entzogen',
  'Account linked': 'Konto verknüpft',
  'No account linked': 'Kein Konto verknüpft',
  'Save': 'Speichern',
  'Invite': 'Einladen',
  'Required': 'Erforderlich',
  'Enter a valid email address.': 'Gültige E-Mail-Adresse eingeben.',
  'Enter a whole number.': 'Ganze Zahl eingeben.',
  'Directory unavailable. Check the migration, connection and administrator access.':
      'Verzeichnis nicht verfügbar. Migration, Verbindung und Administratorzugriff prüfen.',
  'Saved.': 'Gespeichert.',
  'Invitation sent.': 'Einladung gesendet.',
  'Historical records are retained.': 'Historische Daten bleiben erhalten.',
  'Delete this unused physician record? The login account will remain.':
      'Diesen unbenutzten Arzt-Datensatz löschen? Das Anmeldekonto bleibt erhalten.',
  'History or dependent records prevent deletion. Deactivate the physician instead.':
      'Historische Daten oder abhängige Datensätze verhindern das Löschen. Person stattdessen deaktivieren.',
  'Data changed. Close and reload before editing again.':
      'Daten geändert. Vor weiterer Bearbeitung schließen und neu laden.',
  'Operation failed. Check your access and connection.':
      'Vorgang fehlgeschlagen. Zugriff und Verbindung prüfen.',
  'Outcome unknown. Retry the same request safely.':
      'Ergebnis unbekannt. Dieselbe Anfrage sicher wiederholen.',
  'Invitation outcome unknown. Close and reload the directory before retrying.':
      'Einladungsergebnis unbekannt. Vor einem erneuten Versuch schließen und das Verzeichnis neu laden.',
  'An account with this email already exists.':
      'Ein Konto mit dieser E-Mail-Adresse existiert bereits.',
  'resident': 'Assistenzärzt:in',
  'specialist': 'Fachärzt:in',
  'seniorSpecialist': 'Oberärzt:in',
  'consultant': 'Leitende Oberärzt:in',
  'head': 'Abteilungsleitung',
  'canLead': 'Leitung',
  'canWorkOutpatientClinic': 'Ambulanz',
  'canDoNeurosonography': 'Neurosonografie',
  'canDoNightDuty': 'Nachtdienst',
  'canSupervise': 'Supervision',
  'confirmed': 'Bestätigt',
  'provisional': 'Vorläufig',
};
