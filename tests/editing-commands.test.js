// Interactive commands: list conversion, table insertion via input box,
// reflow command with cursor-based table detection, quick-pick driven
// commands, link insertion.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh, MockDocument, MockEditor, Selection } = require('./helpers/vscode-mock');

const vscode = install();
const editing = loadFresh('src/editing.js');
const ctx = { subscriptions: [] };
editing.registerEditingCommands(ctx, ['powershell', 'javascript']);
const run = (id) => vscode._commands[id]();

function editorOn(text, line, character, endLine, endCharacter) {
  const doc = new MockDocument(text);
  const sel = endLine === undefined
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
  assert.match(v, /^\| \$\{1:Header\} \| \$\{2:Header\} \|\n\| --- \| --- \|\n/);
  assert.match(v, /\| \$3 \| \$4 \|\n$/);
});

test('insertTable aborts silently on cancel', async () => {
  const editor = editorOn('', 0, 0);
  vscode._inputBoxResult = undefined;
  await run('markdownWorkbench.insertTable');
  assert.strictEqual(editor.insertedSnippets.length, 0);
});

test('distributeTable expands around the cursor to the whole table', async () => {
  const editor = editorOn('text\n| a | bbbb |\n|---|---|\n| c | d |\nafter', 2, 1);
  await run('markdownWorkbench.distributeTable');
  assert.strictEqual(editor.document.lines[1], '| a   | bbbb |');
  assert.strictEqual(editor.document.lines[3], '| c   | d    |');
  assert.strictEqual(editor.document.lines[0], 'text');
  assert.strictEqual(editor.document.lines[4], 'after');
});

test('distributeTable outside a table informs instead of editing', async () => {
  editorOn('plain text', 0, 2);
  vscode._infos = [];
  await run('markdownWorkbench.distributeTable');
  assert.strictEqual(vscode._infos.length, 1);
});

test('consolidateTable shrinks padding', async () => {
  const editor = editorOn('| aaa   | b     |\n|-------|-------|\n| c     | d     |', 0, 1);
  await run('markdownWorkbench.consolidateTable');
  assert.strictEqual(editor.document.lines[2], '| c | d |');
});

test('insertWebLink wraps the selection into a link snippet', async () => {
  const editor = editorOn('click here', 0, 0, 0, 10);
  await run('markdownWorkbench.insertWebLink');
  assert.strictEqual(editor.insertedSnippets[0].snippet.value, '[${1:click here}](${2:https://})');
});

test('insertLanguageIdentifier replaces the selection with the pick', async () => {
  const editor = editorOn('', 0, 0);
  vscode._quickPickResult = 'powershell';
  await run('markdownWorkbench.insertLanguageIdentifier');
  assert.strictEqual(editor.document.lines[0], 'powershell');
});

test('authoringMenu executes the picked command', async () => {
  editorOn('', 0, 0);
  vscode._quickPickResult = { label: 'x', cmd: 'markdownWorkbench.formatBold' };
  await run('markdownWorkbench.authoringMenu');
  assert.ok(vscode._executed.some((e) => e.id === 'markdownWorkbench.formatBold'));
});

test('insertFileLink without workspace files informs', async () => {
  editorOn('', 0, 0);
  vscode._infos = [];
  await run('markdownWorkbench.insertFileLink');
  assert.strictEqual(vscode._infos.length, 1);
});

function change(line, character) {
  return { contentChanges: [{ range: { start: { line, character }, end: { line, character } } }] };
}

test('marker type propagation listener follows a first-item change', () => {
  vscode._config['lists.extraMarkers'] = ['1)', 'a)'];
  vscode._config['lists.extraMarkersEnabled'] = true;
  vscode._applied.length = 0;
  const doc = new MockDocument('1) x\nb) y\nc) z');
  vscode._docChangeListener(Object.assign({ document: doc }, change(0, 0)));
  delete vscode._config['lists.extraMarkers'];
  delete vscode._config['lists.extraMarkersEnabled'];
  assert.deepStrictEqual(vscode._applied.map((o) => o.text), ['2)', '3)']);
});

test('marker type propagation listener stays quiet when no markers are enabled', () => {
  vscode._applied.length = 0;
  const doc = new MockDocument('a) x\nb) y'); // custom markers, not recognized when off
  vscode._docChangeListener(Object.assign({ document: doc }, change(0, 0)));
  assert.strictEqual(vscode._applied.length, 0);
});

test('manual native number change renumbers the following siblings (no reset)', () => {
  vscode._applied.length = 0;
  const doc = new MockDocument('1. a\n5. b\n3. c\n4. d'); // user typed 2.->5.
  vscode._docChangeListener(Object.assign({ document: doc }, change(1, 0)));
  // 5. stays; the following continue from it -> 6, 7 (line0 1. untouched).
  assert.deepStrictEqual(vscode._applied.map((o) => o.text), ['6.', '7.']);
});

test('editing a line body does not reflow an intentionally non-sequential list', () => {
  vscode._applied.length = 0;
  const doc = new MockDocument('1. a\n5. b\n6. c');
  // change in the text (character past the marker), marker untouched
  vscode._docChangeListener(Object.assign({ document: doc }, change(0, 3)));
  assert.strictEqual(vscode._applied.length, 0);
});

test('the re-entrancy guard suppresses the listener during our own edits', () => {
  vscode._applied.length = 0;
  editing._internal.setPropagatingForTest(true);
  const doc = new MockDocument('1. a\n5. b\n6. c');
  vscode._docChangeListener(Object.assign({ document: doc }, change(1, 0)));
  editing._internal.setPropagatingForTest(false);
  assert.strictEqual(vscode._applied.length, 0);
});
