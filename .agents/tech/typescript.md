# Agent Rules — TypeScript Overlay

Applies to every project of the JS/TS family — a consumer whose `stacks` lists `typescript` or
`javascript` alike. A plain-JavaScript project skips the type-level rules below (no `tsconfig.json`,
no type annotations, no `typecheck` step).

## Baseline

- **Node.js 26** (LTS) pinned in CI (`actions/setup-node`, `node-version: 26`) and in `package.json`
  (`"engines": { "node": ">=26" }`).
- **`tsconfig.json`** extends a `tsconfig.base.json` with exactly this baseline:
  - `strict` and `noUncheckedIndexedAccess` — an index access yields `T | undefined`.
  - `noImplicitOverride` and `noFallthroughCasesInSwitch` — an override is marked, a `case` does not
    fall through unnoticed.
  - `verbatimModuleSyntax`, `erasableSyntaxOnly`, `rewriteRelativeImportExtensions`,
    `module: nodenext`, `target: esnext` — only syntax Node can strip, imports as written.
  - `noEmit` — `tsc` checks, it does not build. A package that ships compiled `.js` through `tsc`
    drops it in its wrapper; a bundler build (WXT, `tsdown`) keeps it.
  - `types: ["node"]` — TypeScript 6 and later load no `@types` package unless named. `@types/node`
    follows the Node major (26.x), not the registry's latest.
- **TypeScript 7** for `tsc`. Before 7.1 it has no stable programmatic API, so a tool built on the
  compiler API (typescript-eslint's type-aware rules, `ts-jest`, Vue/Svelte/Angular compilers)
  cannot run on it; a consumer that needs one pins TypeScript 6 in its wrapper, with that reason.
- **pnpm**, pinned through the `packageManager` field of `package.json`, the one place of its
  version. `pnpm-lock.yaml` is committed.
- **`package.json`**: `"type": "module"` and `"sideEffects": false`; a package whose imports do have
  side effects (a stylesheet, a polyfill) lists those files there instead of `false`.

## Do Not Miss

Where they apply: `.agents/rules/code.md` § "Simplicity".

- `satisfies` over an annotation or `as` where the narrow type must stay.
- `using`/`await using` or `DisposableStack` for every resource with a close step.
- Built-ins before helpers: iterator helpers, `Set` methods, `Promise.try`, `RegExp.escape`,
  `Array.fromAsync`, `Error.isError`, `Uint8Array` base64, `Map.getOrInsert`/`getOrInsertComputed`;
  `Temporal` instead of `Date`.
- Node built-ins before packages: `--env-file` instead of `dotenv`, `fs.glob`, `util.parseArgs`,
  `util.styleText`, `--watch`.
- Import aliases through `package.json` `imports` (`#/…`, mapped to `./src/*.ts`, the specifier
  written without `.ts`), never `tsconfig` `paths`.
- Dependency injection by constructor, wired by hand in the composition root; no decorator
  container.
- Data access selects only the columns it uses, loads relations in the same query and reuses
  prepared statements.

## Code Style

- **Biome** lints and formats code, JSON and CSS (`biome.json`: the `recommended` preset, plus
  `noExplicitAny`, `useAwait` and `useImportType` at `error`; indent with spaces).
- **Prettier** formats only what Biome cannot: Markdown and YAML, with its defaults.
- Both skip the paths the playbook sync mirrors byte-identically (`biome.json` `files.includes`,
  `.prettierignore`).
- TSDoc on every exported symbol (TypeScript's counterpart to XML docs).
- `AbortSignal` on every async API a library exposes (TypeScript's counterpart to
  `CancellationToken`).

## Folder Conventions

- `utils/` is exempt from the folder-naming ban-list.

## Build and Test

```bash
pnpm install --frozen-lockfile
pnpm run format       # biome format && prettier --check "**/*.{md,yml,yaml}"
pnpm run lint         # biome lint
pnpm run typecheck    # tsc
pnpm test             # node --test
pnpm run build        # only where the repo builds an artifact
```

Together they are the stack's full run.

## Dependencies

- `pnpm outdated`.

## Tests

Node's built-in test runner (`node --test`) against `*.test.ts` (`*.test.js` for a plain-JavaScript
project), run straight from source — no build before the tests.

No test sleeps or waits on the real clock (`.agents/rules/code.md` § "Tests and Time"): timers run
under the runner's `mock.timers` (`enable()`, then `tick()`), which moves time by hand.
