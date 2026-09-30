// REQ-080: the size gate fails a build over a limit and passes one at or under it, for the
// gzip limits (P1, P2) and the uncompressed-byte limits of webview.js and webview.css. The
// fixture is a small dist/ in a temp folder; limits are passed in so the files stay small.
import { after, test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import {
  formatTable,
  hostFiles,
  LIMITS,
  type Limits,
  measure,
  P1_WEBVIEW_GZIP_MAX,
  P2_EXTENSION_GZIP_MAX,
  WEBVIEW_CSS_RAW_MAX,
  WEBVIEW_JS_RAW_MAX,
} from '../../scripts/size-gate.ts';

const gate = path.resolve(import.meta.dirname, '../../scripts/size-gate.ts');

const dirs: string[] = [];
after(() => {
  for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true });
});

function tempDir(): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-size-gate-'));
  dirs.push(dir);
  return dir;
}

/** A dist/ fixture with the three bundles, given as content. */
function fixture(files: {
  js: Buffer | string;
  css: Buffer | string;
  ext: Buffer | string;
}): string {
  const dir = tempDir();
  fs.writeFileSync(path.join(dir, 'webview.js'), files.js);
  fs.writeFileSync(path.join(dir, 'webview.css'), files.css);
  fs.writeFileSync(path.join(dir, 'extension.cjs'), files.ext);
  return dir;
}

const gz = (data: Buffer): number => zlib.gzipSync(data, { level: 9 }).length;
const noise = (bytes: number): Buffer => crypto.randomBytes(bytes);
const verdict = (dist: string, limits: Limits, check: string): boolean =>
  measure(dist, limits).find((r) => r.check.startsWith(check))?.ok ?? false;

const js = noise(2000);
const css = noise(1000);
const ext = noise(3000);
const dist = fixture({ js, css, ext });
const loose: Limits = {
  webviewGzip: 1_000_000,
  extensionGzip: 1_000_000,
  webviewJsRaw: 1_000_000,
  webviewCssRaw: 1_000_000,
};

test('the P1 gzip limit passes at the measured sum and fails one byte below', () => {
  const sum = gz(js) + gz(css);
  assert.ok(verdict(dist, { ...loose, webviewGzip: sum }, 'P1'));
  assert.ok(!verdict(dist, { ...loose, webviewGzip: sum - 1 }, 'P1'));
});

test('the P2 gzip limit passes at the measured size and fails one byte below', () => {
  const size = gz(ext);
  assert.ok(verdict(dist, { ...loose, extensionGzip: size }, 'P2'));
  assert.ok(!verdict(dist, { ...loose, extensionGzip: size - 1 }, 'P2'));
});

test('P2 counts the chunks extension.cjs requires directly, not the grammar chunks they load', () => {
  const core = noise(1500);
  const grammar = noise(4000);
  // The bundle's spelling of a chunk load. Put together at run time: REQ-017 keeps the
  // literal call out of tests/, and the fixture must still read like the bundle.
  const call = `${['requ', 'ire'].join('')}("./core-Ab12.cjs")`;
  const dir = fixture({
    js,
    css,
    ext: `const c = ${call};\n${ext.toString('hex')}`,
  });
  fs.writeFileSync(path.join(dir, 'core-Ab12.cjs'), core);
  // Loaded by the core chunk, not by extension.cjs: stays out, as at the base.
  fs.writeFileSync(path.join(dir, 'grammar-Cd34.cjs'), grammar);
  assert.deepStrictEqual(hostFiles(dir), [
    path.join(dir, 'extension.cjs'),
    path.join(dir, 'core-Ab12.cjs'),
  ]);
  const host = gz(fs.readFileSync(path.join(dir, 'extension.cjs'))) + gz(core);
  assert.ok(verdict(dir, { ...loose, extensionGzip: host }, 'P2'));
  assert.ok(!verdict(dir, { ...loose, extensionGzip: host - 1 }, 'P2'));
});

test('the webview.js byte limit passes at the file size and fails one byte below', () => {
  assert.ok(verdict(dist, { ...loose, webviewJsRaw: js.length }, 'webview.js'));
  assert.ok(
    !verdict(dist, { ...loose, webviewJsRaw: js.length - 1 }, 'webview.js'),
  );
});

test('the webview.css byte limit passes at the file size and fails one byte below', () => {
  assert.ok(
    verdict(dist, { ...loose, webviewCssRaw: css.length }, 'webview.css'),
  );
  assert.ok(
    !verdict(dist, { ...loose, webviewCssRaw: css.length - 1 }, 'webview.css'),
  );
});

test('the table names every check with its measured value and limit', () => {
  const table = formatTable(measure(dist, loose));
  assert.match(table, /P1 webview\.js \+ webview\.css \(gzip\)/);
  assert.match(
    table,
    new RegExp(`webview\\.js \\(bytes\\)\\s+${js.length}\\s`),
  );
  assert.match(table, /1000000/);
});

test('the shipped limits are the documented ones', () => {
  assert.strictEqual(P1_WEBVIEW_GZIP_MAX, 28_000);
  assert.strictEqual(P2_EXTENSION_GZIP_MAX, 157_663);
  assert.strictEqual(WEBVIEW_JS_RAW_MAX, 29_859);
  assert.strictEqual(WEBVIEW_CSS_RAW_MAX, 15_244);
  assert.deepStrictEqual(LIMITS, {
    webviewGzip: 28_000,
    extensionGzip: 157_663,
    webviewJsRaw: 29_859,
    webviewCssRaw: 15_244,
  });
});

test('a missing bundle throws instead of passing', () => {
  const dir = tempDir();
  assert.throws(() => measure(dir, loose), /ENOENT/);
});

test('the script exits 0 under the shipped limits and 1 over one of them', () => {
  const small = fixture({ js: 'a', css: 'b', ext: 'c' });
  const ok = spawnSync(process.execPath, [gate, small], { encoding: 'utf8' });
  assert.strictEqual(ok.status, 0, ok.stdout + ok.stderr);
  assert.match(ok.stdout, /Size gate passed/);

  const big = fixture({
    js: Buffer.alloc(LIMITS.webviewJsRaw + 1, 'a'),
    css: 'b',
    ext: 'c',
  });
  const bad = spawnSync(process.execPath, [gate, big], { encoding: 'utf8' });
  assert.strictEqual(bad.status, 1);
  assert.match(bad.stderr, /SIZE GATE FAILED: webview\.js \(bytes\)/);

  const wide = fixture({
    js: 'a',
    css: Buffer.alloc(LIMITS.webviewCssRaw + 1, 'b'),
    ext: 'c',
  });
  const badCss = spawnSync(process.execPath, [gate, wide], {
    encoding: 'utf8',
  });
  assert.strictEqual(badCss.status, 1);
  assert.match(badCss.stderr, /SIZE GATE FAILED: webview\.css \(bytes\)/);
});

test('the script passes a stylesheet exactly at its limit', () => {
  const edge = fixture({
    js: 'a',
    css: Buffer.alloc(LIMITS.webviewCssRaw, 'b'),
    ext: 'c',
  });
  const r = spawnSync(process.execPath, [gate, edge], { encoding: 'utf8' });
  assert.strictEqual(r.status, 0, r.stdout + r.stderr);
});

// Compressible text where the compression level shows in the size (random bytes do not
// compress, so every level gives the same result on them).
const words = ['alpha', 'beta', 'gamma', 'delta', 'lambda', 'sigma', 'omega'];
const prose = Buffer.from(
  Array.from({ length: 4000 }, (_, i) => words[(i * 7 + (i >> 3)) % 7]).join(
    ' ',
  ),
);

test('gzip sizes are measured at level 9', () => {
  const level1 = zlib.gzipSync(prose, { level: 1 }).length;
  assert.ok(gz(prose) < level1, 'the fixture tells level 9 from level 1');
  const compressible = fixture({ js: prose, css: prose, ext: prose });
  const p1 = gz(prose) * 2;
  assert.ok(verdict(compressible, { ...loose, webviewGzip: p1 }, 'P1'));
  assert.ok(!verdict(compressible, { ...loose, webviewGzip: p1 - 1 }, 'P1'));
  assert.ok(
    verdict(compressible, { ...loose, extensionGzip: gz(prose) }, 'P2'),
  );
  assert.ok(
    !verdict(compressible, { ...loose, extensionGzip: gz(prose) - 1 }, 'P2'),
  );
});

test('the table marks a check over its limit and the others ok', () => {
  const lines = formatTable(
    measure(dist, { ...loose, webviewCssRaw: 1 }),
  ).split('\n');
  const line = (check: string): string =>
    lines.find((l) => l.startsWith(check)) ?? '';
  assert.match(lines[0] ?? '', /verdict$/);
  assert.match(line('webview.css (bytes)'), /\sOVER$/);
  for (const check of ['P1', 'P2', 'webview.js (bytes)'])
    assert.match(line(check), /\sok$/, check);
});
