// Up/Down in tables and the inTable context key (REQ-036 to REQ-038, REQ-059).

import { test, beforeEach } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Selection,
} from '../helpers/vscode-mock.ts';
import type { MockContext } from '../helpers/vscode-mock.ts';

// The module as the mock context drives it (the real signature takes a vscode.ExtensionContext).
interface Arrows {
  registerArrows(context: MockContext): void;
  _resetForTest(): void;
}

const vscode = install();
const arrows = await loadFresh<Arrows>('src/tables/arrows.ts');
arrows.registerArrows({ subscriptions: [] });
const command = (id: string) =>
  defined(vscode._commands?.[id], `command ${id}`);
const up = () => command('markdownWorkbench.onUpKey')();
const down = () => command('markdownWorkbench.onDownKey')();
// The selection listener and the active-editor listener the module registered.
const selectionChanged = (textEditor: MockEditor) =>
  defined(vscode._selectionListener, 'selection listener')({ textEditor });
const activeEditorChanged = (editor: MockEditor | undefined) =>
  defined(vscode._activeEditorListener, 'active editor listener')(editor);

function editorOn(text: string, line: number, ch: number) {
  const editor = new MockEditor(
    new MockDocument(text),
    new Selection(line, ch, line, ch),
  );
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  return editor;
}
const caret = (e: MockEditor) => [
  e.selection.active.line,
  e.selection.active.character,
];
const executed = () => vscode._executed.map((x) => x.id);

beforeEach(() => {
  vscode._config = {};
  vscode._editorConfig = {};
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
  vscode._editorConfig.wordWrap = 'on';
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
  selectionChanged(inTable);
  t.mock.timers.tick(500);
  selectionChanged(inTable);
  vscode.window.activeTextEditor = outside;
  selectionChanged(outside);
  t.mock.timers.tick(500);
  activeEditorChanged(undefined);
  assert.deepStrictEqual(setContext(), [
    ['markdownWorkbench.inTable', true],
    ['markdownWorkbench.inTable', false],
  ]);
});

// A document that counts line reads: a block parse reads every line.
class CountingDoc extends MockDocument {
  reads = 0;
  override lineAt(n: number) {
    this.reads++;
    return super.lineAt(n);
  }
}
const countingDoc = (text: string) => new CountingDoc(text);
const setContextCalls = () =>
  vscode._executed.filter((x) => x.id === 'setContext').map((x) => x.args);

test('after an edit the key waits for a typing pause before it parses (R2-4)', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const doc = countingDoc(`text | pipe\n\n${T}`);
  const editor = new MockEditor(doc, new Selection(4, 3, 4, 3));
  vscode.window.activeTextEditor = editor;
  selectionChanged(editor);
  t.mock.timers.tick(500);
  assert.deepStrictEqual(setContextCalls().at(-1), [
    'markdownWorkbench.inTable',
    true,
  ]);
  vscode._executed.length = 0;
  editor.selection = new Selection(0, 4, 0, 4);
  doc.reads = 0;
  for (let key = 0; key < 3; key++) {
    doc.version++;
    selectionChanged(editor);
    t.mock.timers.tick(100);
  }
  assert.strictEqual(doc.reads, 3, 'typing: one line read per key, no parse');
  assert.deepStrictEqual(setContextCalls(), [], 'nothing set while typing');
  doc.reads = 0;
  t.mock.timers.tick(500);
  assert.strictEqual(doc.reads, doc.lineCount + 1, 'one parse after the pause');
  assert.deepStrictEqual(setContextCalls(), [
    ['markdownWorkbench.inTable', false],
  ]);
  editor.selection = new Selection(4, 3, 4, 3);
  selectionChanged(editor);
  assert.deepStrictEqual(
    setContextCalls().at(-1),
    ['markdownWorkbench.inTable', true],
    'the version is parsed: answered at once',
  );
});

test('a pending key update dies with an editor switch or disposal (R3-3)', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const doc = new MockDocument(T);
  const editor = new MockEditor(doc, new Selection(2, 1, 2, 1));
  vscode.window.activeTextEditor = editor;
  vscode._executed.length = 0;
  selectionChanged(editor);
  const other = new MockEditor(
    new MockDocument('plain'),
    new Selection(0, 0, 0, 0),
  );
  vscode.window.activeTextEditor = other;
  activeEditorChanged(other);
  t.mock.timers.tick(500);
  assert.deepStrictEqual(setContextCalls(), [], 'the old editor sets nothing');
  const ctx: MockContext = { subscriptions: [] };
  arrows.registerArrows(ctx);
  doc.version++;
  vscode.window.activeTextEditor = editor;
  selectionChanged(editor);
  for (const s of ctx.subscriptions) s.dispose?.();
  t.mock.timers.tick(500);
  assert.deepStrictEqual(setContextCalls(), [], 'disposed: the timer is gone');
});

test('on the delimiter row the plain move runs', async () => {
  editorOn(T, 1, 3);
  await down();
  assert.deepStrictEqual(executed(), ['cursorDown']);
  editorOn(T, 1, 3);
  await up();
  assert.deepStrictEqual(executed(), ['cursorUp']);
});
