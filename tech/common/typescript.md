# Agent Rules — TypeScript Overlay

Imported via `@tech/common/typescript.md` in every project of the JS/TS family — a consumer whose
`stacks` lists `typescript` or `javascript` alike (`Get-SyncFile` delivers this same file to both;
there is no separate `tech/common/javascript.md`). A plain-JavaScript project skips the type-level
rules below (no `tsconfig.json`, no type annotations, no `typecheck` step) — see "Recommended, not
active" for the JSDoc-typed on-ramp. Project-specific overrides live in a `tech/typescript.md`
wrapper, marked textually with `*(overrides the baseline)*` or `*(addition to the baseline)*`.

Background and the build-dir rationale in
[`docs/common/ci.md`](https://github.com/ww3d/playbook/blob/main/docs/common/ci.md) § "Kanonische
Check-Namen" and § "Build-Verzeichnis je Stack". Every file named below exists ready to copy in
[`templates/typescript/`](https://github.com/ww3d/playbook/blob/main/templates/typescript/README.md)
in the playbook — the template carries nothing this overlay does not name.

## Baseline

- **Node.js 24** (LTS) pinned in CI (`actions/setup-node`, `node-version: 24`) and in
  `package.json` (`"engines": { "node": ">=24" }`). Node runs `.ts` files directly by stripping the
  types (stable since 24.12), so tests and build scripts need no compile step.
- **`tsconfig.json`** extends a `tsconfig.base.json` with exactly this baseline — Node's
  recommendation for type stripping (https://nodejs.org/api/typescript.html) plus the strictness
  flags:
  - `strict` and `noUncheckedIndexedAccess` — an index access yields `T | undefined`.
  - `verbatimModuleSyntax`, `erasableSyntaxOnly`, `rewriteRelativeImportExtensions`,
    `module: nodenext`, `target: esnext` — only syntax Node can strip, imports as written.
  - `noEmit` — `tsc` checks, it does not build. A package that ships compiled `.js` through `tsc`
    drops it in its wrapper; a bundler build (WXT, `tsdown`) keeps it.
  - `types: ["node"]` — TypeScript 6 and later load no `@types` package unless named; without it
    `node:test` and every other Node built-in fail to resolve. `@types/node` follows the Node major
    (24.x), not the registry's latest — its types describe the runtime the code runs on.
- **TypeScript 7** (the native compiler, stable since 08.07.2026 —
  https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) for `tsc`, about 10x faster
  at a full check. Its limit: no stable programmatic API before 7.1 (planned for 24.11.2026,
  https://github.com/microsoft/TypeScript/issues/63703), so a tool built on the compiler API
  (type-aware ESLint rules, `ts-jest`, Vue/Svelte/Angular compilers) cannot run on it yet — a
  consumer that needs one pins TypeScript 6 in its wrapper, with that reason.
- **pnpm**, pinned through the `packageManager` field of `package.json` (`pnpm/action-setup` reads
  it in CI; Corepack no longer ships with Node.js 25+). `pnpm-lock.yaml` is committed.
- **`package.json`**: `"type": "module"` and `"sideEffects": false`; a package whose imports do have
  side effects (a stylesheet, a polyfill) lists those files there instead of `false`.

## Code Style

- **Biome** lints and formats code, JSON and CSS (`biome.json`: the `recommended` preset, plus
  `noExplicitAny`, `useAwait` and `useImportType` at `error`; indent with spaces).
- **Prettier** formats only what Biome cannot: Markdown and YAML, with its defaults.
- Comment line limit (`.agents/rules/code.md` § "Code Comments"): Biome has no line-length lint
  rule, and `formatter.lineWidth` leaves comments untouched. The review check point carries it.
- Both skip the paths the playbook sync mirrors byte-identically (`biome.json` `files.includes`,
  `.prettierignore`) — the reason is in
  [`docs/common/developer-guide.md`](https://github.com/ww3d/playbook/blob/main/docs/common/developer-guide.md)
  § "Synchronisation aus dem Playbook". `.prettierignore` also names `pnpm-lock.yaml`.
- A manifest-only validator (e.g. `web-ext lint` for a browser-extension manifest) is not a JS/TS
  linter and does not replace Biome.
- TSDoc on every exported symbol (TypeScript's counterpart to XML docs).
- `interface` or `readonly`-qualified types for data shapes, not a mutable `class` standing in for
  a plain record.
- No `any`, and no type assertion (`as T`) as an escape from a type error.
- No `enum`, no `namespace` with runtime code, no constructor parameter properties — Node cannot
  strip them (`erasableSyntaxOnly`). An `as const` object plus a union type replaces an `enum`.
- `AbortSignal` on every async API a library exposes (TypeScript's counterpart to
  `CancellationToken`).
- No `async` function without an `await` in its body.
- ESM as the source form, with `import type` for a type-only import and the real extension on a
  relative import (`./util.ts`); CJS only where the host requires it (VS Code extension host),
  produced by the bundler, never hand-written.

## Folder Conventions

Rules and rationale in `.agents/rules/code.md` § "Folder Conventions" — stack exceptions only:

- `utils/` is exempt from the folder-naming ban-list — subject to the same size guideline as any
  other folder (~15 files, `.agents/rules/code.md` § "Folder Conventions"), not a free pass.

## Build and Test

```bash
pnpm install --frozen-lockfile
pnpm run format       # biome format && prettier --check "**/*.{md,yml,yaml}"
pnpm run lint         # biome lint
pnpm run typecheck    # tsc
pnpm test             # node --test
pnpm run build        # only where the repo builds an artifact
```

`format:fix` is the writing counterpart of `format`. A plain-JavaScript consumer skips `typecheck`.
Green locally before every commit. CI runs the same, canonical check name `build-test (<os>)` —
by default `build-test (ubuntu-latest)` only; a repo with a further platform adds its name in the
same scheme.

## Output Layout

Target: open, as in `docs/common/ci.md` § "Build-Verzeichnis je Stack"; the arcade layout
`artifacts/{bin,obj,packages,log,TestResults}` the org's build SDK defines for .NET
(`RepoLayout.props`) is the reference, not yet a target for this stack. Actual: a WXT extension
builds to `.output/` (WXT-native, gitignored); a bundler build for a plain-JavaScript VS-Code
extension (e.g. `tsdown`) writes `dist/` (`outDir`, gitignored).

## Dependencies

- `pnpm outdated` — lockfile committed.
- Majors are their own decision, per `AGENTS.md` § "Dependencies" Rule 3.

## Tests

Node's built-in test runner (`node --test`) against `*.test.ts` (`*.test.js` for a plain-JavaScript
project), run straight from source — no build before the tests.

## Recommended, not active

Not adopted by default; propose, don't build unprompted.

- JSDoc types plus `// @ts-check` as the typed on-ramp for a plain-JavaScript consumer not ready
  for a full `tsconfig.json` migration.
- Vitest instead of the built-in test runner, for watch mode and coverage tooling beyond `c8`.
