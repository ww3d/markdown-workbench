// Scroll sync math, ported from the built-in preview: fractional visible
// line and the character-offset encoding used to reveal fractional lines.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh, MockDocument, MockEditor, Range, Position } = require('./helpers/vscode-mock');

const vscode = install();
const { _internal } = loadFresh('src/views.js');
const { getVisibleLine, scrollEditorToLine } = _internal;

test('getVisibleLine adds the character fraction of the top line', () => {
  const doc = new MockDocument('0123456789\nsecond');
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(0, 6), new Position(1, 0))];
  // line 0, char 6, length 10 -> 0 + 6/(10+2) = 0.5
  assert.ok(Math.abs(getVisibleLine(editor) - 0.5) < 1e-9);
});

test('getVisibleLine is integer at column zero', () => {
  const doc = new MockDocument('a\nb\nc');
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(2, 0), new Position(2, 0))];
  assert.strictEqual(getVisibleLine(editor), 2);
});

test('scrollEditorToLine encodes the fraction as a character offset', () => {
  const doc = new MockDocument('0123456789\nsecond');
  const editor = new MockEditor(doc);
  scrollEditorToLine(0.5, editor);
  assert.strictEqual(editor.revealed.length, 1);
  const { range } = editor.revealed[0];
  assert.strictEqual(range.start.line, 0);
  // 0.5 * text.length = 5. Deliberately asymmetric to getVisibleLine's
  // /(len+2) decode - this matches the built-in preview's scrolling.ts
  // (toRevealRange) exactly, verified against the VS Code source.
  assert.strictEqual(range.start.character, 5);
});

test('scrollEditorToLine clamps to the document end', () => {
  const doc = new MockDocument('a\nb');
  const editor = new MockEditor(doc);
  scrollEditorToLine(99.7, editor);
  assert.ok(editor.revealed[0].range.start.line <= 1);
});
