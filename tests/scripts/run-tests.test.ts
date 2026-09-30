// The unit run starts one test process per core, not a fixed number (DECISIONS.md #50): the
// argument builder takes the core count as given, and a real launch with a stubbed core count
// shows that many test files alive at once. Exit codes of the child reach the caller.
import { after, test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { exitCode, testArgs } from '../../scripts/run-tests.ts';

const launcher = path.resolve(
  import.meta.dirname,
  '../../scripts/run-tests.ts',
);
const stub = path.resolve(import.meta.dirname, 'stub-cores.ts');

const dirs: string[] = [];
after(() => {
  for (const dir of dirs) fs.rmSync(dir, { recursive: true, force: true });
});

test('testArgs puts the core count into --test-concurrency and keeps the caller arguments', () => {
  assert.deepStrictEqual(testArgs(7, ['--import', 'x.ts', 'a.test.ts']), [
    '--test',
    '--test-concurrency=7',
    '--import',
    'x.ts',
    'a.test.ts',
  ]);
  assert.deepStrictEqual(testArgs(2, []), ['--test', '--test-concurrency=2']);
});

test('exitCode passes the exit code on and turns a signal into 1', () => {
  assert.strictEqual(exitCode(0, null), 0);
  assert.strictEqual(exitCode(3, null), 3);
  assert.strictEqual(exitCode(null, 'SIGTERM'), 1);
  assert.strictEqual(exitCode(null, null), 1);
});

/** Runs the launcher with `os.availableParallelism()` stubbed to `cores` over `files` fixtures. */
function launch(cores: number, files: number, failing = false) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mdwb-run-tests-'));
  dirs.push(dir);
  const body = `
    import { test } from 'node:test';
    import assert from 'node:assert';
    import fs from 'node:fs';
    const dir = ${JSON.stringify(dir)};
    const cores = ${cores};
    test('alive together', async () => {
      const mine = dir + '/alive-' + process.pid;
      fs.writeFileSync(mine, '');
      fs.writeFileSync(dir + '/seen-' + process.pid, '');
      const peak = fs.readdirSync(dir).filter((f) => f.startsWith('alive-')).length;
      fs.appendFileSync(dir + '/peaks', peak + '\\n');
      // Holds until every core's worth of files started, so a smaller process count times out.
      const end = Date.now() + 15_000;
      while (fs.readdirSync(dir).filter((f) => f.startsWith('seen-')).length < cores && Date.now() < end) {
        await new Promise((r) => setTimeout(r, 10));
      }
      const seen = fs.readdirSync(dir).filter((f) => f.startsWith('seen-')).length;
      fs.rmSync(mine);
      assert.ok(seen >= cores);
      assert.ok(${!failing});
    });
  `;
  for (let i = 0; i < files; i++)
    fs.writeFileSync(path.join(dir, `f${i}.test.mjs`), body);
  // Inside the outer runner NODE_TEST_CONTEXT would make the inner `node --test` a reporting child.
  const { NODE_TEST_CONTEXT: _context, ...env } = process.env;
  const result = spawnSync(
    process.execPath,
    [
      '--import',
      stub,
      launcher,
      ...fs
        .readdirSync(dir)
        .filter((f) => f.endsWith('.mjs'))
        .map((f) => path.join(dir, f)),
    ],
    { encoding: 'utf8', env: { ...env, STUB_CORES: String(cores) } },
  );
  const peaks = fs.existsSync(path.join(dir, 'peaks'))
    ? fs
        .readFileSync(path.join(dir, 'peaks'), 'utf8')
        .trim()
        .split('\n')
        .map(Number)
    : [];
  return { status: result.status, peak: Math.max(0, ...peaks) };
}

test('the launcher runs as many test processes at once as there are cores', () => {
  // Six cores (stubbed, so it differs from any fixed count) and eight files: the run is green
  // only when six were alive together, and no seventh started while they held.
  const { status, peak } = launch(6, 8);
  assert.strictEqual(status, 0);
  assert.strictEqual(peak, 6);
});

test('the launcher passes the exit code of a failing run on', () => {
  const { status } = launch(2, 2, true);
  assert.strictEqual(status, 1);
});
