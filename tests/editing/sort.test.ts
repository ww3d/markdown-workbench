// Selection sorting (numeric-aware, ascending/descending).

import { test } from 'node:test';
import assert from 'node:assert';
import {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} from '../helpers/vscode-mock.ts';

const vscode = install();
const { sortSelection } = await loadFresh<
  typeof import('../../src/editing/sort.ts')
>('src/editing/sort.ts');

function editorOn(
  text: string,
  line: number,
  character: number,
  endLine?: number,
  endCharacter?: number,
) {
  const doc = new MockDocument(text);
  const sel =
    endLine === undefined || endCharacter === undefined
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
