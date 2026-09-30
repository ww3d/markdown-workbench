// Emphasis marker alignment: masks code spans and inline HTML, then swaps
// _x_ / __x__ (or *x* / **x**) delimiters to the baseline's markers.
// Pure, no vscode.
import { test } from 'node:test';
import assert from 'node:assert';
import { alignStyle } from '../../src/clipboard-diff/style.ts';

test('alignStyle converts _x_ to *x* and __x__ to **x**', () => {
  const result = alignStyle('This is _em_ and __strong__ text.', {
    emphasis: '*',
    strong: '**',
  });
  assert.strictEqual(result.text, 'This is *em* and **strong** text.');
  assert.strictEqual(result.changed, 1);
});

test('code spans and inline HTML are masked in linear time', () => {
  const t = Date.now();
  alignStyle(`${'`'.repeat(20000)} _a_ ${'<'.repeat(20000)}\n`, {
    bullet: null,
    emphasis: '*',
    strong: null,
    table: null,
  });
  assert.ok(Date.now() - t < 1000, `took ${Date.now() - t} ms`);
});
