// The mandatory-field check before packaging: every missing value in one error, exit code 1; a
// complete manifest exits 0. The CLI runs against a temp root, so the shipped package.json is not touched.
import { after, test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  missingPackageFields,
  type PackageManifest,
} from '../../scripts/package-fields.ts';
import pkg from '../../package.json' with { type: 'json' };

const script = path.resolve(
  import.meta.dirname,
  '../../scripts/package-fields.ts',
);

const complete: PackageManifest = {
  publisher: 'ww3d',
  description: 'A description.',
  license: 'MIT',
  repository: { type: 'git', url: 'https://example.test/repo' },
};

const dirs: string[] = [];
after(() => {
  for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true });
});

/** A repository root fixture: the manifest, and a LICENSE file when asked for. */
function fixture(manifest: unknown, withLicense: boolean): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-package-fields-'));
  dirs.push(dir);
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify(manifest));
  if (withLicense) fs.writeFileSync(path.join(dir, 'LICENSE'), 'MIT\n');
  return dir;
}

function run(root: string) {
  return spawnSync(process.execPath, [script, root], { encoding: 'utf8' });
}

test('a complete manifest with a LICENSE file misses nothing', () => {
  assert.deepStrictEqual(missingPackageFields(complete, true), []);
});

test('every mandatory value is reported by name, in a fixed order', () => {
  assert.deepStrictEqual(missingPackageFields({}, false), [
    'publisher',
    'description',
    'license',
    'repository.url',
    'repository.type',
    'LICENSE',
  ]);
});

test('each value counts as missing on its own', () => {
  const cases: readonly (readonly [string, PackageManifest, boolean])[] = [
    ['publisher', { ...complete, publisher: undefined }, true],
    ['description', { ...complete, description: undefined }, true],
    ['license', { ...complete, license: undefined }, true],
    ['repository.url', { ...complete, repository: { type: 'git' } }, true],
    ['repository.type', { ...complete, repository: { url: 'u' } }, true],
    ['LICENSE', complete, false],
  ];
  for (const [name, manifest, hasLicense] of cases)
    assert.deepStrictEqual(missingPackageFields(manifest, hasLicense), [name]);
});

test('blank and non-string values count as missing', () => {
  assert.deepStrictEqual(
    missingPackageFields(
      { ...complete, publisher: '  ', description: 3, repository: 'git://x' },
      true,
    ),
    ['publisher', 'description', 'repository.url', 'repository.type'],
  );
});

test('the CLI names all missing values in one error and exits 1', () => {
  const result = run(fixture({ publisher: 'ww3d', license: 'MIT' }, false));
  assert.strictEqual(result.status, 1);
  assert.strictEqual(
    result.stderr.trim(),
    'Mandatory package fields missing: description, repository.url, repository.type, LICENSE.',
  );
});

test('the CLI exits 0 on a complete manifest', () => {
  const result = run(fixture(complete, true));
  assert.strictEqual(result.status, 0, result.stderr);
});

test('the shipped package.json and LICENSE are complete', () => {
  const root = path.resolve(import.meta.dirname, '../..');
  assert.deepStrictEqual(
    missingPackageFields(pkg, fs.existsSync(path.join(root, 'LICENSE'))),
    [],
  );
});
