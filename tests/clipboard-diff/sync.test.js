// Offset mapping of the selection page's write-through (sync.js) where the
// page drifted from the file region through a save action.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh } = require('../helpers/vscode-mock');

install();
const { offsetMap } = loadFresh('src/clipboard-diff/sync.js')._internal;

test('in sync, page offsets are file-region offsets', () => {
  assert.strictEqual(offsetMap('abc', 'abc')(1, 2), 1);
});

test('edits before and after a drifted span are shifted around it', () => {
  // The page lost a trailing space on line 1 ("one \n" -> "one\n").
  const map = offsetMap('one\ntwo', 'one \ntwo');
  assert.strictEqual(map(0, 1), 0);
  assert.strictEqual(map(5, 6), 6);
});

test('an edit inside the drifted span cannot be mapped (counter-check)', () => {
  // Page "abXd", region "abYd": the page's "X" is a save action's edit.
  const map = offsetMap('abXd', 'abYd');
  assert.strictEqual(map(2, 3), null);
  assert.strictEqual(map(3, 3), 3, 'right after the drift is fine');
});

test('two drifted lines leave the line between them mappable', () => {
  const map = offsetMap('a\nb\nc\n', 'a \nb\nc \n');
  assert.strictEqual(
    map(2, 3),
    3,
    'an edit of "b" maps past the trailing space of "a "',
  );
  assert.strictEqual(map(4, 4), 5);
  assert.strictEqual(
    map(1, 1),
    1,
    'the end of a drifted line maps before its drift',
  );
});

test('a change across lines maps only when every touched line is unchanged', () => {
  assert.strictEqual(offsetMap('x\ny\nz \n', 'x\ny\nz\n')(0, 3), 0);
  assert.strictEqual(offsetMap('x \ny\nz\n', 'x\ny\nz\n')(0, 3), null);
});

test('different line counts fall back to the one differing span', () => {
  const map = offsetMap('a\nb', 'a\nb\n');
  assert.strictEqual(map(0, 1), 0);
});
