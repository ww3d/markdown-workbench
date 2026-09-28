// Table detection (REQ-003, REQ-004, REQ-005, E10), checked against the preview's
// own parser: markdown-it must find the same tables with the same cells.

const { test } = require('node:test');
const assert = require('node:assert');
const MarkdownIt = require('markdown-it');
const {
  findTable,
  pipeHeaderAt,
  scanTables,
  linesDoc,
} = require('../../src/tables/detect.js');

const doc = (text) => linesDoc(text.split('\n'));

// The tables markdown-it renders: start/end line and every row's cell texts.
function previewTables(text) {
  const tokens = new MarkdownIt().parse(text, {});
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
];

test('the model finds the same tables and cells as the preview (REQ-003)', () => {
  for (const text of CORPUS)
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
});

test('the code mask is cached per document version', () => {
  const lines = ['```', '| a |', '|---|', '```', '| b |', '|---|'];
  const d = { ...linesDoc(lines), version: 1 };
  assert.strictEqual(findTable(d, 4)?.start, 4);
  lines[3] = 'still code';
  assert.strictEqual(findTable(d, 4)?.start, 4, 'same version: cached mask');
  d.version = 2;
  assert.strictEqual(findTable(d, 4), null, 'new version: fence now unclosed');
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
});

test('a fence ends with its blockquote; a 4-space fence line is indented code', () => {
  const quoted = '> ```\n> code\n\n| a | b |\n|---|---|\n| 1 | 2 |';
  assert.strictEqual(findTable(doc(quoted), 5)?.start, 3);
  assert.deepStrictEqual(modelTables(quoted), previewTables(quoted));
  const indented = 'text\n\n    ```\n\n| a | b |\n|---|---|\n| 1 | 2 |';
  assert.strictEqual(findTable(doc(indented), 6)?.start, 4);
  assert.deepStrictEqual(modelTables(indented), previewTables(indented));
});

test('the table span is carried over typing in a body cell, dropped otherwise', () => {
  const { inTableAt, carrySpan } = require('../../src/tables/detect.js');
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
    { range: { start: { line: 1500 }, end: { line: 1500 } }, text: 'x' },
  ]);
  assert.strictEqual(inTableAt(d, 1500), true);
  assert.ok(reads < 5, `cached: ${reads} line reads`);
  lines.splice(1000, 0, '');
  d.lineCount = lines.length;
  d.version = 3;
  carrySpan(d, [
    { range: { start: { line: 1000 }, end: { line: 1000 } }, text: '\n' },
  ]);
  assert.strictEqual(inTableAt(d, 1500), false, 'a blank line split the table');
});
