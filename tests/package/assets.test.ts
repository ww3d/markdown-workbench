// Guard against the 0.29.0 packaging bug: package.json and src/views/
// reference media/*.svg icons that an over-eager .vscodeignore can silently
// drop from the vsix (the manifest then points at files absent from the
// package, so the commands render without glyphs). This checks the assets
// against the REAL vsce pack list, not a re-implementation of the ignore
// rules - so re-excluding any referenced icon turns this test red.
//
// The pack list and the stylesheet checks read the built bundles: this is a package test
// (tests/package/), run by build.ps1 after the build, and it never builds dist/ itself.
import { test } from 'node:test';
import assert from 'node:assert';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import pkg from '../../package.json' with { type: 'json' };
import { repoRoot } from '../../eng/layout.ts';
import { builtDist } from '../helpers/dist.ts';

const distDir = builtDist();
const distName = path.basename(distDir);

// Asset paths the manifest points at: every command icon (light + dark) and
// the top-level Marketplace icon. Normalized to package-relative form
// (vsce ls emits "media/x.svg", the manifest writes "./media/x.svg").
function manifestAssets(): Set<string> {
  const assets = new Set<string>();
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
function viewsAssets(): Set<string> {
  const viewsDir = path.join(repoRoot, 'src', 'views');
  const src = fs
    .readdirSync(viewsDir)
    .filter((f) => f.endsWith('.ts'))
    .map((f) => fs.readFileSync(path.join(viewsDir, f), 'utf8'))
    .join('\n');
  const assets = new Set<string>();
  const re = /joinPath\(\s*extensionUri\s*,\s*'media'\s*,\s*'([^']+)'\s*\)/g;
  for (const m of src.matchAll(re)) assets.add(`media/${m[1]}`);
  return assets;
}

// Assets the webview STYLESHEET points at: the vendored codicon font is reached
// only through a CSS url(), which neither the manifest nor the host code mentions,
// so without this collector it shipped unguarded (it survived on the fail-safe
// .vscodeignore alone). The webview loads the bundled dist/webview.css, whose url()
// paths the bundler passes through unchanged, so they resolve against dist/.
function stylesheetAssets(): Set<string> {
  const css = fs.readFileSync(path.join(distDir, 'webview.css'), 'utf8');
  const assets = new Set<string>();
  const re = /url\(\s*["']?([^"')]+)["']?\s*\)/g;
  for (const m of css.matchAll(re)) {
    const [, target] = m;
    if (target === undefined) continue;
    const ref = target.trim();
    if (/^(data:|https?:|\/\/)/.test(ref)) continue; // inline or remote, nothing to pack
    assets.add(path.posix.normalize(path.posix.join(distName, ref)));
  }
  return assets;
}

// The actual list of files vsce would pack, straight from the tool, so the
// assertion tracks real packaging behavior rather than a guessed mirror of
// .vscodeignore. Spawns node on vsce's entry point (cross-platform; no npx).
// `ls` ignores package.json's vsce block, so --no-dependencies is passed here:
// the bundle ships no node_modules, and npm-based detection fails under pnpm.
// Listed once per file: every test reads the same tree, and each vsce run costs
// most of a second.
let packListCache: ReadonlySet<string> | undefined;
function packList(): ReadonlySet<string> {
  packListCache ??= listPack();
  return packListCache;
}

function listPack(): Set<string> {
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

test('the vendored codicon font is packaged, reached via the stylesheet url()', () => {
  // Explicit anchor: the font is referenced ONLY from webview.css, so a collector
  // that scans just the manifest and the host code would miss it.
  assert.ok(
    stylesheetAssets().has('media/codicon.ttf'),
    'the stylesheet url() collector finds the vendored font',
  );
  assert.ok(packList().has('media/codicon.ttf'), 'and it is in the vsix');
});

test('every url() in dist/webview.css points to a file in the vsix', () => {
  // The bundler copies no asset and rewrites no url() (docs/DECISIONS.md, D1 of
  // #92): a path that does not resolve from dist/ to a packed file is a glyph
  // the webview silently never shows.
  const referenced = [...stylesheetAssets()];
  assert.ok(referenced.length > 0, 'the stylesheet references its font');
  const packed = packList();
  const missing = referenced.filter((p) => !packed.has(p));
  assert.deepStrictEqual(missing, [], `url() targets not packed: ${missing}`);
});

test('the vsix carries the webview bundle and no sources', () => {
  const packed = packList();
  for (const file of ['dist/webview.js', 'dist/webview.css']) {
    assert.ok(packed.has(file), `${file} is packed`);
  }
  const sources = [...packed].filter((p) => p.startsWith('src/'));
  assert.deepStrictEqual(sources, [], 'no src/ file ships in the vsix');
});

test('the extension-host bundle carries no webview code', () => {
  // The webview is its own bundle; a host module importing from src/webview/
  // would drag webview code (and its DOM globals) into the extension host. The
  // markers are string literals only the webview sources contain.
  const hostFiles = fs
    .readdirSync(distDir)
    .filter((f) => f.endsWith('.cjs'))
    .map((f): [string, string] => [
      f,
      fs.readFileSync(path.join(distDir, f), 'utf8'),
    ]);
  assert.ok(
    hostFiles.some(([f]) => f === 'extension.cjs'),
    'the host bundle exists',
  );
  const markers = [
    'acquireVsCodeApi',
    'webview skeleton lacks',
    'toc-animating',
  ];
  const webview = fs.readFileSync(path.join(distDir, 'webview.js'), 'utf8');
  for (const marker of markers) {
    assert.ok(webview.includes(marker), `${marker} marks the webview bundle`);
    const leaked = hostFiles.filter(([, text]) => text.includes(marker));
    assert.deepStrictEqual(
      leaked.map(([f]) => f),
      [],
      `webview code (${marker}) in the host bundle`,
    );
  }
});

test('the design-master source media/icon.svg is NOT packaged', () => {
  // .vscodeignore excludes only this file; if it leaks in, the exclude broke.
  assert.ok(
    !packList().has('media/icon.svg'),
    'media/icon.svg (256px design master) must stay out of the vsix',
  );
});
