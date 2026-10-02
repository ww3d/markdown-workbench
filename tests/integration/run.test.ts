// Pure parts of the integration runner (tests/integration/run.ts): the Windows
// path check before VS Code starts and the cleanup that never hides the error
// of the run (ww3d/markdown-workbench#94).
import test from 'node:test';
import type { TestContext } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  assertPathFits,
  cleanup,
  vscodeCacheDir,
  WINDOWS_MAX_PATH,
} from './run.ts';

// The two layouts: 1.100.0 flat with electron-sandbox, 1.139.1 in a commit
// folder with electron-browser.
const LAYOUTS: Record<string, { commit: boolean; host: string }> = {
  '1.100.0': { commit: false, host: 'electron-sandbox' },
  '1.139.1': { commit: true, host: 'electron-browser' },
};

// An unpacked VS Code under os.tmpdir() whose workbench.html path is `length`
// characters long, in the layout of `version`; without `length` the shortest
// the temp folder allows (Windows temp paths alone run past 30 characters).
// Returns the executable path.
function install(t: TestContext, length?: number, version = '1.139.1'): string {
  const layout = LAYOUTS[version];
  if (!layout) throw new Error(`no layout for ${version}`);
  const { commit, host } = layout;
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-run-test-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const inner = [
    ...(commit ? ['04c0d99f4f'] : []),
    'resources',
    'app',
    'out',
    ...['vs', 'code', host, 'workbench', 'workbench.html'],
  ];
  const rest = path.join(base, 'x', ...inner).length - 1;
  const pad = length === undefined ? 1 : length - rest;
  if (pad < 1)
    throw new Error(
      `cannot build a ${length}-character path under ${base}: it needs ${rest + 1} at least`,
    );
  const dir = path.join(base, 'x'.repeat(pad));
  const page = path.join(dir, ...inner);
  if (length !== undefined) assert.equal(page.length, length);
  fs.mkdirSync(path.dirname(page), { recursive: true });
  fs.writeFileSync(page, '');
  return path.join(dir, 'Code.exe');
}

test('a workbench.html path below the Windows limit passes', (t) => {
  const exe = install(t);
  const [page] = fs.globSync('**/workbench.html', { cwd: path.dirname(exe) });
  assert.ok(page, 'the page exists');
  assert.ok(
    path.join(path.dirname(exe), page).length < WINDOWS_MAX_PATH,
    'the shortest page path is below the limit',
  );
  assert.doesNotThrow(() => assertPathFits(exe, 'win32'));
});

test('install() says so when the temp folder is too long for a length', (t) => {
  assert.throws(() => install(t, 10), /cannot build a 10-character path/);
});

test('a long workbench.html path stops the run on Windows with length, limit, path and remedy', (t) => {
  const exe = install(t, 300);
  assert.throws(
    () => assertPathFits(exe, 'win32'),
    (err: Error) =>
      /300 characters/.test(err.message) &&
      /limit: 260/.test(err.message) &&
      err.message.includes(path.dirname(exe)) &&
      /shorter path/.test(err.message),
  );
});

test('the same long path passes on Linux', (t) => {
  assert.doesNotThrow(() => assertPathFits(install(t, 300), 'linux'));
});

for (const version of Object.keys(LAYOUTS)) {
  test(`the limit is exclusive in the ${version} layout: 259 passes, 260 stops`, (t) => {
    const below = install(t, WINDOWS_MAX_PATH - 1, version);
    const at = install(t, WINDOWS_MAX_PATH, version);
    assert.doesNotThrow(() => assertPathFits(below, 'win32'));
    assert.throws(() => assertPathFits(at, 'win32'), /260 characters/);
  });
}

test('an install without a workbench.html is reported, not passed silently', (t) => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-run-test-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const warnings: string[] = [];
  assertPathFits(path.join(base, 'Code.exe'), 'win32', (m) => warnings.push(m));
  assert.equal(warnings.length, 1);
  assert.match(warnings[0] ?? '', /no workbench\.html/);
});

test('cleanup removes an existing directory', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-run-test-'));
  fs.writeFileSync(path.join(dir, 'f.txt'), 'x');
  cleanup(dir);
  assert.equal(fs.existsSync(dir), false);
});

test('cleanup turns an EPERM into a warning with path and code', () => {
  const warnings: string[] = [];
  const rmSync = () => {
    throw Object.assign(new Error('operation not permitted'), {
      code: 'EPERM',
    });
  };
  assert.doesNotThrow(() =>
    cleanup('C:\\tmp\\mdwb-x', { rmSync, warn: (m) => warnings.push(m) }),
  );
  assert.equal(warnings.length, 1);
  assert.ok(warnings[0]?.includes('C:\\tmp\\mdwb-x'));
  assert.ok(warnings[0]?.includes('EPERM'));
});

test('the VS Code cache folder is created with its missing parents', (t) => {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-run-cache-'));
  t.after(() => fs.rmSync(base, { recursive: true, force: true }));
  const dir = path.join(base, 'artifacts', 'toolset', 'vscode-test');
  assert.equal(vscodeCacheDir(dir), dir);
  assert.ok(fs.statSync(dir).isDirectory());
});
