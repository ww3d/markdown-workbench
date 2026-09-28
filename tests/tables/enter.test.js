// Enter and Shift+Enter in tables (REQ-014 to REQ-026, REQ-047, REQ-055/056/060/063/065).

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
const { tableEnter, tableShiftEnter } = loadFresh('src/tables/index.js');
const edit = (e, cb) => e.edit(cb);

function editorOn(text, line, ch) {
  const editor = new MockEditor(
    new MockDocument(text),
    new Selection(line, ch, line, ch),
  );
  vscode.window.activeTextEditor = editor;
  return editor;
}
const lines = (e) => e.document.lines;
const caret = (e) => [e.selection.active.line, e.selection.active.character];

beforeEach(() => {
  vscode._config = {};
});

const T = '| a | b |\n|---|---|\n| 1 | 2 |';

test('E1: Enter in a body row adds an empty row below, cursor in its first cell (REQ-014)', async () => {
  const e = editorOn(T, 2, 5);
  assert.strictEqual(await tableEnter(e, edit), true);
  assert.deepStrictEqual(lines(e), [
    '| a   | b   |',
    '| --- | --- |',
    '| 1   | 2   |',
    '|     |     |',
  ]);
  assert.deepStrictEqual(caret(e), [3, 2]);
});

test('E1+E8: Enter and alignment are one undo step (REQ-020, REQ-021)', async () => {
  const e = editorOn(T, 2, 5);
  await tableEnter(e, edit);
  assert.strictEqual(e.editCalls, 1);
  e.document.undo();
  assert.strictEqual(e.document.getText(), T);
});

test('E2: Enter before the first cell adds a row above (REQ-015)', async () => {
  const e = editorOn('> | a |\n> |---|\n> | 1 |', 2, 1);
  await tableEnter(e, edit);
  assert.deepStrictEqual(lines(e), [
    '> | a   |',
    '> | --- |',
    '> |     |',
    '> | 1   |',
  ]);
  assert.deepStrictEqual(caret(e), [2, 4]);
});

test('E3/E5: Enter in the header or delimiter row adds a row right below it (REQ-016)', async () => {
  for (const line of [0, 1]) {
    const e = editorOn(T, line, 5);
    await tableEnter(e, edit);
    assert.strictEqual(lines(e)[2], '|     |     |');
    assert.strictEqual(lines(e)[3], '| 1   | 2   |');
    assert.deepStrictEqual(caret(e), [2, 2]);
  }
});

test('Enter before the header cells runs the normal Enter', async () => {
  const e = editorOn(T, 0, 0);
  assert.strictEqual(await tableEnter(e, edit), false);
});

test('E4: a typed header gets its delimiter row and an empty row (REQ-017)', async () => {
  const e = editorOn('| Name | Age |', 0, 13);
  assert.strictEqual(await tableEnter(e, edit), true);
  assert.deepStrictEqual(lines(e), [
    '| Name | Age |',
    '| ---- | --- |',
    '|      |     |',
  ]);
  assert.deepStrictEqual(caret(e), [2, 2]);
  const bare = editorOn('> | Name | Age', 0, 14);
  await tableEnter(bare, edit);
  assert.deepStrictEqual(lines(bare), [
    '> | Name | Age',
    '> | ---- | ---',
    '> |      |',
  ]);
});

test('E6: Enter in the last, empty row ends the table and keeps the prefix (REQ-018)', async () => {
  const e = editorOn('> | a |\n> |---|\n> | 1 |\n> |   |', 3, 4);
  await tableEnter(e, edit);
  assert.deepStrictEqual(lines(e), [
    '> | a   |',
    '> | --- |',
    '> | 1   |',
    '> ',
  ]);
  assert.deepStrictEqual(caret(e), [3, 2]);
});

test('E7: an empty row in the middle continues like E1 (REQ-019)', async () => {
  const e = editorOn('| a |\n|---|\n|   |\n| 1 |', 2, 2);
  await tableEnter(e, edit);
  assert.deepStrictEqual(lines(e), [
    '| a   |',
    '| --- |',
    '|     |',
    '|     |',
    '| 1   |',
  ]);
});

test('E8: alignment replaces only changed ranges, unchanged rows stay untouched (REQ-022)', async () => {
  const e = editorOn('| a   |\n| --- |\n| 1   |\n| 2   |', 2, 3);
  const spans = [];
  const orig = e.edit.bind(e);
  e.edit = (cb) =>
    orig((b) =>
      cb({
        ...b,
        replace: (r, t) => {
          spans.push([r.start.line, r.start.character, r.end.character, t]);
          b.replace(r, t);
        },
      }),
    );
  await tableEnter(e, edit);
  assert.deepStrictEqual(spans, [[2, 7, 7, '\n|     |']]);
});

test('E9: several cursors or a selection run the normal Enter (REQ-023)', async () => {
  const e = editorOn(T, 2, 3);
  e.selections = [e.selection, new Selection(0, 1, 0, 1)];
  assert.strictEqual(await tableEnter(e, edit), false);
  const s = editorOn(T, 2, 3);
  s.selection = new Selection(2, 1, 2, 4);
  s.selections = [s.selection];
  assert.strictEqual(await tableEnter(s, edit), false);
});

test('E10: no table branch in a code block or the frontmatter (REQ-024)', async () => {
  const fence = editorOn('```\n| a |\n|---|\n| 1 |\n```', 3, 3);
  assert.strictEqual(await tableEnter(fence, edit), false);
  const fm = editorOn('---\n| a |\n|---|\n---', 1, 3);
  assert.strictEqual(await tableEnter(fm, edit), false);
});

test('enterBehavior nextRowSameColumn moves down in the column, adds a row only at the end (REQ-025)', async () => {
  vscode._config['tables.enterBehavior'] = 'nextRowSameColumn';
  const e = editorOn('| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |', 2, 7);
  await tableEnter(e, edit);
  assert.strictEqual(lines(e).length, 4);
  assert.deepStrictEqual(caret(e), [3, 8]);
  await tableEnter(e, edit);
  assert.strictEqual(lines(e).length, 5);
  assert.deepStrictEqual(caret(e), [4, 8]);
});

test('K5: a new row carries [ ] in checkbox columns (REQ-047, REQ-065)', async () => {
  const e = editorOn('| x | t |\n|---|---|\n| [x] | a |', 2, 9);
  await tableEnter(e, edit);
  assert.strictEqual(lines(e)[3], '| [ ] |     |');
  vscode._config['tables.continueCheckboxes'] = false;
  const off = editorOn('| x | t |\n|---|---|\n| [x] | a |', 2, 9);
  await tableEnter(off, edit);
  assert.strictEqual(lines(off)[3], '|     |     |');
});

test('autoAlign off inserts the row and touches nothing else (REQ-060)', async () => {
  vscode._config['tables.autoAlign'] = false;
  const e = editorOn(T, 2, 5);
  await tableEnter(e, edit);
  assert.deepStrictEqual(lines(e), [
    '| a | b |',
    '|---|---|',
    '| 1 | 2 |',
    '|  |  |',
  ]);
});

test('tables.enabled off leaves Enter to the list handling (REQ-055)', async () => {
  vscode._config['tables.enabled'] = false;
  assert.strictEqual(await tableEnter(editorOn(T, 2, 5), edit), false);
});

test('Shift+Enter in a cell inserts <br> and aligns (REQ-026, REQ-063)', async () => {
  const e = editorOn(T, 2, 3);
  assert.strictEqual(await tableShiftEnter(e, edit), true);
  assert.deepStrictEqual(lines(e), [
    '| a     | b   |',
    '| ----- | --- |',
    '| 1<br> | 2   |',
  ]);
  assert.deepStrictEqual(caret(e), [2, 7]);
});

test('Shift+Enter with an empty cellLineBreak or outside a cell runs the normal one', async () => {
  vscode._config['tables.cellLineBreak'] = '';
  assert.strictEqual(await tableShiftEnter(editorOn(T, 2, 3), edit), false);
  vscode._config = {};
  assert.strictEqual(
    await tableShiftEnter(editorOn(T, 1, 2), edit),
    false,
    'delimiter row',
  );
  assert.strictEqual(
    await tableShiftEnter(editorOn('text', 0, 2), edit),
    false,
  );
});

test('Shift+Enter without autoAlign inserts at the cursor only', async () => {
  vscode._config['tables.autoAlign'] = false;
  vscode._config['tables.cellLineBreak'] = '<br/>';
  const e = editorOn(T, 2, 3);
  await tableShiftEnter(e, edit);
  assert.strictEqual(lines(e)[2], '| 1<br/> | 2 |');
  assert.deepStrictEqual(caret(e), [2, 8]);
});

test('E2 in a borderless row: Enter before the first content adds a row above', async () => {
  const e = editorOn('a | b\n--|--\n1 | 2', 2, 0);
  await tableEnter(e, edit);
  assert.deepStrictEqual(lines(e), [
    'a   | b',
    '--- | ---',
    '|   |',
    '1   | 2',
  ]);
});

test('E4 above a paragraph line ends the new table with a blank line', async () => {
  const e = editorOn('> | a | b\n> Some text', 0, 9);
  await tableEnter(e, edit);
  assert.deepStrictEqual(lines(e), [
    '> | a   | b',
    '> | --- | ---',
    '> |     |',
    '>',
    '> Some text',
  ]);
});
