// The type probes only work while the check that should reject them actually includes them: a
// narrowed `include` would drop a probe from its scope and `tsc -b` would still end with exit 0.
// The tests ask the compiler which files each scope checks (`--listFilesOnly`).
import { test } from 'node:test';
import assert from 'node:assert';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { repoRoot } from '../../eng/layout.ts';

const tsc = path.join(
  path.dirname(fileURLToPath(import.meta.resolve('typescript/package.json'))),
  'bin',
  'tsc',
);

/** The repository-relative files one tsconfig checks, with forward slashes. */
function filesOf(config: string): Set<string> {
  const r = spawnSync(
    process.execPath,
    [tsc, '--listFilesOnly', '-p', config],
    { cwd: repoRoot, encoding: 'utf8' },
  );
  assert.strictEqual(r.status, 0, r.stdout + r.stderr);
  return new Set(
    r.stdout
      .split('\n')
      .map((line) => path.relative(repoRoot, line.trim()).replaceAll('\\', '/'))
      .filter((file) => file !== '' && !file.startsWith('..')),
  );
}

test('the host scope checks its probe and not the webview one', () => {
  const files = filesOf('tsconfig.host.json');
  assert.ok(files.has('tests/probes/host.probe.ts'));
  assert.ok(!files.has('tests/probes/webview.probe.ts'));
});

test('the webview scope checks its probe and not the host one', () => {
  const files = filesOf('tsconfig.webview.json');
  assert.ok(files.has('tests/probes/webview.probe.ts'));
  assert.ok(!files.has('tests/probes/host.probe.ts'));
});

test('the tests scope checks the protocol probe and leaves the scope probes to their scopes', () => {
  // Under the tests scope (DOM and Node both present) the scope probes would fail their
  // own directives.
  const files = filesOf('tsconfig.tests.json');
  assert.ok(files.has('tests/webview/protocol.probe.ts'));
  assert.ok(!files.has('tests/probes/host.probe.ts'));
  assert.ok(!files.has('tests/probes/webview.probe.ts'));
});
