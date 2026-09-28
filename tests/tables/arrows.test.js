// Up/Down in tables and the inTable context key (REQ-036 to REQ-038, REQ-059).

const { test, beforeEach } = require('node:test');
const assert = require('node:assert');
const {
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} = require('../helpers/vscode-mock');

const vscode = install();
const arrows = loadFresh('src/tables/arrows.js');
arrows.registerArrows({ subscriptions: [] });
const up = () => vscode._commands['markdownWorkbench.onUpKey']();
const down = () => vscode._commands['markdownWorkbench.onDownKey']();

function editorOn(text, line, ch) {
  const editor = new MockEditor(
    new MockDocument(text),
    new Selection(line, ch, line, ch),
  );
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}
const caret = (e) => [e.selection.active.line, e.selection.active.character];
const executed = () => vscode._executed.map((x) => x.id);

beforeEach(() => {
  vscode._config = {};
  arrows._resetForTest();
});

const T = '| name | 漢字 |\n| ---- | ---- |\n| abcd | xy   |\n| ab   | 漢   |';

test('Down keeps the cell and the visual offset, over the delimiter row (REQ-036)', async () => {
  const e = editorOn(T, 0, 4);
  await down();
  assert.deepStrictEqual(caret(e), [2, 4]);
  assert.deepStrictEqual(executed(), []);
});

test('the offset is measured in display width, so CJK keeps the column', async () => {
  const e = editorOn(T, 0, 10); // after the first CJK character (2 columns)
  await down();
  assert.deepStrictEqual(caret(e), [2, 11], 'two columns into "xy"');
  await down();
  assert.deepStrictEqual(caret(e), [3, 10], 'after 漢');
});

test('a shorter target cell puts the caret at its end', async () => {
  const e = editorOn(T, 2, 6);
  await down();
  assert.deepStrictEqual(caret(e), [3, 4]);
});

test('Up mirrors Down', async () => {
  const e = editorOn(T, 2, 3);
  await up();
  assert.deepStrictEqual(caret(e), [0, 3]);
});

test('the plain move runs at the edge, with a selection, several cursors or word wrap (REQ-037)', async () => {
  editorOn(T, 0, 3);
  await up();
  assert.deepStrictEqual(executed(), ['cursorUp'], 'top edge');
  editorOn(T, 3, 3);
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown'], 'bottom edge');
  const s = editorOn(T, 2, 2);
  s.selection = new Selection(2, 2, 2, 4);
  s.selections = [s.selection];
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown'], 'selection');
  const m = editorOn(T, 2, 2);
  m.selections = [m.selection, new Selection(0, 2, 0, 2)];
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown'], 'several cursors');
  vscode._config.wordWrap = 'on';
  editorOn(T, 0, 3);
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown'], 'word wrap');
});

test('arrowNavigation or enabled off runs the plain move (REQ-059, REQ-055)', async () => {
  for (const key of ['tables.arrowNavigation', 'tables.enabled']) {
    vscode._config = { [key]: false };
    editorOn(T, 0, 3);
    await down();
    assert.deepStrictEqual(executed(), ['cursorDown'], key);
  }
});

test('outside a table the plain move runs', async () => {
  editorOn('text\nmore', 0, 1);
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown']);
});

test('the context key is set only when it changes (REQ-038)', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const inTable = editorOn(T, 2, 1);
  const outside = new MockEditor(
    new MockDocument('plain | text'),
    new Selection(0, 1, 0, 1),
  );
  const setContext = () =>
    vscode._executed.filter((x) => x.id === 'setContext').map((x) => x.args);
  vscode._selectionListener({ textEditor: inTable });
  t.mock.timers.tick(100);
  vscode._selectionListener({ textEditor: inTable });
  vscode._selectionListener({ textEditor: outside });
  t.mock.timers.tick(100);
  vscode._activeEditorListener(undefined);
  assert.deepStrictEqual(setContext(), [
    ['markdownWorkbench.inTable', true],
    ['markdownWorkbench.inTable', false],
  ]);
});

test('after an edit the key waits for a typing pause before it parses (R2-4)', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const doc = new MockDocument(`text | pipe\n\n${T}`);
  const editor = new MockEditor(doc, new Selection(0, 4, 0, 4));
  const setContext = () =>
    vscode._executed.filter((x) => x.id === 'setContext').map((x) => x.args);
  vscode._executed.length = 0;
  vscode._selectionListener({ textEditor: editor });
  doc.version++;
  vscode._selectionListener({ textEditor: editor });
  assert.deepStrictEqual(setContext(), [], 'nothing computed while typing');
  editor.selection = new Selection(4, 3, 4, 3);
  t.mock.timers.tick(100);
  assert.deepStrictEqual(setContext(), [['markdownWorkbench.inTable', true]]);
  editor.selection = new Selection(0, 4, 0, 4);
  vscode._selectionListener({ textEditor: editor });
  assert.deepStrictEqual(
    setContext().at(-1),
    ['markdownWorkbench.inTable', false],
    'the version is parsed: answered at once',
  );
});

test('on the delimiter row the plain move runs', async () => {
  editorOn(T, 1, 3);
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown']);
  editorOn(T, 1, 3);
  await up();
  assert.deepStrictEqual(executed(), ['cursorUp']);
});
