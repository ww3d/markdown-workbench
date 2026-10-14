// Formatting toggles (bold/italic/code) and web/file link insertion.

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
const { escapeSnippet, toggleWrap } = editing._internal;

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

test('escapeSnippet escapes snippet metacharacters', () => {
  assert.strictEqual(escapeSnippet('a$b}c\\d'), 'a\\$b\\}c\\\\d');
});

test('toggleWrap wraps a selection', async () => {
  const editor = editorOn('make bold here', 0, 5, 0, 9);
  await toggleWrap('**');
  assert.strictEqual(editor.document.lines[0], 'make **bold** here');
});

test('toggleWrap unwraps an exactly wrapped selection', async () => {
  const editor = editorOn('make **bold** here', 0, 5, 0, 13);
  await toggleWrap('**');
  assert.strictEqual(editor.document.lines[0], 'make bold here');
});

test('toggleWrap unwraps when the selection sits inside the markers', async () => {
  const editor = editorOn('make **bold** here', 0, 7, 0, 11);
  await toggleWrap('**');
  assert.strictEqual(editor.document.lines[0], 'make bold here');
});

test('toggleWrap on an empty cursor over a word wraps the word', async () => {
  const editor = editorOn('make bold here', 0, 7);
  await toggleWrap('*');
  assert.strictEqual(editor.document.lines[0], 'make *bold* here');
});

const ctx = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id) => vscode._commands[id]();

test('insertWebLink wraps the selection into a link snippet', async () => {
  const editor = editorOn('click here', 0, 0, 0, 10);
  await run('markdownWorkbench.insertWebLink');
  assert.strictEqual(
    editor.insertedSnippets[0].snippet.value,
    `[\${1:click here}](\${2:https://})`,
  );
});

test('insertFileLink without workspace files informs', async () => {
  editorOn('', 0, 0);
  vscode._infos = [];
  await run('markdownWorkbench.insertFileLink');
  assert.strictEqual(vscode._infos.length, 1);
});
