// The .vsix is byte-identical for the same SOURCE_DATE_EPOCH (vsce then fixes the zip mtimes and sorts
// the files), and differs for another one. The first test fails when the epoch is ignored (the in-memory
// entries then carry the wall clock); the second when the epoch does not reach the timestamps. Runs the
// real vsce on the built dist/, into a temp folder under artifacts/tmp.
import { after, before, test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { layoutPath, repoRoot } from '../../eng/layout.ts';
import { builtDist } from '../helpers/dist.ts';

builtDist();

const vsce = fileURLToPath(import.meta.resolve('@vscode/vsce/vsce'));
const EPOCH = 1_700_000_000;
const YEAR = 365 * 24 * 60 * 60;

let work = '';
before(() => {
  fs.mkdirSync(layoutPath('tmp'), { recursive: true });
  work = fs.mkdtempSync(path.join(layoutPath('tmp'), 'reproducible-'));
});
after(() => {
  fs.rmSync(work, { recursive: true, force: true });
});

/** SHA-256 of a .vsix that `vsce package` builds with `SOURCE_DATE_EPOCH` set to `epoch`. */
function packageHash(name: string, epoch: number): string {
  const out = path.join(work, `${name}.vsix`);
  const result = spawnSync(
    process.execPath,
    [vsce, 'package', '--no-dependencies', '--out', out],
    {
      cwd: repoRoot,
      encoding: 'utf8',
      env: { ...process.env, SOURCE_DATE_EPOCH: String(epoch) },
    },
  );
  assert.strictEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return crypto.createHash('sha256').update(fs.readFileSync(out)).digest('hex');
}

test('two packages with the same SOURCE_DATE_EPOCH have the same SHA-256', () => {
  assert.strictEqual(packageHash('a', EPOCH), packageHash('b', EPOCH));
});

test('a package with another SOURCE_DATE_EPOCH has another SHA-256', () => {
  assert.notStrictEqual(
    packageHash('c', EPOCH),
    packageHash('d', EPOCH + YEAR),
  );
});
