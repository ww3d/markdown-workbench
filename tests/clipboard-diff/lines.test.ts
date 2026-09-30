// Line-level text helpers: end-of-line handling and the line-hash index. Pure,
// no vscode - requires the module directly, no mock.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  splitLines,
  normalizeEol,
  lineKey,
  buildLineIndex,
  commonAffixes,
} from '../../src/clipboard-diff/lines.ts';

// --- splitLines ---

test('splitLines handles CRLF, CR and LF within the same text', () => {
  assert.deepStrictEqual(splitLines('a\r\nb\rc\nd'), ['a', 'b', 'c', 'd']);
});

test('splitLines (counter-check) a single line with no break stays one element', () => {
  assert.deepStrictEqual(splitLines('one line'), ['one line']);
});

// --- normalizeEol ---

test('normalizeEol rewrites every break kind to the target', () => {
  assert.strictEqual(normalizeEol('a\r\nb\rc\nd', '\n'), 'a\nb\nc\nd');
});

test('normalizeEol (counter-check) leaves a text already using the target unchanged', () => {
  assert.strictEqual(normalizeEol('a\nb\nc', '\n'), 'a\nb\nc');
});

// --- lineKey ---

test('lineKey trims both ends', () => {
  assert.strictEqual(lineKey('  hi  '), 'hi');
});

test('lineKey (counter-check) a whitespace-only line keys to empty, not to itself', () => {
  assert.strictEqual(lineKey('   '), '');
  assert.notStrictEqual(lineKey('   '), '   ');
});

// --- buildLineIndex ---

test('buildLineIndex keeps positions of a repeated key in ascending order', () => {
  const index = buildLineIndex(['x', 'y', 'x', '', 'x']);
  assert.deepStrictEqual(index.get('x'), [0, 2, 4]);
  assert.deepStrictEqual(index.get('y'), [1]);
});

test('buildLineIndex (counter-check) blank lines never anchor: no entry under the empty key', () => {
  const index = buildLineIndex(['', '  ', 'content']);
  assert.strictEqual(index.has(''), false);
  assert.strictEqual(index.size, 1);
});

// --- commonAffixes ---

test('commonAffixes finds the shared start and end around one change', () => {
  assert.deepStrictEqual(commonAffixes('one two three', 'one TWO three'), {
    prefix: 4,
    suffix: 6,
  });
});

test('commonAffixes never lets the suffix overlap the prefix', () => {
  assert.deepStrictEqual(commonAffixes('aaa', 'aaaa'), {
    prefix: 3,
    suffix: 0,
  });
  assert.deepStrictEqual(commonAffixes('', 'x'), { prefix: 0, suffix: 0 });
});

test('commonAffixes (counter-check) identical texts share everything as prefix', () => {
  assert.deepStrictEqual(commonAffixes('same', 'same'), {
    prefix: 4,
    suffix: 0,
  });
});
