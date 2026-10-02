// Formatting toggles (bold/italic/code) and web/file link insertion.

import { test } from 'node:test';
import assert from 'node:assert';
import {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
  defined,
  makeUri,
} from '../helpers/vscode-mock.ts';
import type { MockContext } from '../helpers/vscode-mock.ts';

// The editing entry point with the mock context in place of a vscode.ExtensionContext.
interface Editing {
  registerEditingCommands(context: MockContext, shikiLangs: string[]): void;
}

const vscode = install();
const editing = await loadFresh<Editing>('src/editing/index.ts');
const { escapeSnippet, toggleWrap } = await loadFresh<
  typeof import('../../src/editing/wrap-links.ts')
>('src/editing/wrap-links.ts');

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

const ctx: MockContext = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id: string) => defined(vscode._commands?.[id], `command ${id}`)();

test('insertWebLink wraps the selection into a link snippet', async () => {
  const editor = editorOn('click here', 0, 0, 0, 10);
  await run('markdownWorkbench.insertWebLink');
  assert.strictEqual(
    editor.insertedSnippets[0]?.snippet.value,
    `[\${1:click here}](\${2:https://})`,
  );
});

test('insertFileLink without workspace files informs', async () => {
  editorOn('', 0, 0);
  vscode._infos = [];
  await run('markdownWorkbench.insertFileLink');
  assert.strictEqual(vscode._infos.length, 1);
});

// The two workspace files the link tests pick from.
const docsFile = makeUri('file', '/ws/docs/a.md');
const imgFile = makeUri('file', '/ws/img/pic.png');

// Run insertFileLink over the two workspace files with the quick pick choosing
// `docsFile`, on an editor whose document has the given URI scheme.
async function pickDocsFile(scheme: string, selection?: [number, number]) {
  const doc = new MockDocument('see x', makeUri(scheme, '/ws/doc.md'));
  const sel = selection
    ? new Selection(0, selection[0], 0, selection[1])
    : new Selection(0, 4, 0, 4);
  const editor = new MockEditor(doc, sel);
  vscode.window.activeTextEditor = editor;
  const origFindFiles = vscode.workspace.findFiles;
  vscode.workspace.findFiles = async () => [imgFile, docsFile];
  vscode._quickPickResult = (items: unknown) =>
    Array.isArray(items)
      ? items.find(
          (item: unknown) =>
            typeof item === 'object' &&
            item !== null &&
            'uri' in item &&
            item.uri === docsFile,
        )
      : undefined;
  try {
    await run('markdownWorkbench.insertFileLink');
  } finally {
    vscode.workspace.findFiles = origFindFiles;
    vscode._quickPickResult = undefined;
  }
  return editor;
}

test('insertFileLink links the picked file relative to a file document', async () => {
  const editor = await pickDocsFile('file');
  assert.strictEqual(editor.document.lines[0], 'see [a.md](docs/a.md)x');
});

test('insertFileLink labels the link with the selected text', async () => {
  const editor = await pickDocsFile('file', [4, 5]);
  assert.strictEqual(editor.document.lines[0], 'see [x](docs/a.md)');
});

test('insertFileLink uses the workspace-relative path outside a file document', async () => {
  const editor = await pickDocsFile('untitled', [4, 5]);
  assert.strictEqual(editor.document.lines[0], 'see [x](/ws/docs/a.md)');
});
