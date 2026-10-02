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

## Ausnahmen

| Ordner                                            | Regel                                                        | Grund                                                                                                                                                                                      | Aufloesung  |
| ------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| `tests/helpers/`                                  | Verbotsliste (`Helpers`), Spiegelregel (kein `src/helpers/`) | Test-Infrastruktur fuer alle Testordner (vscode-Attrappe, DOM-Attrappe der Webview, Aufbau der Clipboard-Diff-Tests); ein Fachname wuerde einen Fachordner vortaeuschen, den es nicht gibt | `permanent` |
| `tests/integration/`                              | Spiegelregel (kein `src/integration/`)                       | Eigene Testschicht im echten VS Code quer ueber alle Fachordner, mit eigenem Runner und eigenen Fixtures (DECISIONS.md #48)                                                                | `permanent` |
| `docs/common/`, `scripts/common/`, `tech/common/` | Verbotsliste (`Common`)                                      | Vom Playbook byte-identisch gesynct; Pfad und Name setzt ww3d/playbook, nicht dieses Repo                                                                                                  | `permanent` |
