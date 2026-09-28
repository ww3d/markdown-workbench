// Tables: pure reflow helpers plus the distribute/consolidate commands.

const { test } = require('node:test');
const assert = require('node:assert');
const {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} = require('../helpers/vscode-mock');

const vscode = install();
const editing = loadFresh('src/editing/index.js');
const { reflowTable, splitRow } = editing;

function editorOn(text, line, character, endLine, endCharacter) {
  const doc = new MockDocument(text);
  const sel =
    endLine === undefined
      ? new Selection(line, character, line, character)
      : new Selection(line, character, endLine, endCharacter);
  const editor = new MockEditor(doc, sel);
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}

test('splitRow trims pipes and cells', () => {
  assert.deepStrictEqual(splitRow('| a | b c |'), ['a', 'b c']);
  assert.deepStrictEqual(splitRow('a|b'), ['a', 'b']);
});

test('reflowTable distribute pads to column widths and keeps alignment colons', () => {
  const out = reflowTable(
    ['| App | On |', '|:---|---:|', '| git | yes |', '| q | n |'],
    'distribute',
  );
  assert.strictEqual(out[2], '| git | yes |');
  assert.strictEqual(out[3], '| q   | n   |');
  assert.match(out[1], /^\| :-+ \| -+: \|$/);
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

const ctx = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id) => vscode._commands[id]();

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
  assert.deepStrictEqual(splitRow('| a \\| b | c |'), ['a \\| b', 'c']);
  for (const mode of ['distribute', 'consolidate']) {
    const out = reflowTable(
      ['| a \\| b | c |', '|---|---|', '| x | y |'],
      mode,
    );
    assert.deepStrictEqual(splitRow(out[0]), ['a \\| b', 'c']);
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
