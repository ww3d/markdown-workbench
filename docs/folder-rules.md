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

## Spiegelregel fuer die Webview

`tests/webview/` spiegelt `src/webview/`: je Fachordner ein gleichnamiger Testordner,
auf der obersten Ebene `main.test.ts` zu `main.ts` und `protocol.probe.ts` zu
`protocol.ts` (eine Typprobe, die `pnpm run typecheck` prueft). `host.ts` hat keinen
eigenen Test: `tests/helpers/webview-dom.ts` stellt ihm `acquireVsCodeApi`, jeder
Webview-Test laeuft darueber. Keine
Ausnahme noetig.

## Ausnahmen

| Ordner                                            | Regel                                                        | Grund                                                                                                                                                                                      | Aufloesung  |
| ------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| `tests/helpers/`                                  | Verbotsliste (`Helpers`), Spiegelregel (kein `src/helpers/`) | Test-Infrastruktur fuer alle Testordner (vscode-Attrappe, DOM-Attrappe der Webview, Aufbau der Clipboard-Diff-Tests); ein Fachname wuerde einen Fachordner vortaeuschen, den es nicht gibt | `permanent` |
| `tests/integration/`                              | Spiegelregel (kein `src/integration/`)                       | Eigene Testschicht im echten VS Code quer ueber alle Fachordner, mit eigenem Runner und eigenen Fixtures (DECISIONS.md #48)                                                                | `permanent` |
| `docs/common/`, `scripts/common/`, `tech/common/` | Verbotsliste (`Common`)                                      | Vom Playbook byte-identisch gesynct; Pfad und Name setzt ww3d/playbook, nicht dieses Repo                                                                                                  | `permanent` |
