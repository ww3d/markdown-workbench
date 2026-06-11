# Contributing

Solo project; this documents the workflow.

## Setup

```powershell
npm ci
```

## Build, test, package

Everything runs through the PowerShell orchestrator:

```powershell
./build.ps1 -Task Test       # node:test suites
./build.ps1 -Task Coverage   # tests under c8 with the coverage gate
./build.ps1 -Task Build      # tsdown (Rolldown) bundle to dist/
./build.ps1 -Task Package    # version check + bundle + vsce package
./build.ps1                  # All: version check + coverage + package
```

`npm test`, `npm run coverage`, `npm run build` and `npm run package` map to
the same steps for environments without PowerShell.

## Testing

Tests live in `tests/*.test.js` (node:test). Two helpers carry the suites:

- `tests/helpers/vscode-mock.js` - a vscode API mock with editable
  documents and editors, installed via a `Module._load` hook.
- `tests/helpers/dom-mock.js` - executes the webview `<script>` headlessly
  and exposes listeners, posted messages, body classes and element styles.

Coverage gate (c8, enforced locally and in CI): 88% lines, 82% branches,
78% functions over `extension.js` and `editing.js`.

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
node scripts/release-notes.js <version>   # print the notes for a version
node scripts/bundle-smoke.js              # assert shiki works in the bundle
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
2. Install the toolchain: `winget install Microsoft.AzureCLI OpenJS.NodeJS.LTS`
3. Log in once with the publisher's account: `az login`
4. Install the repo dependencies in your clone: `npm ci` - the script needs
   the local `@vscode/vsce` and refuses to run without it (it never installs
   anything itself).

Then, per release, exactly one command:

```powershell
./publish.ps1                    # publishes the version in package.json
./publish.ps1 -Version 0.24.3    # or an explicit, already released version
```

The script preflights the toolchain (node >= 22, `az` logged in, `gh`
authenticated, publisher set), downloads the vsix and `SHA256SUMS.txt` of
the `v<version>` GitHub release into a temp directory, verifies the
checksum and the build-provenance attestation (both mandatory; any
mismatch aborts before any publish attempt), skips cleanly when the
gallery already has that version, and only then publishes. A missing
release for the tag is an error: merge and release first, then publish.

## Code conventions

- English code, comments and docs; German is fine in issues/PR bodies.
- Umlauts written as ae/oe/ue/ss in plain-text contexts.
- No frameworks in the webview; it stays one inline template.
- Every user-visible change lands in CHANGELOG.md and, if it changes
  behavior, README.md.
