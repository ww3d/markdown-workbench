// Command registration (registerEditingCommands): every command's behavior
// with no active editor.

import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh } from '../helpers/vscode-mock.js';

const vscode = install();
const editing = await loadFresh('src/editing/index.js');
const ctx = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id) => vscode._commands[id]();

const FALLBACK_WITHOUT_EDITOR = {
  'markdownWorkbench.onEnterKey': 'default:type',
  'markdownWorkbench.onShiftEnterKey': 'default:type',
  'markdownWorkbench.onTabKey': 'tab',
  'markdownWorkbench.onShiftTabKey': 'outdent',
  'markdownWorkbench.joinForwardOrFallback': 'deleteWordRight',
  'markdownWorkbench.joinBackwardOrFallback': 'deleteWordLeft',
};
const NOOP_WITHOUT_EDITOR = [
  'markdownWorkbench.formatBold',
  'markdownWorkbench.formatItalic',
  'markdownWorkbench.formatCode',
  'markdownWorkbench.insertWebLink',
  'markdownWorkbench.insertFileLink',
  'markdownWorkbench.insertBulletedList',
  'markdownWorkbench.insertNumberedList',
  'markdownWorkbench.insertTaskList',
  'markdownWorkbench.insertTable',
  'markdownWorkbench.distributeTable',
  'markdownWorkbench.consolidateTable',
  'markdownWorkbench.insertLanguageIdentifier',
];
// Table commands (src/tables): without an editor they do nothing; the arrow
// keys fall back to the plain cursor move.
const TABLE_NOOP_WITHOUT_EDITOR = [
  'markdownWorkbench.sortTableAscending',
  'markdownWorkbench.sortTableDescending',
  'markdownWorkbench.insertColumnLeft',
  'markdownWorkbench.insertColumnRight',
  'markdownWorkbench.deleteColumn',
  'markdownWorkbench.moveColumnLeft',
  'markdownWorkbench.moveColumnRight',
];
FALLBACK_WITHOUT_EDITOR['markdownWorkbench.onUpKey'] = 'cursorUp';
FALLBACK_WITHOUT_EDITOR['markdownWorkbench.onDownKey'] = 'cursorDown';
NOOP_WITHOUT_EDITOR.push(...TABLE_NOOP_WITHOUT_EDITOR);

function noEditor() {
  vscode.window.activeTextEditor = undefined;
  vscode._executed.length = 0;
  vscode._applied.length = 0;
  vscode._infos = [];
}

for (const [id, fallback] of Object.entries(FALLBACK_WITHOUT_EDITOR)) {
  test(`${id} without an active editor falls back to ${fallback}`, async () => {
    noEditor();
    await run(id);
    assert.deepStrictEqual(
      vscode._executed.map((e) => e.id),
      [fallback],
    );
  });
}

for (const id of NOOP_WITHOUT_EDITOR) {
  test(`${id} without an active editor does nothing`, async () => {
    noEditor();
    await run(id);
    assert.deepStrictEqual(vscode._executed, [], 'no command executed');
    assert.deepStrictEqual(vscode._applied, [], 'no edit applied');
  });
}

for (const id of [
  'markdownWorkbench.sortAscending',
  'markdownWorkbench.sortDescending',
]) {
  test(`${id} without an active editor asks for a selection`, async () => {
    noEditor();
    await run(id);
    assert.deepStrictEqual(vscode._infos, ['Select the lines to sort first.']);
  });
}

test('every editing command is covered by a no-editor test', () => {
  const covered = new Set([
    ...Object.keys(FALLBACK_WITHOUT_EDITOR),
    ...NOOP_WITHOUT_EDITOR,
    'markdownWorkbench.sortAscending',
    'markdownWorkbench.sortDescending',
    'markdownWorkbench.authoringMenu', // a quick pick; reads no editor itself
  ]);
  const registered = Object.keys(vscode._commands).filter((id) =>
    id.startsWith('markdownWorkbench.'),
  );
  assert.deepStrictEqual(
    registered.filter((id) => !covered.has(id)),
    [],
  );
});
