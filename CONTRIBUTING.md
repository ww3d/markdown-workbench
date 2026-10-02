# Contributing

Solo project; this documents the workflow.

## Setup

A fresh clone needs nothing installed beforehand - not Node, pnpm or Corepack:

```powershell
.\Build.cmd        # Windows (needs only Windows PowerShell 5.1)
```

```sh
./build.sh         # Linux / macOS (needs bash, curl and tar)
```

The first run fetches the Node version pinned in `package.json` (`devEngines.runtime.version`,
exact) from nodejs.org (checked against `SHASUMS256.txt`) and the pnpm pinned by `packageManager`
(installed by npm from that Node) into `.tools/` of the repository (gitignored, never in the
`.vsix`), then installs the dependencies with `pnpm install --frozen-lockfile` and builds. A
matching Node or pnpm already on `PATH` is used; a different version never is. The scripts follow
the layout of ww3d/atlas (ww3d/markdown-workbench#103).

The other root scripts, Windows / Linux and macOS:

- `Restore.cmd` / `restore.sh` - the tools and the dependency install only.
- `Test.cmd` / `test.sh` - restore + the unit tests.
- `eng\common\CIBuild.cmd` / `eng/common/cibuild.sh` - every task with `--ci`, the run CI does.

Any other task goes through the generic entry point, which takes `-Task <Name>` / `--task <Name>`
or the Atlas switches (`-restore -build -test -pack -check -coverage -integrationTest`, `-ci`,
`-clean`, `-artifactsDir`, `-NoRestore`):

```powershell
eng\common\build.ps1 -Task Package
```

```sh
eng/common/build.sh --task Package
```

With Node already installed, `pnpm install --frozen-lockfile` and `node eng/build.ts --task <Name>`
work as well.

## Build, test, package

Every task is a step of `eng/build.ts` (TypeScript, run by Node's type stripping); the root scripts
above fetch the pinned Node and then call it:

```powershell
node eng/build.ts --task Restore     # tools + pnpm install --frozen-lockfile
node eng/build.ts --task Check       # format check (Biome + Prettier) + lint (Biome) + typecheck (tsc -b)
                                     # + type scope tests (pnpm run test:probes)
node eng/build.ts --task Test        # node:test unit suites (no build needed)
node eng/build.ts --task Coverage    # tests under c8 with the coverage gate
node eng/build.ts --task Build       # tsdown bundles to dist/ + bundle smoke + webview smoke + size gate
node eng/build.ts --task Package     # version check + package fields + Build + package tests on dist/ + vsce package
node eng/build.ts --task Integration # Build + integration tests in a real VS Code
node eng/build.ts                    # All: check + version check + coverage + package + integration
```

Switches: `--no-restore` (fail fast on a missing or stale `node_modules`), `--ci` (also set by the
`CI` environment variable) and `--help`. Through the wrappers the same tasks read
`eng\common\build.ps1 -Task Check` or `eng/common/build.sh --task Check`.

`pnpm run format`, `pnpm run lint`, `pnpm run typecheck`, `pnpm run test:probes`, `pnpm test`,
`pnpm run coverage`, `pnpm run build`, `pnpm run bundle-smoke`,
`pnpm run webview-smoke`, `pnpm run size-gate`, `pnpm run test:package`,
`pnpm run package` and `pnpm run test:integration` map to the same steps once Node and pnpm are
installed (`coverage` and `package` call `node eng/build.ts --task Coverage|Package` themselves);
`pnpm run format:fix` rewrites the formatting.

The build writes the two bundles to `dist/` (`extension.cjs` for the extension
host, `webview.js` + `webview.css` for the webview); every other output - the
`.vsix` in `artifacts/packages/`, coverage in `artifacts/TestResults/`, build info,
the test compile cache (`artifacts/obj/compile-cache`) and integration bundles in
`artifacts/obj/`, the downloaded VS Code in `artifacts/toolset/`, scratch pages in
`artifacts/tmp/` -
takes its path from `eng/layout.ts`, never from a literal.

Packaging (`-Task Package`) has two guards:

- **Mandatory fields.** `scripts/package-fields.ts` runs first and stops with one error naming every
  missing value: `publisher`, `description`, `license`, `repository.url`, `repository.type` in
  `package.json`, and the `LICENSE` file.
- **Byte-identical `.vsix`.** `eng/build.ts` sets `SOURCE_DATE_EPOCH` to the commit time of HEAD
  (`git log -1 --format=%ct`) and `TZ` to `UTC` for `vsce package` only (the session gets its old
  values back), and `vsce` then fixes the zip mtimes and sorts the files: the same commit gives the
  same SHA-256 on the same platform. File permissions (umask, the Windows mode) go into the package.
  A `SOURCE_DATE_EPOCH` already in the environment wins and must be digits. Without git or its
  history the run stops instead of falling back to the clock. Outside `eng/build.ts`, a plain
  `vsce package` stays non-reproducible unless you set both variables yourself.

`typecheck` is `tsc -b` over four scopes: the extension host (Node types, no DOM),
the webview (DOM, no Node types), the tests and the tools (`tsdown.config.ts`,
`eng/`, `scripts/`, `bench/`); `src/webview/protocol.ts` belongs to both the host
and the webview scope (docs/DECISIONS.md #50). `tests/probes/scope.test.ts` proves
each scope includes its type probes; it runs in Check, not in the unit run.

The Build task checks the bundles, not the sources: `scripts/bundle-smoke.ts` and
`scripts/webview-smoke.ts` run the built `dist/extension.cjs` (Shiki in all 18
languages) and `dist/webview.js` (a visible render in happy-dom) from an isolated
temp directory, and `scripts/size-gate.ts` fails the run when a bundle outgrows its
limit - gzip of `webview.js` + `webview.css` (28 000 B) and of `extension.cjs`, and
the uncompressed bytes of each webview file. A limit is never raised to make a
change fit; raising one is a decision, not a fix.

Every `eng/build.ts` task starts with a dependency preflight: if `node_modules` is
missing or stale (the tracked `pnpm-lock.yaml` is newer than the install), it
restores automatically with an announced `pnpm install --frozen-lockfile`
(implicit restore, like `dotnet build`) rather than letting node die with
cryptic `MODULE_NOT_FOUND` errors and a misleading coverage drop; a failed
restore aborts with pnpm's exit code. Pass `--no-restore` (`-NoRestore` on the
wrappers) to opt out and fail fast with `run 'pnpm install --frozen-lockfile' first`
instead. With `--ci` (or the `CI` environment variable) it never auto-installs - a
lockfile drift must surface as a red build, and the workflow runs its own frozen install.

Build scripts of dependencies run only where `pnpm-workspace.yaml` allows them
(`allowBuilds`); pnpm fails the install on any dependency left unreviewed.

## Testing

Tests live in `tests/**/*.test.ts` (node:test) in two layers.

The unit layer (everything except `tests/package/` and `tests/probes/`) runs straight
from the TypeScript sources through Node's type stripping, no build first:

```sh
node --env-file=tests/helpers/compile-cache.env scripts/run-tests.ts --import ./tests/helpers/setup.ts "tests/*.test.ts" "tests/!(package|probes)/**/*.test.ts"   # = pnpm test
```

`scripts/run-tests.ts` starts `node --test` with one test process per core
(`os.availableParallelism()`); Node's default is one less and takes no "all cores" value.

The package layer (`tests/package/`) checks what the build produced: it reads
`dist/` and the real `vsce` pack list and stops when a bundle is missing instead of
building it. Run it with `pnpm run test:package` after a build;
`node eng/build.ts --task Package` runs it right after the build. It is outside the unit run
and outside the coverage gate. The type scope tests (`tests/probes/`, `pnpm run test:probes`)
are outside it too and run in `node eng/build.ts --task Check` after the typecheck.

A folder of product code under `src/` has its tests in the same-named folder
under `tests/` (e.g. `src/clipboard-diff/` -> `tests/clipboard-diff/`,
`src/webview/minimap/` -> `tests/webview/minimap/`). The helpers, all under
`tests/helpers/`:

- `tests/helpers/setup.ts` - preloaded by `--import` into every test process:
  registers the module hooks below and loads `compile-cache.ts` and `build-id.ts`.
- `tests/helpers/compile-cache.ts` - turns on Node's compile cache for a test file
  run on its own, stored under the layout's `compileCache`;
  `NODE_DISABLE_COMPILE_CACHE=1` switches it off.
- `tests/helpers/compile-cache.env` - read by the unit run through `node --env-file`, so
  every test process it starts inherits `NODE_COMPILE_CACHE` from its first module (a
  cache hit never loads the type stripper). It holds the layout's `compileCache` path as a
  literal; `compile-cache.test.ts` pins it.
- `tests/helpers/build-id.ts` - stands in the bundler's `BUILD_ID` with a fixed
  global (`TEST_BUILD_ID`), since the tests run the sources unbundled.
- `tests/helpers/vscode-hooks.ts` - resolves `vscode` to a virtual module built
  from the mock installed at load time, and tags every `src/` URL with a
  generation (`?gen=N`), so each generation is a fresh module graph with its own
  state.
- `tests/helpers/vscode-mock.ts` - the vscode API mock with editable documents
  and editors; `install()` sets it up, `loadFresh()` imports a module in a new
  generation bound to it.
- `tests/helpers/clipboard-diff-setup.ts` - the fixture of the clipboard-diff
  binding tests: a fresh mock, the feature registered, one open Markdown file as
  the active editor.
- `tests/helpers/text-lines.ts` - a mock document as the read-only line source
  (`TextLines`) the editing helpers take.
- `tests/helpers/nth.ts` - indexed access that throws on a missing item, so a test
  fails by name under `noUncheckedIndexedAccess`.
- `tests/helpers/webview-hooks.ts` - lets the webview modules load under Node: a
  stylesheet import becomes an empty module, `morphdom` a stand-in a test can
  replace.
- `tests/helpers/webview-dom.ts` - a DOM mock for the webview and
  `startWebview()`, which installs it and imports `src/webview/main.ts` in a fresh
  generation; it exposes listeners, posted messages, body classes, element styles
  and the persisted state.
- `tests/helpers/webview-fixtures.ts` - shared fixtures of the webview tests: config
  messages, click targets, heading and line-map mocks and prepared documents.
- `tests/helpers/css-rules.ts` - stylesheet lookups for the CSS contract tests,
  reading `src/webview/**/*.css` in the bundle's cascade order.
- `tests/helpers/dist.ts` - the package layer's access to the built `dist/`; it
  throws with the remedy when a bundle is missing.

Coverage gate (c8, enforced locally and in CI): 88% lines, 82% branches,
78% functions over every `.ts` file under `src/`.

### Integration tests (real VS Code)

`tests/integration/` runs the extension in a real VS Code through
`@vscode/test-electron`, with its own small runner (no Mocha, DECISIONS.md #48):
`tests/integration/run.ts` downloads VS Code into `artifacts/toolset/vscode-test/` (the layout's
`toolset`, git- and vsix-ignored with the other outputs; a `.vscode-test/` left at the repository root by an
older checkout is no longer ignored and can be deleted), bundles the suite and the guard driver with tsdown into
`artifacts/obj/integration/` (VS Code 1.100 runs Node 20.19, which cannot strip
types) and runs the cases of `tests/integration/suite/*.int.ts` twice - against the
minimum version from `engines.vscode` and against the current stable one. Each run
gets a fresh `--user-data-dir` in the temp directory, `--disable-extensions` and a
copy of `tests/integration/fixtures/workspace/`; a second launch on the same
profile plays the reloaded window. The guard scenario in `guard/scenario.ts`
carries the clipboard diff's promise that the clipboard text never reaches the
disk. It runs once more in a **normal window** (a test host keeps VS Code's
backups in memory): the runner packages the extension and the test-only
`guard/driver` extension as vsix files with `vsce`, installs both into a fresh
`--extensions-dir` of a fresh profile and starts VS Code twice on it; the driver
runs the scenario and quits.

- Under Linux the run needs a display: `node eng/build.ts --task Integration` goes through
  `xvfb-run -a` (package `xvfb`); by hand run
  `xvfb-run -a node tests/integration/run.ts`. Windows and macOS run it directly.
- `MDWB_VERSIONS=1.139.1,stable` narrows the versions, `MDWB_ONLY=guard` runs one
  suite file (without the window guard), `MDWB_ONLY=window-guard` only the window
  guard. Build first (`node eng/build.ts --task Integration` does): both runs load
  `dist/`.
- Under Windows the runner stops before VS Code starts when the path to its
  `workbench.html` under `artifacts/toolset/vscode-test/` reaches 260 characters (VS Code would
  hang until the timeout): check the repository out under a shorter path.
- The guard's mutation run, `node tests/integration/guard-mutation.ts` (under
  Linux through `xvfb-run -a`; script `test:guard-mutation`), shows that the
  guard catches an unsaved page: it builds a copy of the repository without the
  immediate save and expects both guards to fail. Not part of `All` (it runs
  the guards twice more); run it when the save or the guard changes.
- The run starts four VS Code instances per version and takes minutes. On the shared
  build machine, take a slot from the orchestrator before running it (or the full
  `All` gate) locally.
- If VS Code cannot be downloaded or started, report the integration step as **not
  run** - never as green - and ask the maintainer for a run on Windows.

### Benchmarks

`bench/` holds diagnostics, not gates: the start of the shipped webview
(`bench/start-bench.ts`), the load time of `dist/webview.js` up to `ready`
(`bench/load-bench.ts`), the activation of `dist/extension.cjs`
(`bench/activation-bench.ts`), plus scrolling, folding, rendering, tables and the
clipboard anchor. Build first; how to run and read them: `bench/README.md`.

Conventions learned the hard way: when a test fails, verify the test before
touching the code (two real cases live in DECISIONS.md #5 and #11 - one
wrong test, one real contract violation).

## Releasing

Releases are automated: every push to `main` whose CI is green runs the
`release` job, which tags `v<version>` (from `package.json`), publishes a
GitHub Release named `v<version>` with the matching `CHANGELOG.md` section as
notes, and attaches two assets - the vsix (direct download) and
`SHA256SUMS.txt` - plus a Sigstore build-provenance attestation on the vsix.

To cut a release, land a normal PR that bumps the version:

1. Bump `version` in `package.json` (source of truth).
2. Add the matching `## x.y.z` entry on top of `CHANGELOG.md` -
   `eng/build.ts` refuses to package on mismatch, and the release job fails if
   that section is missing or empty.
3. Update `README.md` if behavior changed (standing rule: README and
   CHANGELOG move with every change).
4. `eng\common\build.ps1` / `eng/common/build.sh` (all tasks) - green coverage gate, vsix created.
5. Merge to `main`. The `release` job does the rest.

The job is idempotent: a merge that does not bump the version (the tag
already exists) skips the release step cleanly, so docs-only merges never
fail or overwrite a published release. Marketplace publishing stays manual,
out of this workflow's scope - see the next section.

Local helpers:

```sh
node scripts/release-notes.ts <version>   # print the notes for a version
node scripts/bundle-smoke.ts              # assert shiki works in the bundle
node scripts/webview-smoke.ts             # assert the built webview renders
node scripts/size-gate.ts                 # measure the bundles against their limits
```

## Marketplace publishing

GitHub Releases are automatic (every green merge to `main` publishes one);
publishing to the VS Code Marketplace is a deliberate manual decision per
release. `./publish.ps1` publishes exactly the attested GitHub release
artifact - never a local build - and authenticates via Entra ID
(`vsce publish --azure-credential`; no PAT, Marketplace PATs retire in
December 2026). Publishing deliberately stays out of `eng/build.ts`, which
remains credential-free and deterministic for CI.

One-time setup:

1. Create the `ww3d` publisher at
   <https://marketplace.visualstudio.com/manage>.
2. Install the toolchain: `winget install Microsoft.AzureCLI OpenJS.NodeJS`
3. Log in once with the publisher's account: `az login`
4. Install the repo dependencies in your clone: `pnpm install --frozen-lockfile` - the script needs
   the local `@vscode/vsce` and refuses to run without it (it never installs
   anything itself).

Then, per release, exactly one command:

```powershell
./publish.ps1                    # publishes the version in package.json
./publish.ps1 -Version 0.24.3    # or an explicit, already released version
```

The script preflights the toolchain (node >= 26, `az` logged in, `gh`
authenticated, publisher set, publish permission on the publisher verified
via `vsce verify-pat`), downloads the vsix and `SHA256SUMS.txt` of
the `v<version>` GitHub release into a temp directory, verifies the
checksum and the build-provenance attestation (both mandatory; any
mismatch aborts before any publish attempt), skips cleanly when the
gallery already has that version, and only then publishes. A missing
release for the tag is an error: merge and release first, then publish.

### Publisher identity

The publisher owner and the identity `az login` signs in as must be the
same principal. The trap: the same e-mail address can exist as both a
personal Microsoft account and an Entra identity - the Marketplace portal
may resolve it differently when creating the publisher than `az login`
does, and the upload then fails with "Access Denied" despite correct
credentials. Diagnose in seconds:

```powershell
pnpm exec vsce verify-pat ww3d --azure-credential
```

To see which identity the az side is using:

```powershell
az ad signed-in-user show --query userPrincipalName -o tsv
```

For guest identities the UPN has the form `name_domain#EXT#@<tenant>...` -
and it is exactly this UPN (not the e-mail address) that the publisher's
Members dialog accepts.

## Code conventions

- English code, comments and docs; German is fine in issues/PR bodies.
- Umlauts written as ae/oe/ue/ss in plain-text contexts.
- No frameworks in the webview; its modules live under `src/webview/`, one folder
  per subject, each importing its own stylesheet (docs/folder-rules.md).
- Every user-visible change lands in CHANGELOG.md and, if it changes
  behavior, README.md.
