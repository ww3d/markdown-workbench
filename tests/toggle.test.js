// Source mutation paths: list toggles (uniform multi-select, single undo
// step) and table cell toggles (nth occurrence, code spans blanked).
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh, MockDocument } = require('./helpers/vscode-mock');

const vscode = install();
const { _internal } = loadFresh('extension.js');
const { applyToggle, applyCellToggle } = _internal;

function freshDoc(text) { vscode._applied.length = 0; return new MockDocument(text); }

test('applyToggle flips a single open box to checked', () => {
  const doc = freshDoc('- [ ] task');
  applyToggle(doc, [0], true);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(vscode._applied[0].text, 'x');
  assert.strictEqual(vscode._applied[0].range.start.character, 3);
});

test('applyToggle sets a uniform state across mixed lines in one edit', () => {
  const doc = freshDoc('- [ ] a\n- [x] b\n- [ ] c');
  applyToggle(doc, [0, 1, 2], true);
  assert.strictEqual(vscode._applied.length, 3, 'one WorkspaceEdit, three ops, single undo step');
  for (const op of vscode._applied) assert.strictEqual(op.text, 'x');
});

test('applyToggle skips lines that are no task items', () => {
  const doc = freshDoc('- [ ] a\nplain text');
  applyToggle(doc, [0, 1], true);
  assert.strictEqual(vscode._applied.length, 1);
});

test('applyToggle handles numbered and nested markers', () => {
  const doc = freshDoc('1. [ ] a\n  - [x] b');
  applyToggle(doc, [0, 1], false);
  assert.strictEqual(vscode._applied.length, 2);
  for (const op of vscode._applied) assert.strictEqual(op.text, ' ');
});

test('applyCellToggle flips the nth bracket on a row line', () => {
  const line = '| app | [x] | [ ] |';
  const doc = freshDoc(line);
  applyCellToggle(doc, 0, 1, true);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(vscode._applied[0].range.start.character, line.lastIndexOf('[ ]') + 1);
});

test('applyCellToggle ignores brackets inside code spans (index parity with renderer)', () => {
  const line = '| git `[ ]` | [x] | [ ] |';
  const doc = freshDoc(line);
  applyCellToggle(doc, 0, 0, false);
  assert.strictEqual(vscode._applied[0].range.start.character, line.indexOf('[x]') + 1);
});

test('applyCellToggle is a no-op for out-of-range lines and indices', () => {
  const doc = freshDoc('| a | [ ] |');
  applyCellToggle(doc, 5, 0, true);
  applyCellToggle(doc, 0, 9, true);
  assert.strictEqual(vscode._applied.length, 0);
});
