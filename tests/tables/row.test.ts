// Row splitting of the table model (REQ-001, REQ-002) and the delimiter row.

import { test } from 'node:test';
import assert from 'node:assert';
import {
  splitRow,
  parseRow,
  parseSeparator,
  prefixLength,
  cellIndexAt,
} from '../../src/tables/row.ts';
import { nth } from '../helpers/nth.ts';

const texts = (line: string) => parseRow(line).cells.map((c) => c.text);

test('an escaped pipe stays cell content and does not split (REQ-001)', () => {
  assert.deepStrictEqual(texts('| a \\| b | c |'), ['a \\| b', 'c']);
});

test('an unescaped pipe inside a code span splits like markdown-it (REQ-002)', () => {
  assert.deepStrictEqual(texts('| `x|y` | z |'), ['`x', 'y`', 'z']);
});

test('border pipes are not cells; borderless rows split the same', () => {
  const bordered = parseRow('| a | b |');
  assert.strictEqual(bordered.lead, true);
  assert.strictEqual(bordered.trail, true);
  const bare = parseRow('a | b');
  assert.strictEqual(bare.lead, false);
  assert.strictEqual(bare.trail, false);
  assert.deepStrictEqual(texts('a | b'), ['a', 'b']);
});

test('an escaped trailing pipe is content, not a border', () => {
  const r = parseRow('| a | b \\|');
  assert.strictEqual(r.trail, false);
  assert.deepStrictEqual(texts('| a | b \\|'), ['a', 'b \\|']);
});

test('cell offsets are absolute and exclude the padding', () => {
  const line = '> |  ab | c |';
  const first = nth(splitRow(line, prefixLength(line)).cells, 0);
  assert.strictEqual(line.slice(first.cStart, first.cEnd), 'ab');
  assert.strictEqual(first.start, 3, 'right after the pipe');
  assert.strictEqual(first.end, 8, 'at the next pipe');
});

test('Unicode whitespace at an inner cell edge is padding, not content', () => {
  const line = '| a\u3000|\u00a0b\u2003| c |';
  const { cells } = parseRow(line);
  assert.deepStrictEqual(
    cells.map((c) => c.text),
    ['a', 'b', 'c'],
  );
  assert.deepStrictEqual(
    cells.map((c) => line.slice(c.cStart, c.cEnd)),
    ['a', 'b', 'c'],
    'the content range excludes the whitespace',
  );
  assert.strictEqual(
    nth(cells, 0).end - nth(cells, 0).start,
    3,
    'the segment keeps it',
  );
});

test('the prefix covers indentation and nested blockquote markers', () => {
  assert.strictEqual(prefixLength('  > > | a |'), 6);
  assert.strictEqual(prefixLength('| a |'), 0);
  assert.strictEqual(prefixLength('    | a |'), 4);
});

test('delimiter rows parse with alignments; lookalikes do not', () => {
  assert.deepStrictEqual(parseSeparator('| :-- | :-: | --: | --- |', 0), [
    'left',
    'center',
    'right',
    '',
  ]);
  assert.deepStrictEqual(parseSeparator('---|---', 0), ['', '']);
  assert.strictEqual(parseSeparator('- -', 0), null, 'a list item');
  assert.strictEqual(parseSeparator('| a | --- |', 0), null);
  assert.strictEqual(parseSeparator('|  | --- |', 0), null, 'empty inner cell');
  assert.strictEqual(parseSeparator('-', 0), null);
});

test('cellIndexAt maps a column to its cell, -1 before the first pipe', () => {
  const row = parseRow('  | ab | cd |');
  assert.strictEqual(cellIndexAt(row, 0), -1);
  assert.strictEqual(cellIndexAt(row, 2), -1);
  assert.strictEqual(cellIndexAt(row, 3), 0);
  assert.strictEqual(
    cellIndexAt(row, 7),
    0,
    'the pipe belongs to the left cell',
  );
  assert.strictEqual(cellIndexAt(row, 8), 1);
  assert.strictEqual(cellIndexAt(row, 99), 1);
  const bare = parseRow('ab | cd');
  assert.strictEqual(cellIndexAt(bare, 0), 0);
  assert.strictEqual(cellIndexAt(parseRow('|'), 1), -1, 'no cells');
});
