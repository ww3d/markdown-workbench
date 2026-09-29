// Table detection (REQ-003, REQ-004, REQ-005, E10), checked against the preview's
// own parser: markdown-it must find the same tables with the same cells.

import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh } from '../helpers/vscode-mock.ts';

// The preview's own markdown-it instance (html, linkify, front matter), loaded
// first, so the model below reads the very same instance.
install();
const { md } = (await loadFresh('src/render/index.ts'))._internal;
const { findTable, pipeHeaderAt, scanTables, linesDoc, inTableAt, carrySpan } =
  await import('../../src/tables/detect.js');

const doc = (text) => linesDoc(text.split('\n'));

test('the model and the preview share one markdown-it instance', async () => {
  assert.strictEqual(md, (await import('../../src/render/parser.ts')).md);
  // The model under test is the one loaded after the preview instance.
  const loaded = await import('../../src/tables/detect.js');
  assert.strictEqual(loaded.findTable, findTable);
});

// The tables the preview renders: start/end line and every row's cell texts.
function previewTables(text) {
  const tokens = md.parse(text, {});
  const out = [];
  let cur = null,
    row = null;
  for (const t of tokens) {
    if (t.type === 'table_open')
      cur = { start: t.map[0], end: t.map[1] - 1, rows: [] };
    else if (t.type === 'tr_open') row = [];
    else if (t.type === 'inline' && row) row.push(t.content);
    else if (t.type === 'tr_close') {
      cur.rows.push(row);
      row = null;
    } else if (t.type === 'table_close') out.push(cur);
  }
  return out;
}

// Ours in the same shape (delimiter row dropped, rows padded to the header like
// markdown-it pads them, escapes resolved like its escapedSplit).
function modelTables(text) {
  return scanTables(doc(text)).map((t) => ({
    start: t.start,
    end: t.end,
    rows: t.rows
      .filter((_, i) => i !== 1)
      .map((r) =>
        Array.from({ length: t.columnCount }, (_, i) =>
          (r.cells[i]?.text ?? '').replace(/\\\|/g, '|'),
        ),
      ),
  }));
}

const CORPUS = [
  '| a | b |\n|---|---|\n| 1 | 2 |',
  'a | b\n--|--\n1 | 2\ntext below joins',
  'para\n| a | b |\n| - | :-: |\n| 1 |\n| 1 | 2 | 3 |\n\nafter',
  '- item\n\n  | a | b |\n  |---|---|\n  | 1 | 2 |',
  '> | q | r |\n> | - | - |\n> | 1 | 2 |\n\n| x |\n|---|\n| y |',
  '| a \\| b | `c|d` |\n|---|---|---|\n| 1 | 2 | 3 |',
  '| a | b |\n|---|---|\n| 1 | 2 |\n# heading\n| c | d |\n| - | - |',
  '| a | b |\n|---|---|\n- list ends it',
  '```\n| a | b |\n|---|---|\n```\n| a |\n|---|',
  '---\ntitle: x\n---\n| a | b |\n|---|---|',
  '    | a | b |\n    |---|---|\n',
  '| a | b |\n|---|\n| 1 | 2 |',
  // Whitespace the preview trims like String.prototype.trim (R2-3).
  '\u00a0| a | b |\n|---|---|\n| 1 | 2 |',
  '| a | b |\u00a0\n|---|---|\n| 1 | 2 |\u3000',
  '| a\u3000| \u00a0b |\n|---|---|',
];

test('the model finds the same tables and cells as the preview (REQ-003)', () => {
  for (const text of CORPUS)
    assert.deepStrictEqual(modelTables(text), previewTables(text), text);
});

// Container edge cases, each against the preview's parser: header on a list
// marker's line, lazy quote and list lines, fences in list items, `>` as cell
// content at the outer level (docs/DECISIONS.md #49).
const CONTAINERS = [
  '- | a | b |\n  |---|---|\n  | 1 | 2 |',
  '- | a | b |\n|---|---|\n| 1 | 2 |',
  '- item\n  | a | b |\n  |---|---|',
  '- item\n| a | b |\n  |---|---|\n| 1 | 2 |',
  '- item\na | b\n--|--',
  '- item\ntext\n  | a | b |\n  |---|---|\n| a | b |\n|---|---|',
  '- item\n  # h\n| a | b |\n|---|---|',
  '- | a | b |\n\t|---|---|\n| a |\n| - | - |\n| - | - |',
  '1. x\n--- | ---\n\t|---|---|\n\t|---|---|\n:-: | --:',
  '> para\n| a | b |\n|---|---|',
  '> | a | b |\n|---|---|\n| 1 | 2 |',
  '> x\n\n| a | b |\n|---|---|',
  '> x | y\n--- | ---',
  '>\n> x | y\n--- | ---',
  '> a\nb\n> x | y\n--- | ---',
  '- item\n\n    ```\n    code\n\n| a | b |\n|---|---|',
  '- | a | b |\n>\n  |---|---|\n| - | - |',
  '- | a | b |\n| `a|b` | c |\n\t|---|---|\n>\n\t|---|---|\n  |---|---|',
  '> | a | b |\n  | a | b |\n- | a | b |\n--- | ---\n>\n  |---|---|\n| - | - |',
  'a | b\n| `a|b` | c |\n- | a | b |\n>\n> x | y\n--- | ---',
  // Review round 1 on #91, point 3.
  '- x\n  - | a | b |\n  |---|---|---|',
  '- x\n  - a | b\n    --|--',
  '- item\n- a | b\n  --|--\n  1 | 2',
  '- item\n\n  para\n| a | b |\n|---|---|',
  'text\n2. | a | b |\n   |---|---|',
  'text\n10. x\n| a | b |\n|---|---|',
  '> h\n> -\n> a \\| b\n> ---',
  '>\t| a | b |\n>\t|---|---|\n>\t| 1 | 2 |',
  '>    | a | b |\n>    |---|---|',
  '> \t| a |\n> \t|---|',
  '>| a | b\n>| --- | --- |\n>| \n>    code',
  '- > | a | b |\n  > |---|---|\n  > | 1 | 2 |',
  '<div>\n\n- > |a|b|\n  > | :- | -: |\n  > | - | - |',
  '> - x\n| a | b |\n|---|---|',
  '> ```\n> x\n| a | b |\n|---|---|\n| 1 | 2 |',
  '> | a | b |\n> |---|---|\n| x | y |\n|---|---|',
  '> > | a | b |\n> > |---|---|\n> | x | y |\n> |---|---|',
  '-    | a | b |\n     |---|---|\n     | 1 | 2 |',
  '- item\n> a | b\n--|--',
  // Point 5: indented code before `>` and in a list item.
  '    > | a | b |\n    > |---|---|\n    > | 1 | 2 |',
];

// HTML blocks as the preview parses them (`html: true`), point 4.
const HTML = [
  '<div>\n| a | b |\n|---|---|\n</div>',
  '<!--\n| a | b |\n|---|---|\n-->',
  ...[
    '<textarea>',
    '<ADDRESS>',
    '<?php x ?>',
    '<!DOCTYPE html>',
    '<![CDATA[x]]>',
  ].map((tag) => `| a | b |\n|---|---|\n| 1 | 2 |\n${tag}\n| 3 | 4 |`),
  '| a | b |\n|---|---|\n<span>x</span>',
];

test('HTML blocks hold no table and end one like in the preview (REQ-003)', () => {
  for (const text of HTML)
    assert.deepStrictEqual(modelTables(text), previewTables(text), text);
});

test('lists, lazy lines and quotes yield the preview tables (REQ-003)', () => {
  for (const text of CONTAINERS)
    assert.deepStrictEqual(modelTables(text), previewTables(text), text);
});

test('a table is found from any of its lines, not from outside it', () => {
  const d = doc('before\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nafter');
  for (const line of [2, 3, 4])
    assert.strictEqual(findTable(d, line)?.start, 2);
  for (const line of [0, 1, 5, 6]) assert.strictEqual(findTable(d, line), null);
});

test('rows behind a prefix carry it verbatim (REQ-004)', () => {
  const d = doc('- item\n\n  > | a | b |\n  > |---|---|\n  > | 1 | 2 |');
  const t = findTable(d, 4);
  assert.deepStrictEqual(
    t.rows.map((r) => r.prefix),
    ['  > ', '  > ', '  > '],
  );
});

test('a quote-depth change ends the table', () => {
  const d = doc('> | a |\n> |---|\n> | 1 |\n| 2 |');
  assert.strictEqual(findTable(d, 0).end, 2);
  assert.strictEqual(findTable(d, 3), null);
});

test('no table inside a fence or the frontmatter (E10)', () => {
  const d = doc('---\n| a | b |\n|---|---|\n---\n~~~\n| a |\n|---|\n~~~');
  for (let l = 0; l < d.lineCount; l++)
    assert.strictEqual(findTable(d, l), null);
  assert.strictEqual(pipeHeaderAt(d, 5), null);
});

test('a line starting with | and no delimiter row is a typed header (REQ-005)', () => {
  const d = doc('> | Name | Age\ntext');
  const head = pipeHeaderAt(d, 0);
  assert.strictEqual(head.prefix, '> ');
  assert.deepStrictEqual(
    head.cells.map((c) => c.text),
    ['Name', 'Age'],
  );
  assert.strictEqual(
    pipeHeaderAt(doc('Name | Age'), 0),
    null,
    'no leading pipe',
  );
  assert.strictEqual(
    pipeHeaderAt(doc('| a | b |\n|---|---|'), 0),
    null,
    'already a table',
  );
  assert.strictEqual(
    pipeHeaderAt(doc('| a | b |\n|---|'), 0),
    null,
    'delimiter below',
  );
  for (const item of ['- |---|---|', '1. |---|---|'])
    assert.ok(
      pipeHeaderAt(doc(`| a | b\n${item}`), 0),
      `${item}: a list item below is another block, not a delimiter row`,
    );
});

test('a body row that looks like a delimiter row stays a body row (top-down scan)', () => {
  const d = doc(
    '| Name | Val |\n|------|-----|\n| a | 1 |\n| - | - |\n| b | 2 |',
  );
  for (const line of [2, 3, 4])
    assert.strictEqual(findTable(d, line)?.start, 0, `line ${line}`);
  assert.deepStrictEqual(
    modelTables('a | b\n| - | - |\n--- | ---'),
    previewTables('a | b\n| - | - |\n--- | ---'),
  );
});

test('an indented code block is never a typed header (E10)', () => {
  assert.strictEqual(pipeHeaderAt(doc('Some text\n\n    | a | b |'), 2), null);
  assert.ok(
    pipeHeaderAt(doc('- item\n\n    | a | b |'), 2),
    'inside a list item it is',
  );
  for (const [text, line] of [
    ['- x\n\n      | Name', 2],
    ['> - x\n>\n>       | Name', 2],
    ['    > | Name', 0],
    ['<div>\n| Name', 1],
  ])
    assert.strictEqual(pipeHeaderAt(doc(text), line), null, text);
});

test('a typed header on a list item carries the marker in its prefix', () => {
  const head = pipeHeaderAt(doc('1. | a | b'), 0);
  assert.strictEqual(head.prefix, '1. ');
  assert.deepStrictEqual(
    head.cells.map((c) => c.text),
    ['a', 'b'],
  );
});

test('a fence ends with its blockquote; a 4-space fence line is indented code', () => {
  const quoted = '> ```\n> code\n\n| a | b |\n|---|---|\n| 1 | 2 |';
  assert.strictEqual(findTable(doc(quoted), 5)?.start, 3);
  assert.deepStrictEqual(modelTables(quoted), previewTables(quoted));
  const indented = 'text\n\n    ```\n\n| a | b |\n|---|---|\n| 1 | 2 |';
  assert.strictEqual(findTable(doc(indented), 6)?.start, 4);
  assert.deepStrictEqual(modelTables(indented), previewTables(indented));
});

// A versioned document that counts line reads (a block parse reads them all).
function countingDoc(lines) {
  const d = { lineCount: lines.length, version: 1, reads: 0 };
  d.lineAt = (n) => {
    d.reads++;
    return { text: lines[n] };
  };
  return d;
}

test('the diagnostics scan keeps the cursor table cached (R2-4)', () => {
  const lines = [
    '| a |',
    '|---|',
    '| 1 |',
    '| 2 |',
    '',
    '| b |',
    '|---|',
    '| 3 |',
  ];
  const d = countingDoc(lines);
  assert.strictEqual(inTableAt(d, 2), true);
  scanTables(d);
  lines[2] = '| 1x |';
  d.version = 2;
  carrySpan(d, [
    {
      range: { start: { line: 2, character: 3 }, end: { line: 2 } },
      text: 'x',
    },
  ]);
  d.reads = 0;
  assert.strictEqual(inTableAt(d, 2), true);
  assert.strictEqual(d.reads, 0, 'answered from the cached span');
});

test('a borderless body row carries no span: an edit may start a block (R3-5)', () => {
  const lines = ['a | b', '--|--', 'c | d', 'e | f'];
  const d = countingDoc(lines);
  assert.strictEqual(inTableAt(d, 2), true);
  lines[2] = '# c | d';
  d.version = 2;
  carrySpan(d, [
    {
      range: { start: { line: 2, character: 0 }, end: { line: 2 } },
      text: '# ',
    },
  ]);
  assert.strictEqual(inTableAt(d, 2), false, 'the heading ends the table');
});

test('the table span is carried over typing in a body cell, dropped otherwise', () => {
  const lines = ['| a |', '|---|'];
  for (let i = 0; i < 2000; i++) lines.push(`| ${i} |`);
  let reads = 0;
  const d = {
    lineCount: lines.length,
    version: 1,
    lineAt: (n) => {
      reads++;
      return { text: lines[n] };
    },
  };
  assert.strictEqual(inTableAt(d, 1500), true);
  lines[1500] = '| 1500x |';
  d.version = 2;
  reads = 0;
  carrySpan(d, [
    {
      range: { start: { line: 1500, character: 6 }, end: { line: 1500 } },
      text: 'x',
    },
  ]);
  assert.strictEqual(inTableAt(d, 1500), true);
  assert.ok(reads < 5, `cached: ${reads} line reads`);
  d.version = 3;
  carrySpan(d, [
    {
      range: { start: { line: 1500, character: 0 }, end: { line: 1500 } },
      text: '# ',
    },
  ]);
  lines[1500] = '# | 1500x |';
  reads = 0;
  assert.strictEqual(
    inTableAt(d, 1500),
    false,
    'an edit before the pipe re-reads',
  );
  assert.ok(reads > 100, 're-parsed');
  lines[1500] = '| 1500x |';
  d.version = 4;
  assert.strictEqual(inTableAt(d, 1500), true);
  lines.splice(1000, 0, '');
  d.lineCount = lines.length;
  d.version = 5;
  carrySpan(d, [
    {
      range: { start: { line: 1000, character: 0 }, end: { line: 1000 } },
      text: '\n',
    },
  ]);
  assert.strictEqual(inTableAt(d, 1500), false, 'a blank line split the table');
  const small = ['| a |', '|---|', '| 1 |', '| 2 |'];
  const d2 = { ...linesDoc(small), version: 1 };
  assert.strictEqual(inTableAt(d2, 2), true);
  small.splice(3, 0, '# x');
  d2.lineCount = small.length;
  d2.version = 2;
  carrySpan(d2, [
    {
      range: { start: { line: 2, character: 4 }, end: { line: 2 } },
      text: '\n# x',
    },
  ]);
  assert.strictEqual(
    inTableAt(d2, 3),
    false,
    'a change with a line break drops the span',
  );
});

test('a body row indented 4+ columns past the header ends the table', () => {
  const text = '| a | b |\n|---|---|\n| 1 | 2 |\n    | 3 | 4 |';
  assert.strictEqual(findTable(doc(text), 0).end, 2);
  assert.deepStrictEqual(modelTables(text), previewTables(text));
});

test('rows are measured against the block indent, not the header indent', () => {
  const code = '  | a | b |\n  |---|---|\n    | c | d |';
  assert.strictEqual(
    findTable(doc(code), 0).end,
    1,
    'a 4-space row is indented code',
  );
  assert.deepStrictEqual(modelTables(code), previewTables(code));
  const tabbed = '  | a | b |\n\t|---|---|';
  assert.strictEqual(
    findTable(doc(tabbed), 0),
    null,
    'a tab-indented delimiter is code',
  );
  assert.deepStrictEqual(modelTables(tabbed), previewTables(tabbed));
});

// Differential check against the preview: random documents from lines that
// stress containers, code, HTML and table shapes; fixed seeds, so a failure
// reproduces. Tables and cells must match exactly.
const POOL = [
  '| a | b |',
  '|---|---|',
  '| - | - |',
  'a | b',
  '--- | ---',
  '',
  '',
  '> | a | b |',
  '> |---|---|',
  '> x | y',
  '  | a | b |',
  '    | a | b |',
  '- item',
  '- | a | b |',
  '  |---|---|',
  'text',
  '```',
  '# h',
  '| a |',
  '|---|',
  '| `a|b` | c |',
  ':-: | --:',
  '***',
  '1. x',
  '|-|-|-|',
  '>',
  '\t|---|---|',
  '  - x',
  '  - | a | b |',
  '    |---|---|',
  '2. x',
  '10. x',
  '2. | a | b |',
  '>\t| a | b |',
  '>     | a | b |',
  '- > | a | b |',
  '- > |---|---|',
  '> - x',
  '> - | a | b |',
  '>   |---|---|',
  '<div>',
  '</div>',
  '<!-- c',
  '-->',
  '<textarea>',
  '</textarea>',
  '<ADDRESS>',
  '<?x',
  '?>',
  '<!DOCTYPE html>',
  '<![CDATA[',
  ']]>',
  '    > | a | b |',
  '      | Name',
  '<span>',
  '  > | a | b |',
  '---',
  'title: x',
  '| a \\| b |',
  '| a | b | ',
  ' | a | b |',
  '| 1　| 2 |',
  '|---|---| ',
];

function randomDoc(rand) {
  const n = 2 + Math.floor(rand() * 7);
  const lines = Array.from(
    { length: n },
    () => POOL[Math.floor(rand() * POOL.length)],
  );
  return (rand() < 0.5 ? ['x', ''] : []).concat(lines).join('\n');
}

test('random documents yield the preview tables (REQ-003, seeds 1-3)', () => {
  for (const seed of [1, 2, 3]) {
    let a = seed;
    const rand = () => {
      a = (a * 1103515245 + 12345) & 0x7fffffff;
      return a / 0x7fffffff;
    };
    for (let i = 0; i < 3000; i++) {
      const text = randomDoc(rand);
      assert.deepStrictEqual(
        modelTables(text),
        previewTables(text),
        `${seed}/${i}: ${JSON.stringify(text)}`,
      );
    }
  }
});
