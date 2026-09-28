// Command registration (registerEditingCommands): every command's behavior
// with no active editor.

const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh } = require('../helpers/vscode-mock');

const vscode = install();
const editing = loadFresh('src/editing/index.js');
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
