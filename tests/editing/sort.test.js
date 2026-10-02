// Selection sorting (numeric-aware, ascending/descending).

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
const { sortSelection } = editing._internal;

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

test('sortSelection sorts numerically aware', async () => {
  const editor = editorOn('item10\nitem2\nitem1', 0, 0, 2, 5);
  await sortSelection(false);
  assert.deepStrictEqual(editor.document.lines, ['item1', 'item2', 'item10']);
});

test('sortSelection descending reverses', async () => {
  const editor = editorOn('a\nc\nb', 0, 0, 2, 1);
  await sortSelection(true);
  assert.deepStrictEqual(editor.document.lines, ['c', 'b', 'a']);
});

test('sortSelection without selection informs instead of editing', async () => {
  editorOn('a\nb', 0, 0);
  vscode._infos = [];
  await sortSelection(false);
  assert.strictEqual(vscode._infos.length, 1);
});
