# Ordnerregeln: Verbotsliste, Sediment-Deckel, Ausnahmen

Die Ausnahmedatei dieses Repos zu `.agents/rules/code.md` § "Folder Conventions". Die Regeln selbst
stehen dort; hier steht nur, was fuer dieses Repo gilt, und jede Ausnahme mit ihrer Aufloesung
(Traeger oder `permanent`).

## Geltung

Geprueft werden Ordner, die ein PR anlegt oder aendert, ab ww3d/markdown-workbench#89. Den Bestand
davor prueft diese Datei nicht; was dort auffaellt, steht als Ausnahme mit Traeger unten.

## Verbotsliste

Die Standardliste aus `.agents/rules/code.md` ohne Zusaetze: `Services`, `Helpers`, `Utils`,
`Models`, `Interfaces`, `Extensions`, `Common`, `Misc`, `Shared`. `utils/` ist nach
`tech/common/typescript.md` § "Folder Conventions" frei.

## Sediment-Deckel

Drei Dateien auf der obersten Ebene von `src/`.

Ebenso drei auf der obersten Ebene von `src/webview/`: der Einstieg `main.ts`, das
Nachrichtenprotokoll `protocol.ts` und der Zugang zum Host `host.ts`. Alles andere
liegt in einem Fachordner je Abschnitt der Webview, das Stylesheet eines Moduls neben
ihm (DECISIONS.md #50).

Ebenso drei auf der obersten Ebene von `tests/`: `activation.test.ts` (zu `src/extension.ts`),
`manifest.test.ts` (das Manifest `package.json`) und `repo.test.ts` (Invarianten des Quellbaums). Alles andere liegt in einem
Ordner, der einen Ordner von `src/`, `eng/` oder `scripts/` spiegelt (`tests/eng/` zu `eng/`,
`tests/scripts/` zu `scripts/`), oder in einer der Ausnahmen unten.

## Spiegelregel fuer die Webview

`tests/webview/` spiegelt `src/webview/`: je Fachordner ein gleichnamiger Testordner,
auf der obersten Ebene `main.test.ts` zu `main.ts` und `protocol.probe.ts` zu
`protocol.ts` (eine Typprobe, die `pnpm run typecheck` prueft). `host.ts` hat keinen
eigenen Test: `tests/helpers/webview-dom.ts` stellt ihm `acquireVsCodeApi`, jeder
Webview-Test laeuft darueber. Keine
Ausnahme noetig.

## Ausnahmen

| Ordner                                            | Regel                                                        | Grund                                                                                                                                                                                                                                                                  | Aufloesung  |
| ------------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `tests/helpers/`                                  | Verbotsliste (`Helpers`), Spiegelregel (kein `src/helpers/`) | Test-Infrastruktur fuer alle Testordner (vscode-Attrappe, DOM-Attrappe der Webview, Aufbau der Clipboard-Diff-Tests); ein Fachname wuerde einen Fachordner vortaeuschen, den es nicht gibt                                                                             | `permanent` |
| `tests/integration/`                              | Spiegelregel (kein `src/integration/`)                       | Eigene Testschicht im echten VS Code quer ueber alle Fachordner, mit eigenem Runner und eigenen Fixtures (DECISIONS.md #48)                                                                                                                                            | `permanent` |
| `tests/package/`                                  | Spiegelregel (kein `src/package/`)                           | Eigene Testschicht gegen das gebaute `dist/` und die echte vsce-Paketliste, quer ueber alle Fachordner: `build.ps1` faehrt sie nach dem Build, `pnpm test` und die Abdeckung nicht, denn Unit-Tests bauen nichts (REQ-020 von #92)                                     | `permanent` |
| `tests/probes/`                                   | Spiegelregel (kein `src/probes/`)                            | Typproben je Pruefbereich (`host.probe.ts`, `webview.probe.ts`), die nur ihr Bereich prueft, und der Test, dass jeder Bereich sie einschliesst (laeuft in `build.ps1 -Task Check` als `pnpm run test:probes`, nicht in `pnpm test`); sie gehoeren zu keinem Fachordner | `permanent` |
| `docs/common/`, `scripts/common/`, `tech/common/` | Verbotsliste (`Common`)                                      | Vom Playbook byte-identisch gesynct; Pfad und Name setzt ww3d/playbook, nicht dieses Repo                                                                                                                                                                              | `permanent` |
