// The preload turns Node's compile cache on for every test process and puts it under the
// layout's obj folder; without it every test file re-parses the sources it imports.
import { test } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import { getCompileCacheDir } from 'node:module';
import path from 'node:path';
import pkg from '../../package.json' with { type: 'json' };
import { layoutPath, repoRoot } from '../../eng/layout.ts';

test('the test preload enables the compile cache under the layout', {
  skip: process.env.NODE_DISABLE_COMPILE_CACHE !== undefined,
}, () => {
  const dir = getCompileCacheDir();
  assert.ok(dir !== undefined, 'the compile cache is enabled');
  assert.ok(
    dir.startsWith(layoutPath('compileCache')),
    `${dir} is not under ${layoutPath('compileCache')}`,
  );
});

test('the unit run starts its test processes with the compile cache of the layout', () => {
  // The runner does not run the preload itself; only an environment it inherits reaches the
  // processes it starts before their first module.
  const envFile = /--env-file=(\S+)/.exec(pkg.scripts.test)?.[1];
  assert.ok(envFile, 'pnpm test reads an env file');
  const text = fs.readFileSync(path.join(repoRoot, envFile), 'utf8');
  const value = /^NODE_COMPILE_CACHE=(.+)$/m.exec(text)?.[1];
  assert.ok(value, `${envFile} sets NODE_COMPILE_CACHE`);
  // The file names the default root; a moved root is passed by the orchestrator as the variable itself,
  // which wins over the file (tests/eng/build.test.ts pins that).
  assert.strictEqual(
    path.resolve(repoRoot, value),
    layoutPath('compileCache', {}),
  );
});
