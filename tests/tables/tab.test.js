// Tab / Shift+Tab in tables and `|` + Tab (REQ-027 to REQ-035, REQ-041, REQ-057/058/064).

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
const { tableTab } = loadFresh('src/tables/index.js');
const editing = loadFresh('src/editing/index.js');
editing.registerEditingCommands({ subscriptions: [] }, []);
const edit = (e, cb) => e.edit(cb);

function editorOn(text, line, ch, endLine, endCh) {
  const sel =
    endLine === undefined
      ? new Selection(line, ch, line, ch)
      : new Selection(line, ch, endLine, endCh);
  const editor = new MockEditor(new MockDocument(text), sel);
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}
const sel = (e) => [
  e.selection.start.line,
  e.selection.start.character,
  e.selection.end.line,
  e.selection.end.character,
];

beforeEach(() => {
  vscode._config = {};
});

const T = '| a | b |\n|---|---|\n| 1 | 22 |\n| 3 |  |';

test('T1: Tab moves to the next cell and selects its content (REQ-027)', async () => {
  const e = editorOn(T, 2, 2);
  assert.strictEqual(await tableTab(e, 1, edit), true);
  assert.strictEqual(e.document.lines[2], '| 1   | 22  |');
  assert.deepStrictEqual(sel(e), [2, 8, 2, 10]);
});

test('T1: an empty cell gets the caret', async () => {
  const e = editorOn(T, 3, 2);
  await tableTab(e, 1, edit);
  assert.deepStrictEqual(sel(e), [3, 8, 3, 8]);
});

test('T2: from the last cell of a row to the first of the next, over the delimiter (REQ-028)', async () => {
  const e = editorOn(T, 0, 7);
  await tableTab(e, 1, edit);
  assert.deepStrictEqual(sel(e), [2, 2, 2, 3]);
});

test('T3: Tab in the very last cell adds a row (REQ-029, REQ-058)', async () => {
  const e = editorOn(T, 3, 8);
  await tableTab(e, 1, edit);
  assert.strictEqual(e.document.lines.length, 5);
  assert.strictEqual(e.document.lines[4], '|     |     |');
  assert.deepStrictEqual(sel(e), [4, 2, 4, 2]);
  vscode._config['tables.tabAddsRow'] = false;
  const off = editorOn(T, 3, 8);
  await tableTab(off, 1, edit);
  assert.strictEqual(off.document.lines.length, 4, 'no row added');
});

test('T4: Shift+Tab goes back, wraps to the previous row, stops at the first header cell (REQ-030)', async () => {
  const e = editorOn(T, 2, 8);
  await tableTab(e, -1, edit);
  assert.deepStrictEqual(sel(e), [2, 2, 2, 3]);
  const wrap = editorOn(T, 2, 2);
  await tableTab(wrap, -1, edit);
  assert.deepStrictEqual(sel(wrap), [0, 8, 0, 9], 'header last cell');
  const first = editorOn(T, 0, 2);
  assert.strictEqual(await tableTab(first, -1, edit), true);
  assert.strictEqual(first.document.getText(), T, 'nothing changes');
  assert.strictEqual(first.editCalls, 0);
});

test('T4: Shift+Tab never outdents an indented table row', async () => {
  const e = editorOn('  | a | b |\n  |---|---|\n  | 1 | 2 |', 2, 4);
  await vscode._commands['markdownWorkbench.onShiftTabKey']();
  assert.ok(e.document.lines.every((l) => l.startsWith('  |')));
  assert.deepStrictEqual(vscode._executed, [], 'no outdent fallback');
});

test('T5: aligning happens in the same edit; an aligned table gets no edit (REQ-031)', async () => {
  const e = editorOn(T, 2, 2);
  await tableTab(e, 1, edit);
  assert.strictEqual(e.editCalls, 1);
  await tableTab(e, 1, edit);
  assert.strictEqual(e.editCalls, 1, 'already aligned: no undo step');
});

test('T6: missing cells are filled while aligning (REQ-032)', async () => {
  const e = editorOn('| a | b |\n|---|---|\n| 1 |', 2, 2);
  await tableTab(e, 1, edit);
  assert.strictEqual(e.document.lines[2], '| 1   |     |');
});

test('T7: Tab before the first pipe goes to the first cell (REQ-033)', async () => {
  const e = editorOn('> | a | b |\n> |---|---|\n> | 1 | 2 |', 2, 0);
  await tableTab(e, 1, edit);
  assert.deepStrictEqual(sel(e), [2, 4, 2, 5]);
});

test('the table branch runs before the column stops of markerless lines (REQ-034)', async () => {
  const e = editorOn(T, 2, 2);
  await vscode._commands['markdownWorkbench.onTabKey']();
  assert.deepStrictEqual(
    sel(e),
    [2, 8, 2, 10],
    'moved to the next cell, not indented',
  );
  assert.strictEqual(e.document.lines[2], '| 1   | 22  |');
});

test('T8: a selection over several lines keeps the block indent (REQ-035)', async () => {
  const e = editorOn(T, 0, 0, 2, 3);
  assert.strictEqual(await tableTab(e, 1, edit), false);
  await vscode._commands['markdownWorkbench.onTabKey']();
  assert.ok(e.document.lines[0].startsWith(' '), 'block indented');
});

test('tabSelectsCell off puts the caret at the cell end (REQ-057)', async () => {
  vscode._config['tables.tabSelectsCell'] = false;
  const e = editorOn(T, 2, 2);
  await tableTab(e, 1, edit);
  assert.deepStrictEqual(sel(e), [2, 10, 2, 10]);
});

test('K2: | + Tab closes the cell and opens the next one (REQ-041, REQ-064)', async () => {
  const e = editorOn('| Name', 0, 6);
  assert.strictEqual(await tableTab(e, 1, edit), true);
  assert.strictEqual(e.document.lines[0], '| Name | ');
  assert.deepStrictEqual(sel(e), [0, 9, 0, 9]);
  const closed = editorOn('> | Name |', 0, 10);
  await tableTab(closed, 1, edit);
  assert.strictEqual(closed.document.lines[0], '> | Name | ');
  assert.strictEqual(
    await tableTab(editorOn('| Name', 0, 3), 1, edit),
    false,
    'cursor mid-line',
  );
  vscode._config['tables.createFromPipe'] = false;
  assert.strictEqual(await tableTab(editorOn('| Name', 0, 6), 1, edit), false);
});

test('tables.enabled off leaves Tab to the list handling (REQ-055)', async () => {
  vscode._config['tables.enabled'] = false;
  assert.strictEqual(await tableTab(editorOn(T, 2, 2), 1, edit), false);
});
