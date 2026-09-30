// Scroll sync math, ported from the built-in preview: fractional visible
// line and the character-offset encoding used to reveal fractional lines.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Range,
  Position,
} from '../helpers/vscode-mock.ts';
import { nth } from '../helpers/nth.ts';

/** The scroll helpers this suite drives with mock editors (not `vscode.TextEditor`). */
interface ScrollApi {
  _internal: {
    getVisibleLine(editor: MockEditor): number | undefined;
    scrollEditorToLine(line: number, editor: MockEditor): void;
  };
}

install();
const { _internal } = await loadFresh<ScrollApi>('src/views/index.ts');
const { getVisibleLine, scrollEditorToLine } = _internal;

test('getVisibleLine adds the character fraction of the top line', () => {
  const doc = new MockDocument('0123456789\nsecond');
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(0, 6), new Position(1, 0))];
  // line 0, char 6, length 10 -> 0 + 6/(10+2) = 0.5
  assert.ok(Math.abs((getVisibleLine(editor) ?? Number.NaN) - 0.5) < 1e-9);
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
  const { range } = nth(editor.revealed, 0);
  assert.strictEqual(range.start.line, 0);
  // 0.5 * text.length = 5. Deliberately asymmetric to getVisibleLine's
  // /(len+2) decode - the encoding follows the built-in preview's scrolling.ts
  // (toRevealRange), from which this scroll sync was ported (DECISIONS.md #5).
  assert.strictEqual(range.start.character, 5);
});

test('scrollEditorToLine clamps to the document end', () => {
  const doc = new MockDocument('a\nb');
  const editor = new MockEditor(doc);
  scrollEditorToLine(99.7, editor);
  assert.ok(nth(editor.revealed, 0).range.start.line <= 1);
});
