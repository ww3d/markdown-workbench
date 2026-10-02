@AGENTS.md
@tech/common/typescript.md

## Project Context

**Markdown Workbench** is a VS Code extension: an interactive markdown preview
with toggleable checkboxes, a minimap, modern tables and authoring tools.
Toggles are mirrored surgically back into the source file. Stack: TypeScript 7
(VS Code Extension API, Node; `src/**/*.ts`, checked by `tsc -b`, tests via
`node --test` straight from `.ts`), bundled with tsdown.

Architecture and contributor docs in `docs/`:

- `docs/common/*.md` (synct aus `ww3d/playbook`)

## Architecture Principles

_keine_

## Project-Specific Overrides

- Bestehender CI (`.github/workflows/test.yml`) ist projekt-eigen und von
  `docs/common/ci.md` nur im kanonischen Check-Namen `build-test (ubuntu-latest)`
  geregelt: Dateiname, der Job `release` (Tag, GitHub-Release, Provenance-Attestation,
  die `publish.ps1` prueft) statt `pack` und das `.vsix`-Artefakt auch auf PRs folgen
  der Release-Kette aus `CONTRIBUTING.md` § "Releasing", fuer die `ci.md` kein
  Gegenstueck hat. `permanent`.
- _(overrides the baseline)_ CI, `pnpm run coverage` und `pnpm run package` rufen
  `node eng/build.ts --task <Task>` statt `pnpm run ...` (`tech/common/typescript.md`
  § "Build and Test"): `eng/build.ts` ist der Orchestrator des Repos (DECISIONS.md #21)
  und faehrt dieselben Kommandos (`pnpm run format`, `lint`, `typecheck`, den
  Testbefehl von `pnpm test` unter c8, `tsdown`) plus Smokes, Groessen-Gate und
  Paket, so laufen lokales Gate und CI denselben Weg. `permanent`.
- _(overrides the baseline)_ `tsconfig.base.json` setzt zusaetzlich
  `"skipLibCheck": true` (`tech/common/typescript.md` § "Baseline" nennt die Flags
  abschliessend): jeder der vier Pruefbereiche pruefte sonst die Deklarationen von
  Node, VS Code und DOM neu und verdoppelte die kalte Typpruefung; die eigenen
  Quellen bleiben voll geprueft, lokale Shims decken kaputte Fremd-Typen
  (DECISIONS.md #50). `permanent`.
- _(overrides the baseline)_ Node.js 26 statt 24 LTS (`tech/common/typescript.md`
  § "Baseline"), in CI und `engines.node`: Auftrag des Maintainers. Gilt, bis
  ww3d/playbook#334 das Overlay auf 26 hebt; danach entfaellt die Zeile.
