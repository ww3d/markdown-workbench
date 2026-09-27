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

## Project-Specific Overrides

- Das JS/TS-Overlay `tech/common/typescript.md` gilt auch fuer JavaScript-Projekte
  und ist oben importiert; dessen Typ-Regeln (`tsconfig.json`, `typecheck`) entfallen
  hier, wie das Overlay selbst fuer reines JavaScript sagt.
- Bestehender CI (`.github/workflows/test.yml`) ist projekt-eigen und nicht von
  `docs/common/ci.md` geregelt.
- _(overrides the baseline)_ Node.js 26 statt 24 LTS (`tech/common/typescript.md`
  § "Baseline"), in CI und `engines.node`: Auftrag des Maintainers. Gilt, bis
  ww3d/playbook#334 das Overlay auf 26 hebt; danach entfaellt die Zeile.
