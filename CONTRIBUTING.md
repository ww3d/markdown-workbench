# Contributing

Solo project; this documents the workflow.

## Setup

```powershell
pnpm install --frozen-lockfile
```

pnpm is pinned by the `packageManager` field in `package.json`.

## Build, test, package

Everything runs through the PowerShell orchestrator:

```powershell
./build.ps1 -Task Check      # format check (Biome + Prettier) + lint (Biome)
./build.ps1 -Task Test       # node:test suites
./build.ps1 -Task Coverage   # tests under c8 with the coverage gate
./build.ps1 -Task Build      # tsdown (Rolldown) bundle to dist/
./build.ps1 -Task Package    # version check + bundle + vsce package
./build.ps1 -Task Integration # bundle + integration tests in a real VS Code
./build.ps1                  # All: check + version check + coverage + package + integration
```

`pnpm run format`, `pnpm run lint`, `pnpm test`, `pnpm run coverage`,
`pnpm run build`, `pnpm run package` and `pnpm run test:integration` map to the
same steps for environments without PowerShell; `pnpm run format:fix` rewrites
the formatting.

Every `build.ps1` task starts with a dependency preflight: if `node_modules` is
missing or stale (the tracked `pnpm-lock.yaml` is newer than the install), it
restores automatically with an announced `pnpm install --frozen-lockfile`
(implicit restore, like `dotnet build`) rather than letting node die with
cryptic `MODULE_NOT_FOUND` errors and a misleading coverage drop; a failed
restore aborts with pnpm's exit code. Pass `-NoRestore` to opt out and fail
fast with `run 'pnpm install --frozen-lockfile' first` instead. In CI
(`$env:CI`) it never auto-installs - a lockfile drift must surface as a red
build, and the workflow runs its own frozen install.

Build scripts of dependencies run only where `pnpm-workspace.yaml` allows them
(`allowBuilds`); pnpm fails the install on any dependency left unreviewed.

## Testing

Tests live in `tests/**/*.test.js` (node:test); a folder of product code under
`src/` has its tests in the same-named folder under `tests/` (e.g.
`src/clipboard-diff/` -> `tests/clipboard-diff/`). Two helpers carry the suites:

- `tests/helpers/vscode-mock.js` - a vscode API mock with editable
  documents and editors, installed via a `Module._load` hook.
- `tests/helpers/dom-mock.js` - executes the webview `<script>` headlessly
  and exposes listeners, posted messages, body classes and element styles.

Coverage gate (c8, enforced locally and in CI): 88% lines, 82% branches,
78% functions over every file under `src/`.

### Integration tests (real VS Code)

`tests/integration/` runs the extension in a real VS Code through
`@vscode/test-electron`, with its own small runner (no Mocha, DECISIONS.md #48):
`tests/integration/run.js` downloads VS Code into `.vscode-test/` (git- and
vsix-ignored) and runs `tests/integration/suite/*.int.js` twice - against the
minimum version from `engines.vscode` and against the current stable one. Each run
gets a fresh `--user-data-dir` in the temp directory, `--disable-extensions` and a
copy of `tests/integration/fixtures/workspace/`; a second launch on the same
profile plays the reloaded window. The guard scenario in `guard/scenario.js`
carries the clipboard diff's promise that the clipboard text never reaches the
disk. It runs once more in a **normal window** (a test host keeps VS Code's
backups in memory): the runner packages the extension and the test-only
`guard/driver` extension as vsix files with `vsce`, installs both into a fresh
`--extensions-dir` of a fresh profile and starts VS Code twice on it; the driver
runs the scenario and quits.

- Under Linux the run needs a display: `build.ps1 -Task Integration` goes through
  `xvfb-run -a` (package `xvfb`); by hand run
  `xvfb-run -a node tests/integration/run.js`. Windows and macOS run it directly.
- `MDWB_VERSIONS=1.139.1,stable` narrows the versions, `MDWB_ONLY=guard` runs one
  suite file (without the window guard), `MDWB_ONLY=window-guard` only the window
  guard. Build first (`build.ps1 -Task Integration` does): both runs load
  `dist/`.
- The run starts four VS Code instances per version and takes minutes. On the shared
  build machine, take a slot from the orchestrator before running it (or the full
  `All` gate) locally.
- If VS Code cannot be downloaded or started, report the integration step as **not
  run** - never as green - and ask the maintainer for a run on Windows.

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
   `build.ps1` refuses to package on mismatch, and the release job fails if
   that section is missing or empty.
3. Update `README.md` if behavior changed (standing rule: README and
   CHANGELOG move with every change).
4. `./build.ps1` - green coverage gate, vsix created.
5. Merge to `main`. The `release` job does the rest.

The job is idempotent: a merge that does not bump the version (the tag
already exists) skips the release step cleanly, so docs-only merges never
fail or overwrite a published release. Marketplace publishing stays manual,
out of this workflow's scope - see the next section.

Local helpers:

```sh
node scripts/release-notes.cjs <version>   # print the notes for a version
node scripts/bundle-smoke.cjs              # assert shiki works in the bundle
```

## Marketplace publishing

GitHub Releases are automatic (every green merge to `main` publishes one);
publishing to the VS Code Marketplace is a deliberate manual decision per
release. `./publish.ps1` publishes exactly the attested GitHub release
artifact - never a local build - and authenticates via Entra ID
(`vsce publish --azure-credential`; no PAT, Marketplace PATs retire in
December 2026). Publishing deliberately stays out of `build.ps1`, which
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
- No frameworks in the webview; it stays one inline template.
- Every user-visible change lands in CHANGELOG.md and, if it changes
  behavior, README.md.
