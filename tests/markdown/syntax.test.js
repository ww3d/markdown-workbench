// Markdown source primitives shared by the editor commands, the preview and
// the clipboard diff: CHECKBOX_RE. The table reflow lives in src/tables/format.js
// (tests/tables/format.test.js).
// This module must stay usable without the extension host - unlike the other
// test files it deliberately does not require tests/helpers/vscode-mock.js.
import { test } from 'node:test';
import assert from 'node:assert';

import { CHECKBOX_RE, checkboxBoxPos } from '../../src/markdown/syntax.js';

test('src/markdown/syntax.js loads without vscode', async () => {
  // A query of its own makes it a fresh load, before any mock is installed.
  await assert.doesNotReject(import('../../src/markdown/syntax.js?nomock'));
});

// --- CHECKBOX_RE ---

test('CHECKBOX_RE matches plain and numbered task items', () => {
  let m = CHECKBOX_RE.exec('- [ ] text');
  assert.strictEqual(m[1], '- ');
  assert.strictEqual(m[2], ' ');
  assert.strictEqual(m[3], ' text');
  m = CHECKBOX_RE.exec('1. [X] text');
  assert.strictEqual(m[2], 'X');
});

test('CHECKBOX_RE matches compound markers and an empty label', () => {
  const m = CHECKBOX_RE.exec('1. - [ ] text');
  assert.strictEqual(m[1], '1. - ');
  const empty = CHECKBOX_RE.exec('- [ ]');
  assert.strictEqual(empty[3], undefined);
});

test('CHECKBOX_RE (counter-check) rejects a missing marker, bad box char and no gap after the box', () => {
  assert.strictEqual(CHECKBOX_RE.exec('[ ] text'), null);
  assert.strictEqual(CHECKBOX_RE.exec('- [z] text'), null);
  assert.strictEqual(CHECKBOX_RE.exec('- [ ]text'), null);
});

// --- checkboxBoxPos ---

test('checkboxBoxPos points at the char between the brackets, plain and compound markers', () => {
  assert.strictEqual(checkboxBoxPos(CHECKBOX_RE.exec('- [ ] text')), 3);
  assert.strictEqual(checkboxBoxPos(CHECKBOX_RE.exec('1. - [ ] text')), 6);
});

test('(counter-check) checkboxBoxPos ignores the box char and label, only the prefix', () => {
  const shortLabel = checkboxBoxPos(CHECKBOX_RE.exec('- [x] a'));
  const longLabel = checkboxBoxPos(
    CHECKBOX_RE.exec('- [ ] a much longer label'),
  );
  assert.strictEqual(shortLabel, longLabel);
});
