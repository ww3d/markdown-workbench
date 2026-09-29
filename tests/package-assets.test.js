// Guard against the 0.29.0 packaging bug: package.json and src/views/
// reference media/*.svg icons that an over-eager .vscodeignore can silently
// drop from the vsix (the manifest then points at files absent from the
// package, so the commands render without glyphs). This checks the assets
// against the REAL vsce pack list, not a re-implementation of the ignore
// rules - so re-excluding any referenced icon turns this test red.
import { test } from 'node:test';
import assert from 'node:assert';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pkg from '../package.json' with { type: 'json' };
import { relativeLayout } from '../eng/layout.ts';

const repoRoot = path.resolve(import.meta.dirname, '..');

// Asset paths the manifest points at: every command icon (light + dark) and
// the top-level Marketplace icon. Normalized to package-relative form
// (vsce ls emits "media/x.svg", the manifest writes "./media/x.svg").
function manifestAssets() {
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
  const viewsDir = path.join(repoRoot, 'src', 'views');
  const src = fs
    .readdirSync(viewsDir)
    .filter((f) => f.endsWith('.js'))
    .map((f) => fs.readFileSync(path.join(viewsDir, f), 'utf8'))
    .join('\n');
  const assets = new Set();
  const re = /joinPath\(\s*extensionUri\s*,\s*'media'\s*,\s*'([^']+)'\s*\)/g;
  for (const m of src.matchAll(re)) assets.add(`media/${m[1]}`);
  return assets;
}

// Assets the webview STYLESHEET points at: the vendored codicon font is reached
// only through a CSS url(), which neither the manifest nor the host code mentions,
// so without this collector it shipped unguarded (it survived on the fail-safe
// .vscodeignore alone). url() paths are relative to media/webview.css, so they
// resolve against media/.
function stylesheetAssets() {
  const css = fs.readFileSync(
    path.join(repoRoot, 'media', 'webview.css'),
    'utf8',
  );
  const assets = new Set();
  const re = /url\(\s*["']?([^"')]+)["']?\s*\)/g;
  for (const m of css.matchAll(re)) {
    const ref = m[1].trim();
    if (/^(data:|https?:|\/\/)/.test(ref)) continue; // inline or remote, nothing to pack
    assets.add(path.posix.normalize(path.posix.join('media', ref)));
  }
  return assets;
}

// The actual list of files vsce would pack, straight from the tool, so the
// assertion tracks real packaging behavior rather than a guessed mirror of
// .vscodeignore. Spawns node on vsce's entry point (cross-platform; no npx).
// `ls` ignores package.json's vsce block, so --no-dependencies is passed here:
// the bundle ships no node_modules, and npm-based detection fails under pnpm.
function packList() {
  const vsce = fileURLToPath(import.meta.resolve('@vscode/vsce/vsce'));
  const out = execFileSync(
    process.execPath,
    [vsce, 'ls', '--no-dependencies'],
    {
      cwd: repoRoot,
      encoding: 'utf8',
    },
  );
  return new Set(
    out
      .split('\n')
      .map((l) => l.trim())
      .filter(Boolean),
  );
}

test('every referenced media asset is in the real vsce pack list', () => {
  const referenced = new Set([
    ...manifestAssets(),
    ...viewsAssets(),
    ...stylesheetAssets(),
  ]);
  assert.ok(referenced.size > 0, 'expected at least one referenced asset');
  const packed = packList();
  const missing = [...referenced].filter((p) => !packed.has(p));
  assert.deepStrictEqual(
    missing,
    [],
    `referenced assets missing from the vsix: ${missing.join(', ')}`,
  );
});

test('the vsix carries only the extension, its media and the Marketplace docs', () => {
  const allowed =
    /^(dist\/|media\/|README\.md$|CHANGELOG\.md$|LICENSE$|package\.json$)/;
  const stray = [...packList()].filter((p) => !allowed.test(p));
  assert.deepStrictEqual(
    stray,
    [],
    `files outside the extension in the vsix: ${stray.join(', ')}`,
  );
});

test('build.ps1 runs format check and lint first in the All gate', () => {
  const script = fs.readFileSync(path.join(repoRoot, 'build.ps1'), 'utf8');
  assert.match(script, /ValidateSet\('Check',/, 'Check is a task of its own');
  assert.match(script, /pnpm run format\b/, 'Check runs the format check');
  assert.match(script, /pnpm run lint\b/, 'Check runs the linter');
  assert.match(
    script,
    /'All' \{\s*Invoke-Check\s*\n/,
    'All starts with the check, before the tests',
  );
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
    'media/source-dark.svg',
  ];
  const packed = packList();
  const missing = expected.filter((p) => !packed.has(p));
  assert.deepStrictEqual(missing, [], `missing icons: ${missing.join(', ')}`);
});

test('build.ps1 dependency preflight: implicit restore locally, fail-fast in CI / -NoRestore', () => {
  // Contract only (PowerShell is not executed headlessly; CI exercises the CI
  // branch for real). The preflight detects a missing/stale node_modules, then:
  // locally restores with a frozen pnpm install (announced), but in CI or with
  // -NoRestore fails fast; a failed restore aborts with pnpm's exit code.
  const script = fs.readFileSync(path.join(repoRoot, 'build.ps1'), 'utf8');
  assert.match(
    script,
    /function Assert-Dependencies/,
    'the preflight function exists',
  );
  assert.match(
    script,
    /Assert-Dependencies\s*#/,
    'the preflight runs before the task switch',
  );
  assert.match(
    script,
    /\[switch\] \$NoRestore/,
    'the -NoRestore opt-out exists',
  );
  assert.match(
    script,
    /node_modules\/\.modules\.yaml/,
    'compares against the install marker',
  );
  assert.match(
    script,
    /Get-Item 'pnpm-lock\.yaml' -Force/,
    'the marker is compared with the pnpm lockfile',
  );
  // The install marker is a dotfile; Get-Item needs -Force on Linux or it throws
  // "Could not find item" on the hidden file (regression that broke CI).
  assert.match(
    script,
    /Get-Item \$installed -Force/,
    'reads the hidden install marker with -Force',
  );
  // CI / -NoRestore -> fail fast, never auto-install.
  assert.match(
    script,
    /if \(\$env:CI -or \$NoRestore\)/,
    'CI and -NoRestore take the fail-fast path',
  );
  assert.match(
    script,
    /run 'pnpm install --frozen-lockfile' first/,
    'fail-fast tells the user how to fix it',
  );
  // Local default -> announced implicit restore, error never swallowed.
  assert.match(
    script,
    /restoring \(pnpm install --frozen-lockfile\)\.\.\./,
    'announces the restore before running it',
  );
  assert.match(
    script,
    /^\s*pnpm install --frozen-lockfile$/m,
    'restores with a frozen pnpm install',
  );
  assert.match(
    script,
    /Dependency restore \(pnpm install\) failed with exit code \$LASTEXITCODE/,
    'a failed restore aborts with pnpm exit code',
  );
  assert.doesNotMatch(
    script,
    /\bnpm ci\b|\bnpx\b/,
    'no npm call is left in the build',
  );
});

test('the vendored codicon font is packaged, reached via the stylesheet url()', () => {
  // Explicit anchor: the font is referenced ONLY from webview.css, so a collector
  // that scans just the manifest and the host code would miss it.
  assert.ok(
    stylesheetAssets().has('media/codicon.ttf'),
    'the stylesheet url() collector finds the vendored font',
  );
  assert.ok(packList().has('media/codicon.ttf'), 'and it is in the vsix');
});

test('the design-master source media/icon.svg is NOT packaged', () => {
  // .vscodeignore excludes only this file; if it leaks in, the exclude broke.
  assert.ok(
    !packList().has('media/icon.svg'),
    'media/icon.svg (256px design master) must stay out of the vsix',
  );
});

// --- Output layout (eng/layout.ts) ---
// Where a path cannot come from eng/layout.ts (a manifest field, an ignore
// file, a tsconfig), a literal names it; these tests keep every such literal
// in step with the layout, so moving an output there turns them red here.

// Non-empty, non-comment lines of an ignore file in the repository root.
function ignoreLines(file) {
  return fs
    .readFileSync(path.join(repoRoot, file), 'utf8')
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#'));
}

test('package.json main points into the layout dist folder', () => {
  assert.ok(
    pkg.main.startsWith(`./${relativeLayout.dist}/`),
    `main "${pkg.main}" is not under ${relativeLayout.dist}/`,
  );
});

test('.gitignore and .vscodeignore name the layout outputs', () => {
  const git = ignoreLines('.gitignore');
  for (const dir of [relativeLayout.dist, relativeLayout.artifacts]) {
    assert.ok(git.includes(`${dir}/`), `.gitignore lacks ${dir}/`);
  }
  const vsix = ignoreLines('.vscodeignore');
  assert.ok(
    vsix.includes(`${relativeLayout.artifacts}/**`),
    `.vscodeignore lacks ${relativeLayout.artifacts}/**`,
  );
  assert.ok(
    !vsix.some((l) => l.startsWith(`${relativeLayout.dist}/`)),
    `${relativeLayout.dist}/ is the extension and must ship in the vsix`,
  );
});

test('every tsconfig keeps its build info under the layout obj folder', () => {
  const configs = fs
    .readdirSync(repoRoot)
    .filter((f) => /^tsconfig.*\.json$/.test(f))
    .map((f) => [
      f,
      JSON.parse(fs.readFileSync(path.join(repoRoot, f), 'utf8')),
    ]);
  // A config that checks files (not the solution, not the shared base) must
  // set it: tsc -b otherwise writes its build info next to the config.
  const checking = configs.filter(([, c]) => c.include || c.files?.length);
  assert.ok(checking.length > 0, 'expected at least one checking tsconfig');
  for (const [file, config] of checking) {
    const info = config.compilerOptions?.tsBuildInfoFile ?? '';
    assert.ok(
      info.startsWith(`./${relativeLayout.obj}/`),
      `${file}: tsBuildInfoFile "${info}" is not under ${relativeLayout.obj}/`,
    );
  }
});

test('Biome and Prettier skip the layout outputs through .gitignore', () => {
  // Neither names an output itself: Biome reads .gitignore (vcs.useIgnoreFile),
  // Prettier 3 reads it by default, so .gitignore is the one literal.
  const biome = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'biome.json'), 'utf8'),
  );
  assert.strictEqual(biome.vcs?.useIgnoreFile, true);
  const outputs = [relativeLayout.dist, relativeLayout.artifacts];
  const named = [
    ...ignoreLines('.prettierignore'),
    ...(biome.files?.includes ?? []),
  ].filter((l) => outputs.some((o) => l.replace(/^!/, '').startsWith(o)));
  assert.deepStrictEqual(named, [], 'an output path named outside .gitignore');
});
