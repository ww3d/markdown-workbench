// The preload turns Node's compile cache on for every test process and puts it under the
// layout's obj folder; without it every test file re-parses the sources it imports.
import { test } from 'node:test';
import assert from 'node:assert';
import { getCompileCacheDir } from 'node:module';
import { layoutPath } from '../../eng/layout.ts';

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
