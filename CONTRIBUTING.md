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

1. Bump `version` in `package.json` (source of truth).
2. Add the matching `## x.y.z` entry on top of `CHANGELOG.md` -
   `build.ps1` refuses to package on mismatch.
3. Update `README.md` if behavior changed (standing rule: README and
   CHANGELOG move with every change).
4. `./build.ps1` - green coverage gate, vsix created.
5. Publish: `npx vsce publish` (requires a Marketplace PAT for the
   publisher) or upload the vsix manually.

## Code conventions

- English code, comments and docs; German is fine in issues/PR bodies.
- Umlauts written as ae/oe/ue/ss in plain-text contexts.
- No frameworks in the webview; it stays one inline template.
- Every user-visible change lands in CHANGELOG.md and, if it changes
  behavior, README.md.
