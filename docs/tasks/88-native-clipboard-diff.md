---
issue: 88
repo: ww3d/markdown-workbench
slug: native-clipboard-diff
title: Native clipboard diff with an editable, memory-only candidate
---

# Nativer Clipboard-Diff (ww3d/markdown-workbench#88)

Anforderungen aus dem Auftrag zu ww3d/markdown-workbench#82 (Decision-Log als `docs/DECISIONS.md`
#48). Je REQ eine widerlegbare Aussage, abgehakt oder `nicht geliefert: <Grund>`.

## Ort und Grundmechanik

- [x] REQ-01: Der neue Code liegt in einem Fachordner unter `src/` (`src/clipboard-diff/`), die Tests
      gespiegelt im gleichnamigen Ordner unter `tests/`.
- [x] REQ-02: Die Module fuer Anker, Stil, Entpacker/Platzhalter, Pruefung und Verlauf importieren
      `vscode` nicht und sind mit `node --test` ohne Attrappe testbar.
- [x] REQ-03: Das Test-Glob in `package.json` und `build.ps1` erfasst die Tests im neuen Ordner.
- [x] REQ-04: Die c8-Includes erfassen die neuen Dateien; die Grenzwerte bleiben unveraendert.
- [x] REQ-05: Der Candidate liegt unter einem eigenen Schema und kommt von einem
      `FileSystemProvider` im Speicher; er ist im Diff bearbeitbar.
- [x] REQ-06: Jede Aenderung an einem Candidate-Dokument wird sofort gespeichert
      (`onDidChangeTextDocument` → `document.save()`, nur eigenes Schema); `writeFile` schreibt nur in
      den Speicher, `stat` liefert danach eine hoehere mtime.
- [x] REQ-07: Der Inhalt eines Candidate wird freigegeben, sobald kein Tab mehr seine URI zeigt
      (`tabGroups.onDidChangeTabs`), und beim `deactivate`.
- [x] REQ-08: Der Clipboard-Inhalt erscheint in keiner Log-Ausgabe und keinem Fehlertext und wird
      nirgends persistiert (auch nicht in `globalState`/`workspaceState`).

## Compare

- [x] REQ-09: "Compare with Clipboard" oeffnet `vscode.diff(baseline, candidate)` ohne
      Titelargument.
- [x] REQ-10: Die virtuellen Seiten tragen ihre Rolle im Dateinamen und die Endung der Baseline.
- [x] REQ-11: Bei einer nicht-leeren Auswahl ist die Baseline eine virtuelle Seite mit dem
      Auswahltext.
- [x] REQ-12: Bei mehreren nicht-leeren Auswahlen ist die Baseline der Huellbereich in
      Dokumentreihenfolge, mit kurzer Meldung.
- [x] REQ-13: Ohne Auswahl bestimmt der Abschnitts-Anker den Baseline-Bereich; ohne Treffer ist die
      Baseline die Live-Datei.
- [x] REQ-14: Die Zeilenenden des Clipboard-Texts werden beim Aufnehmen an die Baseline angeglichen.
- [x] REQ-15: Eine leere Zwischenablage fuehrt zu einer klaren Meldung, ohne Diff.
- [x] REQ-16: Eine Untitled-Datei funktioniert als Baseline.
- [x] REQ-17: Ist der aktive Tab kein Text-Editor, kommt eine klare Meldung.

## Tausch

- [x] REQ-18: "Swap Diff Sides" ruft `workbench.action.compareEditor.swapSides` per
      `executeCommand` fuer eigene und fremde Diffs auf und ist frei bindbar.
- [x] REQ-19: Jeder Fehler beim Tausch wird abgefangen und klar gemeldet; kein Versionszweig.
- [x] REQ-20: Zweimal tauschen stellt die Ausgangsorientierung wieder her, samt Tab-Titel.

## Uebernehmen

- [x] REQ-21: "Apply Candidate" schreibt den Candidate in den Baseline-Bereich als einen
      Undo-Schritt.
- [x] REQ-22: Der Baseline-Bereich wird bei Aenderungen der Datei ueber `contentChanges`
      nachgefuehrt.
- [x] REQ-23: Wurde der Baseline-Bereich selbst geaendert, fragt "Apply Candidate" modal nach.
- [x] REQ-24: Uebernehmen je Hunk laeuft nur ueber die eingebauten Pfeile, in beiden
      Orientierungen wie beschrieben; keine Proposed API, kein `diffEditor.revert` mit Argumenten.
- [x] REQ-25: Vor dem Schreiben laufen die Pruefung und das Auffuellen der Platzhalter.

## F1+a Abschnitts-Anker

- [x] REQ-26: Ein Candidate mit fuehrender Ueberschrift waehlt den gleichnamigen Abschnitt bis zur
      naechsten Ueberschrift gleicher oder hoeherer Ebene (Spannen aus `token.map`).
- [x] REQ-27: Sonst sucht ein Zeilen-Hash-Index die erste und letzte Candidate-Zeile und prueft die
      Ueberlappung an hoechstens K Stellen; K und die Konfidenz-Schwelle sind benannte Konstanten.
- [x] REQ-28: Unsicherer oder mehrdeutiger Treffer: QuickPick mit den Kandidaten und "ganze Datei".
- [x] REQ-29: Der gefundene Bereich ist sichtbar (Sprung per `TextDocumentShowOptions.selection`,
      Meldung mit der Spanne).
- [x] REQ-30: Laufzeit des Ankers auf 10 000 Zeilen gemessen und im PR-Body belegt, Ziel < 100 ms.

## e Vergleich mit frueheren Clipboards

- [x] REQ-31: Jeder selbst gelesene Clipboard-Text kommt in einen Ringpuffer im Speicher;
      `maxEntries`/`maxBytes` sind benannte Konstanten, ein zu grosser Eintrag wird verworfen.
- [x] REQ-32: "Compare with Earlier Clipboard" zeigt einen QuickPick mit Zeitstempel und
      Kurzvorschau und oeffnet den Eintrag gegen dieselbe Baseline-Logik.

## F2 Markdown-Stil angleichen

- [x] REQ-33: Stilprofil aus der Baseline (Aufzaehlungszeichen, Emphasis-Marker,
      Tabellenpolsterung ueber die Tabellenlogik aus `src/editing.js`), mit der markdown-it-Instanz aus
      `src/render.js`.
- [x] REQ-34: Die Angleichung ersetzt nur Marker an ihren Quellpositionen, serialisiert nie neu,
      greift nie in Inline-Code, Codebloecke, Fences, HTML und Front Matter und aendert keine
      Absatz-Umbrueche.
- [x] REQ-35: Ein sichtbarer Umschalter wechselt roh/angeglichen, der Zustand ist im Diff erkennbar;
      nach Nutzer-Aenderungen fragt er vorher.

## F3 KI-Antwort entpacken, Auslassungs-Waechter

- [x] REQ-36: Aeussere Fence-Huelle und Chat-Saetze an den Raendern werden entfernt; die Regeln
      stehen als benannte Liste mit Tests.
- [x] REQ-37: Platzhalter-Zeilen aus einer festen, benannten Musterliste werden markiert; beim
      Uebernehmen wird der verdeckte Baseline-Text per Ausrichtung der Nachbarzeilen eingefuellt.
- [x] REQ-38: Bei unklarer Ausrichtung fragt die Extension nach und raet nicht.
- [x] REQ-39: Ein echtes "…" im Fliesstext loest nichts aus (Gegenprobe als Test).

## F4 Markdown-Pruefung vor dem Uebernehmen

- [x] REQ-40: Zurueckgesetzte Checkboxen werden gemeldet, mit Ein-Klick-Korrektur; die
      Checkbox-Definition ist `CHECKBOX_RE`, wiederverwendet.
- [x] REQ-41: Verlorene Fussnoten- und Referenz-Link-Definitionen werden gemeldet.
- [x] REQ-42: Entferntes oder geaendertes Front Matter wird gemeldet.
- [x] REQ-43: Umbenannte oder entfernte Ueberschriften mit `#anker`-Verweisen werden gemeldet;
      Standard eigene Datei, arbeitsbereichsweit nur per Einstellung.
- [x] REQ-44: Alle Befunde sind Hinweise, keine Sperre (Gegenprobe als Test).

## Tests

- [x] REQ-45: `tests/helpers/vscode-mock.js` ist um `window.tabGroups`, `TabInputTextDiff`,
      `env.clipboard`, `workspace.registerFileSystemProvider` und `workspace.fs` erweitert; die
      Bindungslogik ist dort mit Tests abgedeckt.
- [x] REQ-46: Jede reine Regel hat Tests fuer Normalfall, Randfaelle und eine Gegenprobe.
- [x] REQ-47: `@vscode/test-electron` ist exakt auf die aktuelle stabile Version gepinnt; Befehl
      und Ausgabe der Registry-Abfrage stehen im PR-Body.
- [x] REQ-48: Die Integrationstests nutzen einen eigenen Runner ohne Mocha (`tests/integration/`).
- [x] REQ-49: Jeder Integrationslauf nutzt ein frisches `--user-data-dir` im Temp-Verzeichnis,
      `--disable-extensions` und einen Workspace aus `tests/integration/fixtures/`. Ausnahme: der
      Waechter-Lauf im normalen Fenster nimmt ein frisches `--extensions-dir` statt
      `--disable-extensions`, weil das die installierte `.vsix` abschalten wuerde (DECISIONS.md #48).
- [x] REQ-50: Die Integrationstests laufen gegen die Mindestversion aus `engines.vscode` und gegen
      die aktuelle stabile Version.
- [x] REQ-51: Task `Integration` in `build.ps1`, Skript `test:integration`; `All` faehrt ihn mit,
      unter Linux ueber `xvfb-run -a`.
- [x] REQ-52: `.vscode-test/` steht in `.gitignore` und kommt nicht ins `.vsix`; die Paketpruefung
      bleibt gruen.
- [x] REQ-53: Der Waechter-Test ist rot bei jeder Datei unter `<user-data-dir>/Backups/**/<schema>/`
      waehrend schnellem Tippen, mit `editor.formatOnSave`, beim Tausch, beim Schliessen mit und ohne
      Aenderung und nach einem Neuladen des Fensters.
- [x] REQ-54: Der Waechter-Test ist rot bei Schreibzugriffen mit dem Clipboard-Inhalt und bei
      Log-Ausgaben mit dem Clipboard-Inhalt.
- [x] REQ-55: Mutationsprobe: ohne sofortiges Speichern wird der Waechter-Test rot; Beleg im
      PR-Body.
- [x] REQ-56: `tab.label` zeigt vor und nach dem Tausch die Rollen in richtiger Reihenfolge.
- [x] REQ-57: Ein "Apply Candidate" wird mit einem Undo vollstaendig zurueckgenommen.
- [x] REQ-58: Die Pfeil-Richtung vor und nach dem Tausch entspricht REQ-24.
- [x] REQ-59: Integrationstest zu "Speichern unter": Das Default-Ziel ist die Candidate-URI, und
      ohne Nutzeraktion gibt es keinen Schreibzugriff auf die Platte. Was sich nicht automatisieren
      laesst, kommt als deklarierte manuelle Pruefung mit Schrittliste in den PR-Body.
- [x] REQ-60: Tausch mit einer fremden virtuellen URI gelingt oder meldet sich klar.
- [x] REQ-61: Diagnosen und die Ein-Klick-Korrektur von F3/F4 erscheinen auf der Candidate-Seite.
- [x] REQ-62: Sprung zum Anker und QuickPick bei Mehrdeutigkeit sind integrationsgetestet.

## Doku

- [x] REQ-63: `docs/ARCHITECTURE.md` § "Module layout" nennt den Fachordner, mit Status-Marker.
- [x] REQ-64: `docs/ARCHITECTURE.md` hat einen Abschnitt zum Clipboard-Diff mit Status-Markern.
- [x] REQ-65: `docs/DECISIONS.md` hat den Eintrag #48 in Sprache und Stil der bestehenden Eintraege.
- [x] REQ-66: `README.md` fuehrt die neuen Commands in der Command-Tabelle.
- [x] REQ-67: `README.md` hat einen Feature-Abschnitt mit der Zusage im Wortlaut des Logs und einem
      Verweis auf den Waechter-Test.
- [x] REQ-68: `README.md` erklaert die Richtung der eingebauten Pfeile in beiden Orientierungen.
- [x] REQ-69: `README.md` beschreibt Anker, Verlauf, Stil-Umschalter, Entpacker und Pruefung.
- [x] REQ-70: `CHANGELOG.md` hat einen neuen obersten Eintrag, die Version in `package.json` steigt
      passend.
- [x] REQ-71: `CONTRIBUTING.md` beschreibt den Task `Integration` samt xvfb und die Slot-Regel.

## Save-Aktionen (Entscheid des Controllers auf ww3d/markdown-workbench#88 nach Review-Welle 1)

- [x] REQ-73: Ist die Seite der fokussierte Haupt-Editor, speichert die Extension sie mit
      `workbench.action.files.saveWithoutFormatting`, sonst mit `document.save()`.
- [x] REQ-74: Aenderungen ab dem Speicheraufruf (also auch zwischen `onWillSaveTextDocument` und dem
      Ende des Speicherns) gelten als Save-Aktion und werden nie in die echte Datei durchgeschrieben;
      ausgenommen ist, was nach dem Schreiben kam (REQ-78).
- [x] REQ-75: Integrationstest: Mit `files.trimTrailingWhitespace`, `files.insertFinalNewline` und
      `editor.formatOnSave` an veraendert Tippen im Candidate weder den Candidate noch die Datei.
- [x] REQ-76: Integrationstest: Save-Aktionen auf einer nicht fokussierten Seite erreichen die Datei
      nicht; der Fall ist in `docs/ARCHITECTURE.md` und `docs/DECISIONS.md` #48 benannt.
- [x] REQ-77: Jeder der beiden Tests hat eine Mutationsprobe, die ihn rot macht; Beleg im PR-Body.
- [x] REQ-78: Was die Auswahl-Seite beim did-save ueber den geschriebenen Text hinaus traegt, kam
      nach dem Schreiben und geht in die Datei (Entscheid des Controllers zu F1 in Review-Runde 1
      von ww3d/markdown-workbench#89); ein Test "Tippen waehrend des Speicherns auf der
      Auswahl-Seite" ist ohne den Fix rot.

## Traeger

- [x] REQ-72: Bewusst nicht Gebautes steht im Body von ww3d/markdown-workbench#88, Geliefertes ist
      dort abgehakt.
