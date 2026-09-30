// The integration suite lists its case files by hand (suite/index.ts): the bundler needs the
// static imports, so the folder cannot be read at run time. A new *.int.ts that is not listed
// would run in no phase and raise no error, so this test compares the list with the folder.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

const suiteDir = path.join(import.meta.dirname, 'suite');

test('every *.int.ts case file is listed in SUITES, and every entry names one', () => {
  const onDisk = fs
    .readdirSync(suiteDir)
    .filter((f) => f.endsWith('.int.ts'))
    .sort();
  const index = fs.readFileSync(path.join(suiteDir, 'index.ts'), 'utf8');
  const listed = [...index.matchAll(/import\('\.\/([^']+\.int\.ts)'\)/g)]
    .map((m) => m[1])
    .sort();
  assert.ok(onDisk.length > 0, 'the suite folder has case files');
  assert.deepStrictEqual(listed, onDisk);
});
