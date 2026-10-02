// Markdown source primitives shared by the editor commands, the preview and
// the clipboard diff: CHECKBOX_RE. The table reflow lives in src/tables/format.ts
// (tests/tables/format.test.ts).
// This module must stay usable without the extension host - unlike the other
// test files it deliberately does not require tests/helpers/vscode-mock.ts.
import { test } from 'node:test';
import assert from 'node:assert';

import { CHECKBOX_RE, checkboxBoxPos } from '../../src/markdown/syntax.ts';

// The CHECKBOX_RE match of a line the test expects to be a task item.
function taskMatch(line: string): RegExpExecArray {
  const m = CHECKBOX_RE.exec(line);
  assert.ok(m, `no CHECKBOX_RE match: ${line}`);
  return m;
}

test('src/markdown/syntax.js loads without vscode', async () => {
  // A query of its own makes it a fresh load, before any mock is installed.
  const fresh = new URL('../../src/markdown/syntax.ts?nomock', import.meta.url);
  await assert.doesNotReject(import(fresh.href));
});

// --- CHECKBOX_RE ---

test('CHECKBOX_RE matches plain and numbered task items', () => {
  let m = taskMatch('- [ ] text');
  assert.strictEqual(m[1], '- ');
  assert.strictEqual(m[2], ' ');
  assert.strictEqual(m[3], ' text');
  m = taskMatch('1. [X] text');
  assert.strictEqual(m[2], 'X');
});

test('CHECKBOX_RE matches compound markers and an empty label', () => {
  const m = taskMatch('1. - [ ] text');
  assert.strictEqual(m[1], '1. - ');
  const empty = taskMatch('- [ ]');
  assert.strictEqual(empty[3], undefined);
});

test('CHECKBOX_RE (counter-check) rejects a missing marker, bad box char and no gap after the box', () => {
  assert.strictEqual(CHECKBOX_RE.exec('[ ] text'), null);
  assert.strictEqual(CHECKBOX_RE.exec('- [z] text'), null);
  assert.strictEqual(CHECKBOX_RE.exec('- [ ]text'), null);
});

// --- checkboxBoxPos ---

test('checkboxBoxPos points at the char between the brackets, plain and compound markers', () => {
  assert.strictEqual(checkboxBoxPos(taskMatch('- [ ] text')), 3);
  assert.strictEqual(checkboxBoxPos(taskMatch('1. - [ ] text')), 6);
});

test('(counter-check) checkboxBoxPos ignores the box char and label, only the prefix', () => {
  const shortLabel = checkboxBoxPos(taskMatch('- [x] a'));
  const longLabel = checkboxBoxPos(taskMatch('- [ ] a much longer label'));
  assert.strictEqual(shortLabel, longLabel);
});
