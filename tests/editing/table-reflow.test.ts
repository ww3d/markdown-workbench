// Tables: pure reflow helpers plus the distribute/consolidate commands.

import { test } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} from '../helpers/vscode-mock.ts';
import type { MockContext } from '../helpers/vscode-mock.ts';
import { nth } from '../helpers/nth.ts';
import { parseRow } from '../../src/tables/row.ts';

// The editing entry point with the mock context in place of a vscode.ExtensionContext.
type Editing = Pick<
  typeof import('../../src/editing/index.ts'),
  'reflowTable'
> & {
  registerEditingCommands(context: MockContext, shikiLangs: string[]): void;
};

const vscode = install();
const editing = await loadFresh<Editing>('src/editing/index.ts');
const { reflowTable } = editing;

// Cell texts of one table row, split like the preview (an escaped `\|` stays content).
function cellTexts(line: string) {
  return parseRow(line).cells.map((c) => c.text);
}

function editorOn(
  text: string,
  line: number,
  character: number,
  endLine?: number,
  endCharacter?: number,
) {
  const doc = new MockDocument(text);
  const sel =
    endLine === undefined || endCharacter === undefined
      ? new Selection(line, character, line, character)
      : new Selection(line, character, endLine, endCharacter);
  const editor = new MockEditor(doc, sel);
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}

test('reflowTable distribute pads to column widths and keeps alignment colons', () => {
  const out = reflowTable(
    ['| App | On |', '|:---|---:|', '| git | yes |', '| q | n |'],
    'distribute',
  );
  assert.strictEqual(out[2], '| git | yes |');
  assert.strictEqual(out[3], '| q   | n   |');
  assert.match(nth(out, 1), /^\| :-+ \| -+: \|$/);
});

test('reflowTable consolidate shrinks separators to minimum width', () => {
  const out = reflowTable(
    ['| Long header | x |', '|---|---|', '| a | b |'],
    'consolidate',
  );
  assert.strictEqual(out[1], '| --- | --- |');
  assert.strictEqual(out[2], '| a | b |');
});

test('reflowTable pads ragged rows to the header width', () => {
  const out = reflowTable(['| a | b |', '|---|---|', '| only |'], 'distribute');
  for (const line of out)
    assert.strictEqual((line.match(/\|/g) || []).length, 3);
});

const ctx: MockContext = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id: string) => defined(vscode._commands?.[id], `command ${id}`)();

test('distributeTable expands around the cursor to the whole table', async () => {
  const editor = editorOn(
    'text\n| a | bbbb |\n|---|---|\n| c | d |\n\nafter',
    2,
    1,
  );
  await run('markdownWorkbench.distributeTable');
  assert.strictEqual(editor.document.lines[1], '| a   | bbbb |');
  assert.strictEqual(editor.document.lines[3], '| c   | d    |');
  assert.strictEqual(editor.document.lines[0], 'text');
  assert.strictEqual(editor.document.lines[5], 'after');
});

test('distributeTable outside a table informs instead of editing', async () => {
  editorOn('plain text', 0, 2);
  vscode._infos = [];
  await run('markdownWorkbench.distributeTable');
  assert.strictEqual(vscode._infos.length, 1);
});

test('consolidateTable shrinks padding', async () => {
  const editor = editorOn(
    '| aaa   | b     |\n|-------|-------|\n| c     | d     |',
    0,
    1,
  );
  await run('markdownWorkbench.consolidateTable');
  assert.strictEqual(editor.document.lines[2], '| c | d |');
});

test('an escaped pipe stays one cell through distribute and consolidate (REQ-010)', () => {
  for (const mode of ['distribute', 'consolidate'] as const) {
    const out = reflowTable(
      ['| a \\| b | c |', '|---|---|', '| x | y |'],
      mode,
    );
    assert.deepStrictEqual(cellTexts(nth(out, 0)), ['a \\| b', 'c']);
  }
});

test('reflowTable leaves non-table input and lines after the table alone', () => {
  assert.deepStrictEqual(reflowTable(['| a |', 'text'], 'distribute'), [
    '| a |',
    'text',
  ]);
  assert.deepStrictEqual(
    reflowTable(['| a |', '|---|', '', 'after'], 'distribute').slice(2),
    ['', 'after'],
  );
});

test('the reflow commands ignore tables.maxAlignedWidth (REQ-040)', async () => {
  vscode._config['tables.maxAlignedWidth'] = 5;
  const editor = editorOn('| aaaaaaaa | b |\n|---|---|\n| c | d |', 0, 1);
  await run('markdownWorkbench.distributeTable');
  assert.strictEqual(editor.document.lines[2], '| c        | d   |');
  delete vscode._config['tables.maxAlignedWidth'];
});

test('reflowTable follows tables.ambiguousWidth: wide counts an ambiguous char twice', () => {
  const rows = ['| ±±±± | b |', '| --- | --- |', '| x | y |'];
  assert.strictEqual(reflowTable(rows, 'distribute')[2], '| x    | y   |');
  vscode._config['tables.ambiguousWidth'] = 'wide';
  try {
    assert.strictEqual(
      reflowTable(rows, 'distribute')[2],
      '| x        | y   |',
    );
  } finally {
    delete vscode._config['tables.ambiguousWidth'];
  }
});

test('with a selection, every table it touches is aligned in one edit', async () => {
  const text =
    '| a | bb |\n|-|-|\n| c | d |\n\ntext\n\n| x | yyy |\n|-|-|\n| z | w |\n\n| q |\n|-|';
  const editor = editorOn(text, 1, 1, 7, 2);
  await run('markdownWorkbench.distributeTable');
  const lines = editor.document.lines;
  assert.strictEqual(lines[2], '| c   | d   |');
  assert.strictEqual(lines[8], '| z   | w   |');
  assert.strictEqual(lines[11], '|-|', 'the untouched table stays');
  assert.strictEqual(editor.editCalls, 1, 'one undo step');
  const atStart = editorOn(text, 4, 0, 6, 0);
  await run('markdownWorkbench.consolidateTable');
  assert.strictEqual(
    atStart.editCalls,
    0,
    'a selection ending at column 0 stops above',
  );
});

test('the distribute command follows tables.ambiguousWidth: wide counts an ambiguous char twice', async () => {
  const text = '| ±±±± | b |\n| --- | --- |\n| x | y |';
  const narrow = editorOn(text, 0, 1);
  await run('markdownWorkbench.distributeTable');
  assert.strictEqual(narrow.document.lines[2], '| x    | y   |');
  vscode._config['tables.ambiguousWidth'] = 'wide';
  try {
    const wide = editorOn(text, 0, 1);
    await run('markdownWorkbench.distributeTable');
    assert.strictEqual(wide.document.lines[2], '| x        | y   |');
  } finally {
    delete vscode._config['tables.ambiguousWidth'];
  }
});
