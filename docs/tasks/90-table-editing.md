---
issue: 90
repo: ww3d/markdown-workbench
slug: table-editing
title: Markdown-Tabellen im Editor bearbeiten (Enter, Tab, Pfeile, Sortieren, Einfuegen)
---

# Spec: Markdown-Tabellen bearbeiten (#90, Anlass #86)

Entscheidungen: `docs/DECISIONS.md` #48 (D1–D5, E1–E10, T1–T10, K1–K5, X1–X3).

## Modell und Zerlegung (D1)

- [x] REQ-001: Eine Tabellenzeile wird nach GFM zerlegt: `\|` bleibt Zelleninhalt und trennt nicht.
- [x] REQ-002: Ein ungeschuetzter `|` innerhalb eines Code-Spans trennt die Zellen (wie markdown-it 15).
- [x] REQ-003: Eine Tabelle am Cursor wird erkannt wie von der Preview: Kopfzeile plus Trennzeile mit gleicher
      Zellzahl, bis zur Leerzeile oder zum naechsten Block; Randstriche sind optional.
- [x] REQ-004: Tabellen hinter einem Praefix (Einrueckung, Listen-Einrueckung, `>`) werden erkannt; das Praefix
      bleibt bei jeder Aenderung byte-gleich.
- [x] REQ-005: Eine Zeile, die nach dem Praefix mit `|` beginnt und keine Trennzeile hat, gilt fuer Enter (E4) und
      Tab (K2) als Tabellenkopf.
- [x] REQ-006: Die Anzeigebreite einer Zelle wird je Graphem (`Intl.Segmenter`) gemessen: East-Asian Wide/Fullwidth
      (ueber `get-east-asian-width`) und Emoji-Graphemen 2, kombinierende Zeichen 0, sonst 1.
- [x] REQ-007: East-Asian-Ambiguous zaehlt 1, bei `tables.ambiguousWidth: "wide"` 2.
- [x] REQ-008: `get-east-asian-width` steht exakt gepinnt auf 1.7.0 unter `dependencies` (Registry-Stand vorher
      pruefen) und wird von tsdown ins Bundle aufgenommen.
- [x] REQ-009: Der Bundle-Smoke laeuft aus einem isolierten Verzeichnis gruen und deckt die Breitenmessung mit ab.
- [x] REQ-010: Die Befehle Distribute und Consolidate laufen ueber das neue Modell; `a \| b` bleibt nach beiden eine
      Zelle.
- [x] REQ-011: Ausrichten aendert nur Leerzeichen und die Strichzahl der Trennzeile; ein Test prueft das an zufaellig
      erzeugten Tabellen mit festem Seed (ohne Bibliothek).
- [x] REQ-012: Eine randlose Tabelle bleibt nach dem Ausrichten randlos.
- [x] REQ-013: Ausrichtungs-Doppelpunkte der Trennzeile bleiben nach dem Ausrichten erhalten.

## Enter (D2)

- [x] REQ-014: E1 — Enter in einer Datenzeile legt darunter eine leere Zeile gleicher Spaltenzahl an, Cursor in die
      erste Zelle; die Zeile selbst bleibt ungeteilt.
- [x] REQ-015: E2 — Enter vor dem ersten Zelleninhalt (im Praefix oder vor dem ersten `|`) legt eine leere Zeile
      darueber an, Cursor hinein.
- [x] REQ-016: E3/E5 — Enter in der Kopfzeile oder Trennzeile legt die neue Zeile direkt unter der Trennzeile an.
- [x] REQ-017: E4 — Enter in einer Kopfzeile ohne Trennzeile legt Trennzeile und eine leere Datenzeile an, Cursor in
      deren erste Zelle.
- [x] REQ-018: E6 — Enter in der letzten, ganz leeren Zeile macht sie zur Leerzeile; das Praefix bleibt.
- [x] REQ-019: E7 — Enter in einer leeren Zeile mitten in der Tabelle verhaelt sich wie E1.
- [x] REQ-020: E8 — Nach Enter ist die Tabelle ausgerichtet (distribute bzw. K1).
- [x] REQ-021: E8 — Enter plus Ausrichten ist ein einziger Undo-Schritt (Test: ein `undo` stellt den Text vor dem
      Enter her).
- [x] REQ-022: E8 — Das Ausrichten ersetzt nur die geaenderten Bereiche, nie die ganze Tabelle am Stueck.
- [x] REQ-023: E9 — Mit mehreren Cursorn oder einer Markierung laeuft das normale Enter.
- [x] REQ-024: E10 — In Codeblock und Frontmatter greift kein Tabellen-Zweig.
- [x] REQ-025: `tables.enterBehavior: "nextRowSameColumn"` springt stattdessen in dieselbe Spalte der naechsten Zeile
      und legt nur am Tabellenende eine Zeile an.
- [x] REQ-026: Shift+Enter in einer Tabellenzelle fuegt `tables.cellLineBreak` (Vorgabe `<br>`) ein; bei leerem Wert
      laeuft das bisherige Shift+Enter.

## Tab, Shift+Tab, Pfeile (D3)

- [x] REQ-027: T1 — Tab springt zur naechsten Zelle und markiert deren Inhalt; eine leere Zelle bekommt den Cursor.
- [x] REQ-028: T2 — Tab in der letzten Zelle einer Zeile springt in die erste Zelle der naechsten Zeile; die
      Trennzeile wird uebersprungen.
- [x] REQ-029: T3 — Tab in der allerletzten Zelle legt eine neue Zeile wie E1 an.
- [x] REQ-030: T4 — Shift+Tab springt zur vorherigen Zelle (in der ersten Zelle zur letzten Zelle der Vorzeile) und
      markiert sie; in der ersten Kopfzelle aendert es nichts; eine Tabellenzeile wird nie ausgerueckt.
- [x] REQ-031: T5 — Tab/Shift+Tab richten aus, als ein Undo-Schritt; ist die Tabelle schon ausgerichtet, entsteht
      kein Undo-Schritt.
- [x] REQ-032: T6 — Fehlende Zellen einer Zeile werden beim Ausrichten aufgefuellt.
- [x] REQ-033: T7 — Tab mit dem Cursor vor dem ersten `|` springt in die erste Zelle.
- [x] REQ-034: Der Tabellen-Zweig in `onTabKey`/`onShiftTabKey` greift vor dem Spaltenstopp-Zweig fuer markerlose
      Zeilen (DECISIONS.md #27).
- [x] REQ-035: T8 — Eine Markierung ueber mehrere Zeilen behaelt die Block-Einrueckung aus #27.
- [x] REQ-036: T9 — Pfeil hoch/runter in einer Tabelle springt in dieselbe Zelle der Nachbarzeile an die gleiche
      Stelle (sonst ans Zellende) und ueberspringt die Trennzeile.
- [x] REQ-037: T9 — Am Tabellenrand, mit Markierung, mehreren Cursorn, offener Vorschlagsliste oder `editor.wordWrap`
      ungleich `off` laeuft der normale Pfeil.
- [x] REQ-038: T10 — Der Kontext-Schluessel `markdownWorkbench.inTable` wird bei Selektionswechsel berechnet und nur
      bei einer Aenderung gesetzt; die Pfeil-Bindungen haengen an ihm.

## Kandidaten (D4)

- [x] REQ-039: K1 — Uebersteigt die breiteste ausgerichtete Zeile samt Praefix `tables.maxAlignedWidth` (Vorgabe
      100, 0 = keine Grenze) in Anzeigebreite, richtet das automatische Ausrichten consolidate aus.
- [x] REQ-040: K1 — Die Befehle Distribute und Consolidate ignorieren `maxAlignedWidth`.
- [x] REQ-041: K2 — Tab in einer mit `|` beginnenden Zeile ohne Tabelle schliesst die Zelle und legt eine neue leere
      Zelle an, Cursor darin.
- [x] REQ-042: K3 — Eine Code Action „Spalte rechtsbuendig ausrichten“ erscheint fuer eine Spalte ohne eigene
      Ausrichtung, deren Datenzellen nur Zahlen enthalten, und setzt `--:`.
- [x] REQ-043: K3 — Ausrichten (automatisch wie per Befehl) aendert nie die Ausrichtungs-Doppelpunkte.
- [x] REQ-044: K4 — Der Editor-Befehl „Sort table by column“ (auf-/absteigend) sortiert die Datenzeilen nach der
      Spalte am Cursor, numerisch bewusst und stabil, als ein Undo-Schritt.
- [x] REQ-045: K4 — Die Preview zeigt beim Ueberfahren eines Spaltenkopfs einen Sortier-Knopf; ein Klick schickt
      `sortTable` (Tabellenzeile, Spalte, Richtung, Dokumentversion) an den Host.
- [x] REQ-046: K4 — Der Host sortiert auf `sortTable` die Quelle wie REQ-044 und ignoriert eine Nachricht mit
      veralteter Dokumentversion.
- [x] REQ-047: K5 — Eine neue Zeile (E1, T3) traegt `[ ]` in jeder Spalte, deren Zelle in der Ausgangszeile nur aus
      `[ ]`/`[x]` besteht.

## Weitere Ideen (D5)

- [x] REQ-048: X1 — Einfuegen von Tab- oder Komma-getrennten Daten bietet „Als Markdown-Tabelle einfuegen“ an
      (`DocumentPasteEditProvider`); `|` im Inhalt wird `\|`, das Ergebnis ist ausgerichtet.
- [x] REQ-049: X2 — Befehle „Spalte links einfuegen“ und „Spalte rechts einfuegen“.
- [x] REQ-050: X2 — Befehl „Spalte loeschen“.
- [x] REQ-051: X2 — Befehle „Spalte nach links/rechts verschieben“.
- [x] REQ-052: X2 — Die Spaltenbefehle und „Sort table by column“ stehen im Alt+M-Menue.
- [x] REQ-053: X3 — Zellen jenseits der Kopfbreite werden als Diagnose markiert.
- [x] REQ-054: X3 — Ein Quick Fix „Spalte zum Kopf hinzufuegen“ behebt die Diagnose.

## Einstellungen (D5)

Je mit Vorgabe laut Decision-Log, Beschreibung in `package.json` und Test des Rueckfalls auf die Vorgabe.

- [x] REQ-055: `markdownWorkbench.tables.enabled` schaltet Enter/Tab/Pfeile in Tabellen ab.
- [x] REQ-056: `tables.enterBehavior` (`newRow` | `nextRowSameColumn`).
- [x] REQ-057: `tables.tabSelectsCell`.
- [x] REQ-058: `tables.tabAddsRow`.
- [x] REQ-059: `tables.arrowNavigation`.
- [x] REQ-060: `tables.autoAlign`.
- [x] REQ-061: `tables.maxAlignedWidth`.
- [x] REQ-062: `tables.ambiguousWidth` (`narrow` | `wide`).
- [x] REQ-063: `tables.cellLineBreak`.
- [x] REQ-064: `tables.createFromPipe`.
- [x] REQ-065: `tables.continueCheckboxes`.
- [x] REQ-066: `tables.suggestNumericAlign`.
- [x] REQ-067: `tables.previewSort` erreicht die Preview ueber die `config`-Nachricht.
- [x] REQ-068: `tables.pasteAsTable`.
- [x] REQ-069: `tables.validate`.

## Doku-Nachzug

- [x] REQ-070: `docs/ARCHITECTURE.md` § „Editing features“ beschreibt Tabellenmodell, Enter/Tab/Pfeile, Code Action,
      Paste, Diagnose, mit Statusmarkern und Testbelegen.
- [x] REQ-071: `docs/ARCHITECTURE.md` § „Message protocol“ fuehrt `sortTable` (webview → host) und das neue Feld der
      `config`-Nachricht.
- [x] REQ-072: `docs/ARCHITECTURE.md` § „Configuration“ nennt die `tables.*`-Einstellungen.
- [x] REQ-073: `docs/DECISIONS.md` bekommt einen neuen Eintrag (naechste freie Nummer am Head) mit dem Inhalt des
      Decision-Logs; die Freigabe von `get-east-asian-width` steht darin.
- [x] REQ-074: `README.md` beschreibt die Tabellen-Features und Einstellungen und fuehrt die neuen Befehle in
      „Commands“.
- [x] REQ-075: `CHANGELOG.md` hat einen Abschnitt 0.35.0.
- [x] REQ-076: `package.json` `version` ist 0.35.0.

## Nachtraege aus dem Review

- [x] REQ-077: Mit einer Auswahl richten „Evenly Distribute Table“ und „Consolidate Table“ jede Tabelle aus, die die
      Auswahl beruehrt, in einem Undo-Schritt; ohne Auswahl die Tabelle am Cursor (Review-Runde 1, F1).
- [x] REQ-078: Nach dem Merge von #89 traegt der Tabellen-Eintrag in `docs/DECISIONS.md` die Nummer 49, und
      `package.json` `version` sowie der `CHANGELOG`-Abschnitt sind 0.36.0; REQ-073, REQ-075 und REQ-076 gelten mit
      diesen Werten (Review-Runde 4, R4-5).
