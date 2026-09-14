# Agent Rules — TypeScript Overlay

Imported via `@tech/common/typescript.md` in every project of the JS/TS family — `stack: typescript`
and `stack: javascript` alike (`Get-SyncFile` delivers this same file to both; there is no separate
`tech/common/javascript.md`). A plain-JavaScript project skips the type-level rules below (no
`tsconfig.json`, no type annotations) — see "Recommended, not active" for the JSDoc-typed on-ramp.
Project-specific overrides live in a `tech/typescript.md` wrapper, marked textually with
`*(overrides the baseline)*` or `*(addition to the baseline)*`.

Background and the build-dir rationale in
[`docs/common/ci.md`](https://github.com/ww3d/playbook/blob/main/docs/common/ci.md) § "Kanonische
Check-Namen" and § "Build-Verzeichnis je Stack".

## Baseline

- Node.js pinned in CI (`actions/setup-node`, `node-version: 22`).
- TypeScript projects: `tsconfig.json` sets `"strict": true` (which includes `strictNullChecks`);
  `noUncheckedIndexedAccess` where the project opts in.
- Package manager is per-repo (`npm` or a pinned alternative, e.g. `pnpm` with `pnpm/action-setup`)
  — either way its lockfile (`package-lock.json` / `pnpm-lock.yaml`) is committed.

## Code Style

- Format: Prettier (`.prettierrc`), a dedicated `format` / `format:fix` script pair, checked in CI
  before build — the Ist of `crobench`, the one live TypeScript consumer. A plain-JavaScript
  consumer without a formatter (e.g. `markdown-workbench`) carries no `format` step; see
  "Recommended, not active".
- No linter (ESLint or Biome) is adopted in any consumer today — see "Recommended, not active".
  A manifest-only validator (e.g. `web-ext lint` for a browser-extension manifest) is not a JS/TS
  linter and does not count as one.
- TSDoc on every exported symbol (TypeScript's counterpart to XML docs).
- `interface` or `readonly`-qualified types for data shapes, not a mutable `class` standing in for
  a plain record.
- `strict` (which includes `strictNullChecks`) is the `tsconfig.json` baseline for every TypeScript
  project — see § "Baseline".
- No `any`, and no type assertion (`as T`) as an escape from a type error.
- `AbortSignal` on every async API a library exposes (TypeScript's counterpart to
  `CancellationToken`).
- No `async` function without an `await` in its body.
- ESM as the source form, with `import type` for a type-only import; CJS only where the host
  requires it (VS Code extension host), produced by the bundler, never hand-written.

## Folder Conventions

Rules and rationale in `.agents/rules/code.md` § "Folder Conventions" — stack exceptions only:

- `utils/` is exempt from the folder-naming ban-list — subject to the same size guideline as any
  other folder (~15 files, `.agents/rules/code.md` § "Folder Conventions"), not a free pass.

## Build and Test

```bash
npm ci                # or the repo's pinned package manager, e.g. `pnpm install --frozen-lockfile`
npm run format        # prettier --check .
npm run typecheck     # tsc --noEmit
npm test
npm run build
```

A plain-JavaScript consumer skips `typecheck` (no `tsconfig.json` to check against) and, without a
formatter adopted, `format` too.
Green locally before every commit. CI runs the same, canonical check name `build-test (<os>)` —
today `build-test (ubuntu-latest)` only, no consumer runs a Windows or macOS leg.

## Output Layout

Target: the arcade layout `artifacts/{bin,obj,packages,log,TestResults}` that `ww3d/atlas` defines
for .NET (`RepoLayout.props`). Atlas plans a standalone `Atlas.Sdk.<Stack>` for the Chrome-Extension
and VS-Code-VSIX stacks alongside PowerShell and AutoHotkey (`ww3d/atlas docs/architecture-baseline.md`,
`[geplant]`) — only Rust is named as running with no dedicated SDK at all. Whether these planned
per-stack SDKs adopt the `artifacts/` layout is not documented either way. Actual today: a WXT
extension builds to `.output/` (WXT-native, gitignored); a bundler build for a plain-JavaScript
VS-Code extension (e.g. `tsdown`) writes `dist/` (`outDir`, gitignored).

## Dependencies

- `npm outdated` (or `pnpm outdated` for a pnpm-managed repo) — lockfile committed either way.
- Majors are their own decision, per `AGENTS.md` § "Dependencies" Rule 3.

## Tests

Node's built-in test runner (`node --test`) against `*.test.ts` (`*.test.js` for a plain-JavaScript
project). No Vitest or Jest adopted in any consumer today.

## Recommended, not active

Explicitly not adopted anywhere today; propose, don't build unprompted.

- JSDoc types plus `// @ts-check` as the typed on-ramp for a plain-JavaScript consumer not ready
  for a full `tsconfig.json` migration.
- Prettier for a plain-JavaScript consumer that has not adopted a formatter yet.
- `noUncheckedIndexedAccess` in every `tsconfig.json`, not only where a project opts in.
- TypeScript 7's native (Go) compiler for `tsc --noEmit` — about 10x faster at typecheck; its
  programmatic API is not yet stable (lands in 7.1), so a type-aware linter or `ts-jest` cannot run
  on it yet (https://www.infoq.com/news/2026/08/typescript-7-released/).
- Biome as the linter, should one be adopted, rather than ESLint 9.
- Vitest instead of the built-in test runner, for watch mode and coverage tooling beyond `c8`.
- `pnpm`, pinned via the `packageManager` field, as the default package manager for a new consumer
  (Corepack no longer ships with Node.js 25+).
