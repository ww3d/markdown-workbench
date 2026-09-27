// Line-level text helpers: end-of-line handling and the line-hash index. Pure,
// no vscode - requires the module directly, no mock.
const { test } = require('node:test');
const assert = require('node:assert');
const {
  splitLines,
  detectEol,
  normalizeEol,
  lineKey,
  buildLineIndex,
  lineStartOffsets,
} = require('../../src/clipboard-diff/lines');

// --- splitLines ---

test('splitLines handles CRLF, CR and LF within the same text', () => {
  assert.deepStrictEqual(splitLines('a\r\nb\rc\nd'), ['a', 'b', 'c', 'd']);
});

test('splitLines (Gegenprobe) a single line with no break stays one element', () => {
  assert.deepStrictEqual(splitLines('one line'), ['one line']);
});

// --- detectEol ---

test('detectEol picks CRLF when the first break is one', () => {
  assert.strictEqual(detectEol('a\r\nb\nc'), '\r\n');
});

test('detectEol falls back to LF for a plain LF text or no breaks at all', () => {
  assert.strictEqual(detectEol('a\nb\r\nc'), '\n');
  assert.strictEqual(detectEol('no breaks'), '\n');
});

// --- normalizeEol ---

test('normalizeEol rewrites every break kind to the target', () => {
  assert.strictEqual(normalizeEol('a\r\nb\rc\nd', '\n'), 'a\nb\nc\nd');
});

test('normalizeEol (Gegenprobe) leaves a text already using the target unchanged', () => {
  assert.strictEqual(normalizeEol('a\nb\nc', '\n'), 'a\nb\nc');
});

// --- lineKey ---

test('lineKey trims both ends', () => {
  assert.strictEqual(lineKey('  hi  '), 'hi');
});

test('lineKey (Gegenprobe) a whitespace-only line keys to empty, not to itself', () => {
  assert.strictEqual(lineKey('   '), '');
  assert.notStrictEqual(lineKey('   '), '   ');
});

// --- buildLineIndex ---

test('buildLineIndex keeps positions of a repeated key in ascending order', () => {
  const index = buildLineIndex(['x', 'y', 'x', '', 'x']);
  assert.deepStrictEqual(index.get('x'), [0, 2, 4]);
  assert.deepStrictEqual(index.get('y'), [1]);
});

test('buildLineIndex (Gegenprobe) blank lines never anchor: no entry under the empty key', () => {
  const index = buildLineIndex(['', '  ', 'content']);
  assert.strictEqual(index.has(''), false);
  assert.strictEqual(index.size, 1);
});

// --- lineStartOffsets ---

test('lineStartOffsets accounts for CRLF and LF line widths', () => {
  assert.deepStrictEqual(lineStartOffsets('ab\r\ncd\nef'), [0, 4, 7]);
});

test('lineStartOffsets (Gegenprobe) a text with no breaks has only the start of line 0', () => {
  assert.deepStrictEqual(lineStartOffsets('single'), [0]);
});
