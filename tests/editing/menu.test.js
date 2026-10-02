// Authoring quick-pick menu (Alt+M).

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
const ctx = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id) => vscode._commands[id]();

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

test('authoringMenu executes the picked command', async () => {
  editorOn('', 0, 0);
  vscode._quickPickResult = { label: 'x', cmd: 'markdownWorkbench.formatBold' };
  await run('markdownWorkbench.authoringMenu');
  assert.ok(
    vscode._executed.some((e) => e.id === 'markdownWorkbench.formatBold'),
  );
});

test('the menu offers the table sort and column commands (REQ-052)', async () => {
  let offered = [];
  const orig = vscode.window.showQuickPick;
  vscode.window.showQuickPick = (items) => {
    offered = items.map((i) => i.cmd);
    return Promise.resolve(undefined);
  };
  await run('markdownWorkbench.authoringMenu');
  vscode.window.showQuickPick = orig;
  for (const id of [
    'sortTableAscending',
    'sortTableDescending',
    'insertColumnLeft',
    'insertColumnRight',
    'deleteColumn',
    'moveColumnLeft',
    'moveColumnRight',
  ])
    assert.ok(offered.includes(`markdownWorkbench.${id}`), id);
});
