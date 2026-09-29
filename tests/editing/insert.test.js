// List conversion (bulleted/numbered/task), table insertion via input box,
// and language-identifier insertion.

import { test } from 'node:test';
import assert from 'node:assert';
import {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} from '../helpers/vscode-mock.js';

const vscode = install();
const editing = await loadFresh('src/editing/index.js');
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

test('insertBulletedList prefixes selected non-empty lines', async () => {
  const editor = editorOn('one\n\ntwo', 0, 0, 2, 3);
  await run('markdownWorkbench.insertBulletedList');
  assert.deepStrictEqual(editor.document.lines, ['- one', '', '- two']);
});

test('insertNumberedList numbers only non-empty lines', async () => {
  const editor = editorOn('a\n\nb', 0, 0, 2, 1);
  await run('markdownWorkbench.insertNumberedList');
  assert.deepStrictEqual(editor.document.lines, ['1. a', '', '2. b']);
});

test('insertTaskList converts to open checkboxes', async () => {
  const editor = editorOn('a\nb', 0, 0, 1, 1);
  await run('markdownWorkbench.insertTaskList');
  assert.deepStrictEqual(editor.document.lines, ['- [ ] a', '- [ ] b']);
});

test('insertTaskList with empty selection inserts a single marker', async () => {
  const editor = editorOn('', 0, 0);
  await run('markdownWorkbench.insertTaskList');
  assert.strictEqual(editor.document.lines[0], '- [ ] ');
});

test('insertTable builds a snippet from the size input', async () => {
  const editor = editorOn('', 0, 0);
  vscode._inputBoxResult = '2x1';
  await run('markdownWorkbench.insertTable');
  assert.strictEqual(editor.insertedSnippets.length, 1);
  const v = editor.insertedSnippets[0].snippet.value;
  assert.match(
    v,
    /^\| \$\{1:Header\} \| \$\{2:Header\} \|\n\| --- \| --- \|\n/,
  );
  assert.match(v, /\| \$3 \| \$4 \|\n$/);
});

test('insertTable aborts silently on cancel', async () => {
  const editor = editorOn('', 0, 0);
  vscode._inputBoxResult = undefined;
  await run('markdownWorkbench.insertTable');
  assert.strictEqual(editor.insertedSnippets.length, 0);
});

test('insertLanguageIdentifier replaces the selection with the pick', async () => {
  const editor = editorOn('', 0, 0);
  vscode._quickPickResult = 'powershell';
  await run('markdownWorkbench.insertLanguageIdentifier');
  assert.strictEqual(editor.document.lines[0], 'powershell');
});
