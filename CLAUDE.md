@AGENTS.md
@tech/common/typescript.md

## Project Context

**Markdown Workbench** is a VS Code extension: an interactive markdown preview
with toggleable checkboxes, a minimap, modern tables and authoring tools.
Toggles are mirrored surgically back into the source file. Stack: JavaScript
(VS Code Extension API, Node; `src/*.js`, tests via `node --test`), bundled
with tsdown.

Architecture and contributor docs in `docs/`:

- `docs/common/*.md` (synct aus `ww3d/playbook`)

## Architecture Principles

_keine_

## Testlauf und Audit

Felder, die Skills und Pruefskripte hier lesen; nicht loeschen, nur ausfuellen.

- **Voller Lauf:** `./build.ps1` (Check, Versionspruefung, Coverage-Gate, Package, Integration in einem
  echten VS Code; CONTRIBUTING.md § "Build, test, package") — Plattformen: Windows, Linux (die
  Integration dort ueber `xvfb-run -a`; CI faehrt Check, Coverage und Package auf Linux,
  `.github/workflows/test.yml`).
- **Waechterklassen:** `tests/package-assets.test.js` — haelt fest, dass die im Manifest genannten
  Icons im echten `vsce`-Paket liegen.
- **Audit-Schwelle:** 30 — Zahl gemergter PRs seit dem letzten vollen Audit, ab der einer faellig ist
  (Standardwert von `get-audit-due.ps1`; hier ueberschreiben, wenn das Repo eine andere Schwelle
  braucht).

## Start einer Session

Jede Session beginnt mit ihrer Skill-Zeile:

- Dev: `/dev-task <owner/repo>#<N>`
- Controller: `/controller-mode <owner/repo> [lite]`

Stehende Anordnungen des Maintainers stehen woertlich an einem Traeger, den die Session liest (Body
des Tracking Issues oder diese Datei); eine, die noch an keinem solchen Traeger steht, geht woertlich
mit jedem Start mit, bis sie dort steht. Sonst traegt der Start nichts.

## Project-Specific Overrides

- Das JS/TS-Overlay `tech/common/typescript.md` gilt auch fuer JavaScript-Projekte
  und ist oben importiert; dessen Typ-Regeln (`tsconfig.json`, `typecheck`) entfallen
  hier, wie das Overlay selbst fuer reines JavaScript sagt.
- Bestehender CI (`.github/workflows/test.yml`) ist projekt-eigen und nicht von
  `docs/common/ci.md` geregelt.
- _(overrides the baseline)_ Node.js 26 statt 24 LTS (`tech/common/typescript.md`
  § "Baseline"), in CI und `engines.node`: Auftrag des Maintainers. Gilt, bis
  ww3d/playbook#334 das Overlay auf 26 hebt; danach entfaellt die Zeile.
