// Aligning (REQ-010 to REQ-013, REQ-022, REQ-032, REQ-039, REQ-043).

import { test } from 'node:test';
import assert from 'node:assert';
import { findTable, linesDoc } from '../../src/tables/detect.ts';
import type { Table } from '../../src/tables/detect.ts';
import { displayWidth } from '../../src/tables/width.ts';
import {
  toGrid,
  formatGrid,
  autoFormat,
  lineEdits,
} from '../../src/tables/format.ts';
import { nth } from '../helpers/nth.ts';

const MODES = ['distribute', 'consolidate'] as const;
type Mode = (typeof MODES)[number];

function tableOf(lines: string[]): Table {
  const t = findTable(linesDoc(lines), 0);
  assert.ok(t, `no table in ${JSON.stringify(lines)}`);
  return t;
}
const fmt = (lines: string[], mode: Mode) =>
  formatGrid(toGrid(tableOf(lines)), { mode }).lines;

test('distribute pads to the widest cell, consolidate uses single spaces (REQ-010)', () => {
  const src = ['|a|b \\| c|', '|-|:-:|', '|long|x|'];
  assert.deepStrictEqual(fmt(src, 'distribute'), [
    '| a    | b \\| c |',
    '| ---- | :----: |',
    '| long | x      |',
  ]);
  assert.deepStrictEqual(fmt(src, 'consolidate'), [
    '| a | b \\| c |',
    '| --- | :-: |',
    '| long | x |',
  ]);
});

test('a borderless table stays borderless (REQ-012)', () => {
  assert.deepStrictEqual(fmt(['a|bb', '-|-', 'ccc|d'], 'distribute'), [
    'a   | bb',
    '--- | ---',
    'ccc | d',
  ]);
});

test('alignment colons survive both modes (REQ-013, REQ-043)', () => {
  for (const mode of MODES)
    assert.strictEqual(
      nth(fmt(['| a | b | c |', '|:-|-:|:-:|'], mode), 1).replace(/-+/g, '-'),
      '| :- | -: | :-: |',
    );
});

test('short rows are filled, extra cells kept (REQ-032)', () => {
  assert.deepStrictEqual(
    fmt(['| a | b |', '|---|---|', '| 1 |', '| 1 | 2 | 3 |'], 'distribute'),
    ['| a   | b   |', '| --- | --- |', '| 1   |     |', '| 1   | 2   | 3 |'],
  );
});

test('a second pass changes nothing, also with an empty cell past a borderless header (T5)', () => {
  const src = ['| x | y', '|---|---', '| x | y | |'];
  for (const mode of MODES) {
    const once = fmt(src, mode);
    assert.deepStrictEqual(fmt(once, mode), once, mode);
  }
  assert.strictEqual(nth(fmt(src, 'distribute'), 2), '| x   | y');
});

test('trailing Unicode whitespace does not cost the border (R2-3)', () => {
  const out = fmt(
    ['| a | b |\u00a0', '|---|---|', '| 1 | 2 |\u3000'],
    'distribute',
  );
  assert.deepStrictEqual(out, [
    '| a   | b   |',
    '| --- | --- |',
    '| 1   | 2   |',
  ]);
});

test('Unicode whitespace at an inner cell edge is trimmed and becomes spaces', () => {
  const src = ['| a\u3000|\u00a0b |', '|---|---|', '| 1 |\u2003 2\u00a0|'];
  assert.deepStrictEqual(fmt(src, 'distribute'), [
    '| a   | b   |',
    '| --- | --- |',
    '| 1   | 2   |',
  ]);
  assert.deepStrictEqual(fmt(src, 'consolidate'), [
    '| a | b |',
    '| --- | --- |',
    '| 1 | 2 |',
  ]);
});

test('CJK and emoji align by display width', () => {
  assert.deepStrictEqual(
    fmt(['| 漢字 | 😀 |', '|---|---|', '| abcde | x |'], 'distribute'),
    ['| 漢字  | 😀  |', '| ----- | --- |', '| abcde | x   |'],
  );
});

test('prefixes stay byte-identical (REQ-004)', () => {
  const out = fmt(['  >\t|a|', '  >\t|-|', '  >\t|b|'], 'distribute');
  assert.ok(out.every((l) => l.startsWith('  >\t')));
});

// Deterministic generator (mulberry32) - the invariant test needs no library.
function rng(seed: number) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const ALPHABET = [
  'a',
  'Z',
  '1',
  '漢',
  '😀',
  '\\|',
  '`',
  '*',
  'é',
  '[x]',
  '-',
  ':',
];

function randomTable(rand: () => number) {
  const cols = 1 + Math.floor(rand() * 5);
  const rows = 1 + Math.floor(rand() * 5);
  const lead = rand() < 0.7 || cols === 1;
  const trail = rand() < 0.7 || !lead;
  const prefix = nth(['', '  ', '> ', '> > ', '   '], Math.floor(rand() * 5));
  const pad = () => ' '.repeat(Math.floor(rand() * 3));
  const cell = () => {
    let s = '';
    const len = Math.floor(rand() * 4) + (rand() < 0.2 ? 0 : 1);
    for (let i = 0; i < len; i++)
      s += nth(ALPHABET, Math.floor(rand() * ALPHABET.length));
    return s.startsWith('-') || s.startsWith(':') ? `x${s}` : s || 'e';
  };
  // A delimiter row may not start with "- " (a list item), so it gets no padding.
  const row = (cells: string[], p = pad) =>
    prefix +
    (lead ? `|${p()}` : '') +
    cells.map((c) => c + p()).join(`|${p()}`) +
    (trail ? '|' : '');
  const sep = Array.from({ length: cols }, () =>
    nth(['-', '---', ':-', '-:', ':-:'], Math.floor(rand() * 5)),
  );
  const lines = [row(Array.from({ length: cols }, cell)), row(sep, () => '')];
  for (let r = 0; r < rows; r++)
    lines.push(row(Array.from({ length: cols }, cell)));
  return lines;
}

test('aligning changes only spaces and delimiter dashes (REQ-011, seed 20260928)', () => {
  const rand = rng(20260928);
  const strip = (line: string, isSep: boolean) =>
    isSep ? line.replace(/[ -]/g, '') : line.replace(/ /g, '');
  for (let i = 0; i < 500; i++) {
    const src = randomTable(rand);
    const t = tableOf(src);
    assert.ok(t, `generated table ${i} is detected: ${JSON.stringify(src)}`);
    for (const mode of MODES) {
      const res = formatGrid(toGrid(t), { mode });
      const out = res.lines;
      if (mode === 'distribute')
        assert.deepStrictEqual(
          res.widths,
          out.map((l) => displayWidth(l)),
          `${i}: line widths`,
        );
      for (const [r, line] of out.entries())
        assert.strictEqual(
          strip(line, r === 1),
          strip(nth(src, r), r === 1),
          `${i}/${mode}/${r}`,
        );
      const cells = (tbl: Table) =>
        tbl.rows
          .filter((_, k) => k !== 1)
          .map((r) => r.cells.map((c) => c.text));
      assert.deepStrictEqual(
        cells(tableOf(out)),
        cells(t),
        'same cells after aligning',
      );
    }
  }
});

test('autoFormat consolidates above maxWidth, prefix included (REQ-039)', () => {
  const grid = toGrid(
    tableOf(['> | a | b |', '> |---|---|', `> | ${'x'.repeat(20)} | y |`]),
  );
  const wide = autoFormat(grid, { maxWidth: 0 }).lines;
  assert.strictEqual(wide[0], `> | a${' '.repeat(19)} | b   |`);
  assert.deepStrictEqual(
    autoFormat(grid, { maxWidth: nth(wide, 2).length }).lines,
    wide,
  );
  assert.deepStrictEqual(
    autoFormat(grid, { maxWidth: nth(wide, 2).length - 1 }).lines,
    formatGrid(grid, { mode: 'consolidate' }).lines,
  );
});

test('lineEdits replaces only the changed middle of changed lines (REQ-022)', () => {
  const src = ['| a | b |', '|---|---|', '| 1 | 2 |', '| long | x |'];
  const grid = toGrid(tableOf(src));
  const aligned = formatGrid(grid, { mode: 'distribute' }).lines;
  const ops = lineEdits((l) => nth(src, l), grid, aligned);
  assert.deepStrictEqual(
    ops.map((o) => o.line),
    [0, 1, 2, 3],
  );
  for (const o of ops)
    assert.ok(
      o.start > 0 && o.end - o.start < nth(src, o.line).length,
      'never the whole line',
    );
  const applied = src.map((t, l) => {
    const o = ops.find((x) => x.line === l);
    return o ? t.slice(0, o.start) + o.text + t.slice(o.end) : t;
  });
  assert.deepStrictEqual(applied, aligned);
  assert.deepStrictEqual(
    lineEdits((l) => nth(aligned, l), grid, aligned),
    [],
    'aligned: no edit',
  );
});

test('lineEdits carries inserted rows on the row above', () => {
  const src = ['| a |', '|---|', '| 1 |'];
  const grid = toGrid(tableOf(src));
  grid.rows.push({ prefix: '', cells: [''] });
  const ops = lineEdits(
    (l) => nth(src, l),
    grid,
    formatGrid(grid, { mode: 'distribute' }).lines,
  );
  assert.strictEqual(ops.filter((o) => o.text.includes('\n')).length, 1);
  const applied = src.slice();
  for (const o of ops)
    applied[o.line] =
      nth(applied, o.line).slice(0, o.start) +
      o.text +
      nth(applied, o.line).slice(o.end);
  assert.deepStrictEqual(applied.join('\n').split('\n'), [
    '| a   |',
    '| --- |',
    '| 1   |',
    '|     |',
  ]);
});

test('borderless rows whose first cell starts a block keep a leading pipe', () => {
  for (const first of ['>', '```', '<div>']) {
    const src = ['Op | M', '-- | --', `| ${first} | x`, 'y | z'];
    const out = fmt(src, 'distribute');
    assert.ok(nth(out, 2).startsWith('| '), `${first}: ${out[2]}`);
    assert.strictEqual(tableOf(out).end, 3, `${first}: row stays in the table`);
  }
  assert.strictEqual(
    nth(fmt(['a | b', '--|--', '*|x'], 'distribute'), 2),
    '*| x',
    'glued, no list item',
  );
});

test('a borderless row that gets a leading pipe keeps its columns aligned', () => {
  const out = fmt(
    ['Op | Meaning', '-- | --', '| > | x', 'yyyyy | z'],
    'distribute',
  );
  assert.strictEqual(nth(out, 2).indexOf('| x'), nth(out, 3).indexOf('| z'));
});

test('distribute reports each line display width as measured on the line', () => {
  for (const src of [
    ['| 漢字 | 😀 |', '|---|:-:|', '| abcde | x | extra 漢 |'],
    ['  > a|b', '  > -|-', '  > *|é'],
    ['a | b', '--|--', '| x'],
  ]) {
    const out = formatGrid(toGrid(tableOf(src)), { mode: 'distribute' });
    assert.deepStrictEqual(
      out.widths,
      out.lines.map((l) => displayWidth(l)),
      JSON.stringify(src),
    );
  }
});
