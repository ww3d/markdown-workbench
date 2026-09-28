// Sort and column commands, and the preview's sortTable message (REQ-044, REQ-046, REQ-049 to REQ-051).

const { test, beforeEach } = require('node:test');
const assert = require('node:assert');
const {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} = require('../helpers/vscode-mock');

const vscode = install();
const tables = loadFresh('src/tables/index.js');
tables.registerTableFeatures({ subscriptions: [] });
const run = (id) => vscode._commands[id]();

function editorOn(text, line, ch) {
  const editor = new MockEditor(
    new MockDocument(text),
    new Selection(line, ch, line, ch),
  );
  vscode.window.activeTextEditor = editor;
  vscode._infos = [];
  return editor;
}
const col = (e, c) =>
  e.document.lines.slice(2).map((l) => l.split('|')[c + 1].trim());

beforeEach(() => {
  vscode._config = {};
  vscode._applied.length = 0;
});

const T =
  '| n | v |\n|---|---|\n| b | 10 |\n| a | 9 |\n|   | 2 |\n| c | 1,000 |';

test('sort ascending is numeric-aware, stable, empties last, one undo step (REQ-044)', async () => {
  const e = editorOn(T, 2, 7);
  await run('markdownWorkbench.sortTableAscending');
  assert.deepStrictEqual(col(e, 1), ['2', '9', '10', '1,000']);
  assert.strictEqual(e.editCalls, 1);
  const byName = editorOn(T, 2, 2);
  await run('markdownWorkbench.sortTableAscending');
  assert.deepStrictEqual(col(byName, 0), ['a', 'b', 'c', '']);
});

test('sort descending keeps empty cells last', async () => {
  const e = editorOn(T, 2, 2);
  await run('markdownWorkbench.sortTableDescending');
  assert.deepStrictEqual(col(e, 0), ['c', 'b', 'a', '']);
});

test('an already sorted table produces no edit; outside a table an info', async () => {
  const e = editorOn('| n |\n|---|\n| 1 |\n| 2 |', 2, 2);
  await run('markdownWorkbench.sortTableAscending');
  assert.strictEqual(e.editCalls, 0);
  editorOn('text', 0, 1);
  await run('markdownWorkbench.sortTableAscending');
  assert.strictEqual(vscode._infos.length, 1);
});

test('without autoAlign sorting moves whole lines, text unchanged', async () => {
  vscode._config['tables.autoAlign'] = false;
  const e = editorOn('| n |\n|---|\n| bb |\n|a|', 2, 2);
  await run('markdownWorkbench.sortTableAscending');
  assert.deepStrictEqual(e.document.lines, ['| n |', '|---|', '|a|', '| bb |']);
});

test('the sortTable message sorts the source and ignores a stale version (REQ-046)', () => {
  const doc = new MockDocument(T);
  assert.strictEqual(
    tables.sortTableMessage(doc, {
      line: 0,
      col: 1,
      dir: 'desc',
      version: doc.version - 1,
    }),
    false,
  );
  assert.deepStrictEqual(vscode._applied, []);
  assert.strictEqual(
    tables.sortTableMessage(doc, {
      line: 0,
      col: 1,
      dir: 'desc',
      version: doc.version,
    }),
    true,
  );
  assert.ok(vscode._applied.length > 0);
  assert.strictEqual(
    tables.sortTableMessage(doc, {
      line: 2,
      col: 1,
      dir: 'asc',
      version: doc.version,
    }),
    false,
    'not a table start',
  );
  vscode._config['tables.previewSort'] = false;
  assert.strictEqual(
    tables.sortTableMessage(doc, {
      line: 0,
      col: 1,
      dir: 'asc',
      version: doc.version,
    }),
    false,
  );
});

const C = '| a | b | c |\n|:--|---|--:|\n| 1 | 2 | 3 |';

test('insert column left/right adds an empty column and keeps the cursor in it (REQ-049)', async () => {
  const e = editorOn(C, 2, 6);
  await run('markdownWorkbench.insertColumnLeft');
  assert.deepStrictEqual(e.document.lines, [
    '| a   |     | b   | c   |',
    '| :-- | --- | --- | --: |',
    '| 1   |     | 2   | 3   |',
  ]);
  assert.strictEqual(e.selection.active.character, 8);
  const r = editorOn(C, 2, 6);
  await run('markdownWorkbench.insertColumnRight');
  assert.strictEqual(r.document.lines[0], '| a   | b   |     | c   |');
});

test('delete column removes it, but never the last one (REQ-050)', async () => {
  const e = editorOn(C, 2, 6);
  await run('markdownWorkbench.deleteColumn');
  assert.deepStrictEqual(e.document.lines, [
    '| a   | c   |',
    '| :-- | --: |',
    '| 1   | 3   |',
  ]);
  const one = editorOn('| a |\n|---|\n| 1 |', 2, 2);
  await run('markdownWorkbench.deleteColumn');
  assert.strictEqual(one.editCalls, 0);
});

test('move column swaps it with its neighbor, alignment included (REQ-051)', async () => {
  const e = editorOn(C, 2, 2);
  await run('markdownWorkbench.moveColumnRight');
  assert.deepStrictEqual(e.document.lines, [
    '| b   | a   | c   |',
    '| --- | :-- | --: |',
    '| 2   | 1   | 3   |',
  ]);
  const edge = editorOn(C, 2, 2);
  await run('markdownWorkbench.moveColumnLeft');
  assert.strictEqual(edge.editCalls, 0, 'first column cannot move left');
});

test('column commands outside a table inform instead of editing', async () => {
  editorOn('text', 0, 1);
  await run('markdownWorkbench.insertColumnLeft');
  assert.strictEqual(vscode._infos.length, 1);
});
