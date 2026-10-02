// Tab / Shift+Tab in tables and `|` + Tab (REQ-027 to REQ-035, REQ-041, REQ-057/058/064).

import { test, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} from '../helpers/vscode-mock.ts';
import type { MockContext, MockEditFn } from '../helpers/vscode-mock.ts';
import { nth } from '../helpers/nth.ts';

// The modules with the mock editor and context in place of the vscode types.
interface Tables {
  tableTab(
    editor: MockEditor,
    dir: number,
    editFn: MockEditFn,
  ): Promise<boolean>;
}
interface Editing {
  registerEditingCommands(context: MockContext, features: unknown[]): void;
}

const vscode = install();
const { tableTab } = await loadFresh<Tables>('src/tables/index.ts');
const editing = await loadFresh<Editing>('src/editing/index.ts');
editing.registerEditingCommands({ subscriptions: [] }, []);
const edit: MockEditFn = (e, cb) => e.edit(cb);
const command = (id: string) =>
  defined(vscode._commands?.[id], `command ${id}`);

function editorOn(
  text: string,
  line: number,
  ch: number,
  endLine?: number,
  endCh?: number,
) {
  const sel =
    endLine === undefined || endCh === undefined
      ? new Selection(line, ch, line, ch)
      : new Selection(line, ch, endLine, endCh);
  const editor = new MockEditor(new MockDocument(text), sel);
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}
const sel = (e: MockEditor) => [
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
  assert.strictEqual(nth(e.document.lines, 2), '| 1   | 22  |');
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
  assert.strictEqual(nth(e.document.lines, 4), '|     |     |');
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

test('Tab selects the cell the model reads when a list marker is a cell', async () => {
  const text = '- | a | b\n--|--|--';
  const picked = (e: MockEditor) =>
    nth(e.document.lines, 0).slice(
      e.selection.start.character,
      e.selection.end.character,
    );
  const e = editorOn(text, 0, 0);
  await tableTab(e, 1, edit);
  assert.strictEqual(picked(e), 'a');
  const back = editorOn(text, 0, text.indexOf('b'));
  await tableTab(back, -1, edit);
  assert.strictEqual(picked(back), 'a');
});

test('Shift+Tab reaches the header of a table on a list item line (R2-2)', async () => {
  for (const marker of ['- ', '1. ']) {
    const pad = ' '.repeat(marker.length);
    const text = `${marker}| a | b |\n${pad}|---|---|\n${pad}| 1 | 2 |`;
    const e = editorOn(text, 2, pad.length + 2);
    await tableTab(e, -1, edit);
    const line = nth(e.document.lines, e.selection.start.line);
    assert.strictEqual(
      line.slice(e.selection.start.character, e.selection.end.character),
      'b',
      marker,
    );
  }
});

test('T4: Shift+Tab never outdents an indented table row', async () => {
  const e = editorOn('  | a | b |\n  |---|---|\n  | 1 | 2 |', 2, 4);
  await command('markdownWorkbench.onShiftTabKey')();
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
  assert.strictEqual(nth(e.document.lines, 2), '| 1   |     |');
});

test('T7: Tab before the first pipe goes to the first cell (REQ-033)', async () => {
  const e = editorOn('> | a | b |\n> |---|---|\n> | 1 | 2 |', 2, 0);
  await tableTab(e, 1, edit);
  assert.deepStrictEqual(sel(e), [2, 4, 2, 5]);
});

test('the table branch runs before the column stops of markerless lines (REQ-034)', async () => {
  const e = editorOn(T, 2, 2);
  await command('markdownWorkbench.onTabKey')();
  assert.deepStrictEqual(
    sel(e),
    [2, 8, 2, 10],
    'moved to the next cell, not indented',
  );
  assert.strictEqual(nth(e.document.lines, 2), '| 1   | 22  |');
});

test('T8: a selection over several lines keeps the block indent (REQ-035)', async () => {
  const e = editorOn(T, 0, 0, 2, 3);
  assert.strictEqual(await tableTab(e, 1, edit), false);
  await command('markdownWorkbench.onTabKey')();
  assert.ok(nth(e.document.lines, 0).startsWith(' '), 'block indented');
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
  assert.strictEqual(nth(e.document.lines, 0), '| Name | ');
  assert.deepStrictEqual(sel(e), [0, 9, 0, 9]);
  const closed = editorOn('> | Name |', 0, 10);
  await tableTab(closed, 1, edit);
  assert.strictEqual(nth(closed.document.lines, 0), '> | Name | ');
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

test('several cursors keep the normal Tab (T8)', async () => {
  const e = editorOn(T, 2, 2);
  e.selections = [e.selection, new Selection(0, 1, 0, 1)];
  assert.strictEqual(await tableTab(e, 1, edit), false);
  assert.strictEqual(e.document.getText(), T);
});
