<!-- transport: verbatim, do not re-render -->
# Decision-Log: Markdown-Tabellen bearbeiten (#86)

| Feld | Wert |
|---|---|
| Stempel | 2026-09-28T0011Z |
| Repo / Basis | ww3d/markdown-workbench, `main` `4221a9f` (0.34.0, VS Code `^1.100.0`) |
| Anlass | ww3d/markdown-workbench#86 |
| Tracking Issue | ww3d/markdown-workbench#90 |
| Runde | Design-Session `design-mw-86`, Entscheider: Maintainer direkt im Chat (Controller `ctrl-markdown-workbench-1` hatte die Runde an ihn abgegeben) |
| Audit-Gate | `audit/ist-stand-2026-09-27T2058Z.md` |
| Review-Modus | `hard v4` (Vorschlag der Session; der Maintainer hat die Runde danach ohne Einwand geschlossen) |

Ablage im Repo: Das Repo fuehrt keine `docs/decisions/`; der dev-PR traegt den Inhalt als neuen
Eintrag in `docs/DECISIONS.md` (naechste freie Nummer am Head) ein.

## Rahmen (Maintainer, vor der Runde)

- Gebaut wird nach Claudes Empfehlung und mit allen Claude-Ideen, eigene Umsetzung in
  `src/editing.js`.
- Alles in **einem** PR; jeder Punkt ist im Umfang oder ausdruecklich verworfen, mit Grund.
- Einstellungen fuer alle Features, wo sinnvoll.

## Ausgeraeumte Fehlannahmen

- `splitRow` ist nicht nur fuer Enter unzureichend: Schon heute macht `reflowTable` aus
  `a \| b` zwei Zellen und verliert beim Schreiben den Schutz (gemessen am Head).
- Ein `|` in einem Code-Span trennt nach GFM (Spec-Beispiele 199–204) **und** in unserer Preview
  (markdown-it 15.0.2, gemessen) die Zellen. Ein Parser, der Backticks schuetzt (so `mte-kernel`),
  saehe eine andere Tabelle als die Preview.
- markdown-it 15.0.2 erkennt Tabellen ohne Randstriche, in Listenpunkten und in Zitaten (gemessen).
  Eine Textzeile direkt unter einer Tabelle wird zur Tabellenzeile; Beenden braucht eine Leerzeile.
- Eine Tabellenzeile ist fuer `onTabKey` heute eine markerlose Zeile: Tab rueckt sie per
  Spaltenstopp ein (DECISIONS.md #27). Der Tabellen-Zweig muss davor greifen.
- Learn Markdown 1.0.18 (Quelle aus der VSIX-Sourcemap gelesen): Enter kennt keine Tabellen;
  Tabellen nur als Distribute/Consolidate/Insert/„Convert to data matrix“ auf einer Markierung;
  Zerlegung per `split('|')`, Breite per Codepoints mit grobem Emoji-Abzug, keine CJK-Breite.
- `DocumentPasteEditProvider` ist stabil seit dem Zyklus Januar 2025 (microsoft/vscode#238916,
  VS Code 1.97); mit `engines.vscode ^1.100.0` aus #84 nutzbar.

## Entscheidungen

### D1 Grundlage: eigenes Tabellenmodell plus `get-east-asian-width`

- Eigenes Modell in `src/editing.js` (Zerlegung nach GFM, Erkennung wie die Preview, Breite nach
  Graphemen). Verworfen: alte Zerlegung behalten (erbt den Inhaltsfehler); markdown-it zur Erkennung
  (keine Zell-Positionen, keine Kopfzeile ohne Trennzeile); `mte-kernel` (schuetzt Backticks
  gegen GFM, `meaw ^5` veraltet, seit 2020 ohne Release, 600 KB); `string-width` (drei
  Transitiv-Pakete, `/v`-Regex, Terminal-Semantik).
- **Abhaengigkeit freigegeben:** `get-east-asian-width` 1.7.0 (MIT, 0 Abhaengigkeiten), nur als
  Unicode-Breitendaten. Grund: ersetzt die einzige Liste, die sonst selbst gepflegt veralten wuerde.
- Festlegungen: (1) Erkennung wie die Preview, Tipp-Ausnahme fuer eine mit `|` beginnende Zeile
  ohne Trennzeile; (2) `\|` bleibt Inhalt, ungeschuetzter `|` im Code-Span trennt, keine stille
  Korrektur; (3) Breite: East-Asian Wide/Fullwidth und Emoji 2, kombinierende Zeichen 0,
  Ambiguous 1; (4) Stil bleibt: randlos bleibt randlos, Ausrichtungs-Doppelpunkte, Einrueckung,
  Listen-Einrueckung und `>` bleiben.
- Abheben: Ausrichten aendert nur Leerzeichen und Strichzahl der Trennzeile, mit Zufalls-Test unter
  festem Seed; dieselbe Tabelle wie die Preview; korrekte Breite bei CJK/Emoji.
- Architektur-Abgleich: `docs/ARCHITECTURE.md` § „Editing features (editing.js)“.

### D2 Enter

| # | Fall | Entscheidung |
|---|---|---|
| E1 | Enter in einer Datenzeile | neue leere Zeile darunter, gleiche Spaltenzahl, Cursor in die erste Zelle; die Zeile wird nicht geteilt |
| E2 | Enter vor dem ersten Inhalt (Praefix, erster `|`) | neue leere Zeile darueber |
| E3 | Enter in der Kopfzeile mit Trennzeile | neue Zeile direkt unter der Trennzeile |
| E4 | Enter in der Kopfzeile ohne Trennzeile | Trennzeile plus leere Datenzeile, Cursor in deren erste Zelle |
| E5 | Enter in der Trennzeile | wie E3 |
| E6 | Enter in der letzten, ganz leeren Zeile | Zeile wird Leerzeile, Praefix (`>`, Einrueckung) bleibt |
| E7 | leere Zeile mitten in der Tabelle | wie E1 |
| E8 | nach Enter | Tabelle ausrichten; Enter plus Ausrichten ist ein Undo-Schritt; nur geaenderte Bereiche werden ersetzt |
| E9 | mehrere Cursor oder Markierung | normales Enter |
| E10 | Codeblock, Frontmatter | kein Tabellen-Zweig |

Verworfen: Sprung in dieselbe Spalte (org/Obsidian) als Vorgabe — bleibt als Einstellung
(`enterBehavior`); Zelle am Cursor teilen; Stil „kompakt bleibt kompakt“ automatisch erkennen.
Abheben: ein Undo-Schritt samt Ausrichten; Shift+Enter in einer Zelle fuegt `<br>` ein; Beenden
und Einfuegen richtig in Zitaten und Listen.

### D3 Tab, Shift+Tab, Pfeile

| # | Fall | Entscheidung |
|---|---|---|
| T1 | Tab | naechste Zelle, Inhalt markiert; leere Zelle: Cursor hinein |
| T2 | Tab in der letzten Zelle einer Zeile | erste Zelle der naechsten Zeile, Trennzeile uebersprungen |
| T3 | Tab in der allerletzten Zelle | neue Zeile wie E1 |
| T4 | Shift+Tab | vorherige Zelle markiert; erste Zelle: letzte Zelle der Vorzeile; erste Kopfzelle: nichts; nie ausruecken |
| T5 | Ausrichten bei Tab/Shift+Tab | ja, ein Undo-Schritt; schon ausgerichtet: kein Undo-Schritt |
| T6 | Zeile mit zu wenigen Zellen | wird beim Ausrichten aufgefuellt |
| T7 | Cursor vor dem ersten `|` | Tab springt in die erste Zelle |
| T8 | Markierung ueber mehrere Zeilen | unveraendert: Block-Einrueckung (DECISIONS.md #27) |
| T9 | Pfeil hoch/runter | dieselbe Zelle der Nachbarzeile, gleiche Stelle (sonst Zellende), Trennzeile uebersprungen; normaler Pfeil am Tabellenrand, mit Markierung, mehreren Cursorn, offener Vorschlagsliste oder `editor.wordWrap` ungleich `off` |
| T10 | Kontext | Kontext-Schluessel `markdownWorkbench.inTable`, nur bei Selektionswechsel berechnet und nur bei Wechsel gesetzt; die Pfeil-Bindungen haengen daran |

Verworfen: Pfeile generell ueber die Extension leiten (Latenz bei jedem Pfeil). Abheben: keine
Tastenkonflikte (nur in Tabellen, nie bei Snippet/Vorschlagsliste); Pfeil bleibt in der Zelle auch
bei CJK/Emoji; Tab markiert zum Ueberschreiben.

### D4 Kandidaten aus #86

| # | Entscheidung | Verworfen, mit Grund |
|---|---|---|
| K1 | Ausrichten waehlt consolidate, wenn die breiteste ausgerichtete Zeile (samt Praefix, in Anzeigebreite) `maxAlignedWidth` (Vorgabe 100, 0 = aus) ueberschreitet; die Befehle Distribute/Consolidate bleiben unbedingt | feste Grenze ohne Einstellung |
| K2 | `|` + Tab: Zeile, die mit `|` beginnt und keine Tabelle ist, bekommt Zellende und neue Zelle; Enter danach wie E4 | — |
| K3 | Code Action „Spalte rechtsbuendig ausrichten“ fuer Spalten ohne Ausrichtung mit nur Zahlen, setzt `--:` | automatisch: aendert die Darstellung, bricht die Invariante aus D1 |
| K4 | Preview: Sortier-Knopf beim Ueberfahren des Spaltenkopfs, auf-/absteigend; neue Nachricht `sortTable` an den Host; Host sortiert die Datenzeilen der Quelle (numerisch, stabil) in einem Undo-Schritt; veraltete Dokumentversion wird ignoriert. Dazu Editor-Befehl „Tabelle nach dieser Spalte sortieren“ | nur die Anzeige sortieren (bricht die aufsteigenden `data-line`, Scroll-Sync); Klick auf die ganze Kopfzelle |
| K5 | Neue Zeile (E1, T3) uebernimmt Checkbox-Spalten: Zelle nur `[ ]`/`[x]` → neue Zeile `[ ]` | Mehrfachauswahl hier bauen (bleibt #56) |

Nachzuege: `docs/ARCHITECTURE.md` § „Message protocol“ (`sortTable`), `package.json`
(Einstellung K1, Befehl K4). Abheben: Sortieren per Klick zurueck in die Quelle; Vorschlag statt
Bevormundung; Checkbox-Spalten laufen mit.

### D5 Einstellungen und weitere Ideen

Einstellungen unter `markdownWorkbench.tables.*`, Vorgabe = das entschiedene Verhalten, defensive
Rueckfaelle wie DECISIONS.md #17, Schalter an Tastenbelegungen per `when`-Klausel:

| Einstellung | Vorgabe | fuer |
|---|---|---|
| `enabled` | `true` | Hauptschalter Enter/Tab/Pfeile in Tabellen |
| `enterBehavior` | `newRow` (`nextRowSameColumn`) | E1 |
| `tabSelectsCell` | `true` | T1 |
| `tabAddsRow` | `true` | T3 |
| `arrowNavigation` | `true` | T9 |
| `autoAlign` | `true` | E8, T5 |
| `maxAlignedWidth` | `100` (0 = aus) | K1 |
| `ambiguousWidth` | `narrow` (`wide`) | D1 |
| `cellLineBreak` | `<br>` (leer = aus) | Shift+Enter |
| `createFromPipe` | `true` | K2 |
| `continueCheckboxes` | `true` | K5 |
| `suggestNumericAlign` | `true` | K3 |
| `previewSort` | `true` | K4, reist mit der `config`-Nachricht |
| `pasteAsTable` | `true` | X1 |
| `validate` | `true` | X3 |

Verworfen: eine Einstellung je Randfall E2–E7.

| # | Idee | Entscheidung |
|---|---|---|
| X1 | CSV/TSV einfuegen als Markdown-Tabelle (`DocumentPasteEditProvider`), ausgerichtet, `|` im Inhalt wird `\|` | bauen |
| X2 | Spalte links/rechts einfuegen, loeschen, nach links/rechts verschieben; als Befehle und im Alt+M-Menue | bauen |
| X3 | Diagnose fuer Zellen jenseits der Kopfbreite (GFM zeigt sie still nicht an, Spec-Beispiel 204), Quick Fix „Spalte zum Kopf hinzufuegen“ | bauen |

Abheben: Umsteiger-Modus per `enterBehavior`; Warnung vor still verlorenen Zellen; Einfuegen aus
Excel mit geschuetzten `|`.

## Nicht in diesem Design

- Mehrfachauswahl von Tabellen-Checkboxen in der Preview: ww3d/markdown-workbench#56.
- „Convert table to data matrix“ (Learn Markdown): Abgleich in ww3d/markdown-workbench#4.

## Konstellation

- ww3d/markdown-workbench#84 ist gemerged (`4221a9f`): pnpm, Node 26, markdown-it 15.0.2,
  `engines.vscode ^1.100.0`, Version 0.34.0. Dieser PR baut darauf auf und setzt 0.35.0.
- Parallel laeuft die Design-Runde zu ww3d/markdown-workbench#82 (neues Modul `src/diff.js`); beide
  koennen dieselbe naechste `DECISIONS.md`-Nummer beanspruchen — am Head die naechste freie nehmen.
