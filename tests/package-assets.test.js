// Guard against the 0.29.0 packaging bug: package.json and src/views.js
// reference media/*.svg icons that an over-eager .vscodeignore can silently
// drop from the vsix (the manifest then points at files absent from the
// package, so the commands render without glyphs). This checks the assets
// against the REAL vsce pack list, not a re-implementation of the ignore
// rules - so re-excluding any referenced icon turns this test red.
const { test } = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.resolve(__dirname, '..');

// Asset paths the manifest points at: every command icon (light + dark) and
// the top-level Marketplace icon. Normalized to package-relative form
// (vsce ls emits "media/x.svg", the manifest writes "./media/x.svg").
function manifestAssets() {
  const pkg = require('../package.json');
  const assets = new Set();
  for (const cmd of pkg.contributes.commands) {
    if (cmd.icon && typeof cmd.icon === 'object') {
      if (cmd.icon.light) assets.add(cmd.icon.light);
      if (cmd.icon.dark) assets.add(cmd.icon.dark);
    }
  }
  if (pkg.icon) assets.add(pkg.icon);
  return new Set([...assets].map((p) => p.replace(/^\.\//, '')));
}

// media/*.svg icons referenced from the host code (workbenchIconPath builds
// the webview-panel icon via vscode.Uri.joinPath(extensionUri, 'media', ...)).
function viewsAssets() {
  const src = fs.readFileSync(path.join(repoRoot, 'src', 'views.js'), 'utf8');
  const assets = new Set();
  const re = /joinPath\(\s*extensionUri\s*,\s*'media'\s*,\s*'([^']+)'\s*\)/g;
  let m;
  while ((m = re.exec(src)) !== null) assets.add('media/' + m[1]);
  return assets;
}

// The actual list of files vsce would pack, straight from the tool, so the
// assertion tracks real packaging behavior rather than a guessed mirror of
// .vscodeignore. Spawns node on vsce's entry point (cross-platform; no npx).
function packList() {
  const vsce = require.resolve('@vscode/vsce/vsce');
  const out = execFileSync(process.execPath, [vsce, 'ls'], {
    cwd: repoRoot,
    encoding: 'utf8'
  });
  return new Set(
    out.split('\n').map((l) => l.trim()).filter(Boolean)
  );
}

test('every referenced media asset is in the real vsce pack list', () => {
  const referenced = new Set([...manifestAssets(), ...viewsAssets()]);
  assert.ok(referenced.size > 0, 'expected at least one referenced asset');
  const packed = packList();
  const missing = [...referenced].filter((p) => !packed.has(p));
  assert.deepStrictEqual(
    missing, [],
    `referenced assets missing from the vsix: ${missing.join(', ')}`);
});

test('the six tab-action icons are packaged', () => {
  // Explicit anchor for the bug: these are exactly the SVGs 0.29.0 added and
  // the allowlist dropped. Listed by name so re-excluding one fails loudly.
  const expected = [
    'media/workbench-light.svg',
    'media/workbench-dark.svg',
    'media/workbench-side-light.svg',
    'media/workbench-side-dark.svg',
    'media/source-light.svg',
    'media/source-dark.svg'
  ];
  const packed = packList();
  const missing = expected.filter((p) => !packed.has(p));
  assert.deepStrictEqual(missing, [], `missing icons: ${missing.join(', ')}`);
});

test('build.ps1 dependency preflight: implicit restore locally, fail-fast in CI / -NoRestore', () => {
  // Contract only (PowerShell is not executed headlessly; CI exercises the CI
  // branch for real). The preflight detects a missing/stale node_modules, then:
  // locally restores with npm ci (announced), but in CI or with -NoRestore fails
  // fast; a failed restore aborts with npm's exit code.
  const script = fs.readFileSync(path.join(repoRoot, 'build.ps1'), 'utf8');
  assert.match(script, /function Assert-Dependencies/, 'the preflight function exists');
  assert.match(script, /Assert-Dependencies\s*#/, 'the preflight runs before the task switch');
  assert.match(script, /\[switch\] \$NoRestore/, 'the -NoRestore opt-out exists');
  assert.match(script, /node_modules\/\.package-lock\.json/, 'compares against the install marker');
  // The install marker is a dotfile; Get-Item needs -Force on Linux or it throws
  // "Could not find item" on the hidden file (regression that broke CI).
  assert.match(script, /Get-Item \$installed -Force/, 'reads the hidden install marker with -Force');
  // CI / -NoRestore -> fail fast, never auto-install.
  assert.match(script, /if \(\$env:CI -or \$NoRestore\)/, 'CI and -NoRestore take the fail-fast path');
  assert.match(script, /run 'npm ci' first/, 'fail-fast tells the user how to fix it');
  // Local default -> announced implicit restore, error never swallowed.
  assert.match(script, /restoring \(npm ci\)\.\.\./, 'announces the restore before running it');
  assert.match(script, /npm ci/, 'restores with npm ci');
  assert.match(script, /Dependency restore \(npm ci\) failed with exit code \$LASTEXITCODE/,
    'a failed restore aborts with npm exit code');
});

test('the design-master source media/icon.svg is NOT packaged', () => {
  // .vscodeignore excludes only this file; if it leaks in, the exclude broke.
  assert.ok(!packList().has('media/icon.svg'),
    'media/icon.svg (256px design master) must stay out of the vsix');
});
