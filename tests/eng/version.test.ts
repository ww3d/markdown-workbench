// The package version of a build says what made the file (ww3d/atlas docs/versioning.md): -dev for a local
// build, -ci for CI, -preview.<iteration>.<short date>.<revision> for an official build, nothing for a
// release. package.json keeps the release version, which the Marketplace takes.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  buildKind,
  packageVersion,
  parseOfficialBuildId,
} from '../../eng/version.ts';

test('the kind of build follows the flags: release beats an official id beats --ci beats local', () => {
  assert.strictEqual(buildKind({ ci: false, release: false }), 'dev');
  assert.strictEqual(buildKind({ ci: true, release: false }), 'ci');
  assert.strictEqual(
    buildKind({ ci: true, release: false, officialBuildId: '20260930.1' }),
    'official',
  );
  assert.strictEqual(
    buildKind({ ci: false, release: false, officialBuildId: '20260930.1' }),
    'official',
  );
  assert.strictEqual(
    buildKind({ ci: true, release: true, officialBuildId: '20260930.1' }),
    'release',
  );
});

test('a local and a CI package carry their label, a release carries none', () => {
  assert.strictEqual(packageVersion('0.37.0', 'dev'), '0.37.0-dev');
  assert.strictEqual(packageVersion('0.37.0', 'ci'), '0.37.0-ci');
  assert.strictEqual(packageVersion('0.37.0', 'release'), '0.37.0');
});

test('an official build carries label, iteration, short date and revision (Atlas: yy*1000 + mm*50 + dd)', () => {
  // 2026-09-30: 26 * 1000 + 9 * 50 + 30 = 26480.
  assert.strictEqual(
    packageVersion('0.37.0', 'official', '20260930.1'),
    '0.37.0-preview.1.26480.1',
  );
  assert.deepStrictEqual(parseOfficialBuildId('20260101.0'), {
    shortDate: 26051,
    revision: 0,
  });
  assert.deepStrictEqual(parseOfficialBuildId('20261231.99'), {
    shortDate: 26 * 1000 + 12 * 50 + 31,
    revision: 99,
  });
});

test('later builds sort higher: the short date and the revision grow with the calendar', () => {
  const key = (id: string): number => {
    const { shortDate, revision } = parseOfficialBuildId(id);
    return shortDate * 100 + revision;
  };
  const ids = [
    '20260930.1',
    '20260930.2',
    '20261001.1',
    '20261101.1',
    '20270101.1',
  ];
  assert.deepStrictEqual(
    ids,
    [...ids].sort((a, b) => key(a) - key(b)),
  );
});

test('an official build id of another shape, a date that does not exist or a counter above 99 is refused', () => {
  for (const bad of [
    '',
    '2026-09-30.1',
    '260930.1',
    '20260930',
    '20260930.',
    '20260930.x',
    '19990930.1',
  ]) {
    assert.throws(() => parseOfficialBuildId(bad), /is not 'yyyymmdd\.r'/, bad);
  }
  assert.throws(() => parseOfficialBuildId('20261301.1'), /names no date/);
  assert.throws(() => parseOfficialBuildId('20260032.1'), /names no date/);
  assert.throws(() => parseOfficialBuildId('20260930.100'), /between 0 and 99/);
});

test('an official build without an id, and a prefix that is no MAJOR.MINOR.PATCH, are errors', () => {
  assert.throws(
    () => packageVersion('0.37.0', 'official'),
    /needs an official build id/,
  );
  for (const bad of ['0.37', '1.2.3-dev', 'v1.2.3', '']) {
    assert.throws(
      () => packageVersion(bad, 'dev'),
      /is not MAJOR\.MINOR\.PATCH/,
      bad,
    );
  }
});
