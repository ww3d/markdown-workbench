// The block structure read from the preview's parser (docs/DECISIONS.md #49, D1).

import { test } from 'node:test';
import assert from 'node:assert';
import { blocksOf } from '../../src/tables/blocks.js';
import { findTable, linesDoc } from '../../src/tables/detect.js';

test('table and paragraph lines carry where their content starts', () => {
  const { lines, tables } = blocksOf(
    linesDoc(['- | a | b', '', '> | x | y |', '> |---|---|', '>\t| 1 | 2 |']),
  );
  assert.deepStrictEqual(lines[0], { kind: 'paragraph', start: 0, at: 2 });
  assert.strictEqual(lines[1], undefined);
  assert.deepStrictEqual(
    [2, 3, 4].map((l) => [lines[l].kind, lines[l].start, lines[l].at]),
    [
      ['table', 2, 2],
      ['table', 2, 2],
      ['table', 2, 2],
    ],
  );
  assert.deepStrictEqual(tables, [2]);
});

test('code, HTML and frontmatter lines are marked', () => {
  const { code } = blocksOf(
    linesDoc([
      '---',
      'a: 1',
      '---',
      '```',
      'x',
      '```',
      '    y',
      '',
      '<div>',
      'z',
      '',
      'p',
    ]),
  );
  assert.deepStrictEqual([...code], [1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 0]);
});

test('the parse is cached per version; a new version with a changed structure is re-read', () => {
  const lines = ['| a | b |', '|---|---|', '| 1 | 2 |'];
  const d = { ...linesDoc(lines), version: 1 };
  assert.strictEqual(findTable(d, 2)?.start, 0);
  lines.splice(1, 1);
  d.lineCount = lines.length;
  assert.strictEqual(blocksOf(d).tables.length, 1, 'same version: cached');
  d.version = 2;
  assert.strictEqual(findTable(d, 1), null, 'delimiter row deleted: no table');
  assert.deepStrictEqual(blocksOf(d).tables, []);
});
