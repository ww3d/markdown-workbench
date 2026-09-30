// Source mutation paths: list toggles (uniform multi-select, single undo
// step) and table cell toggles (nth occurrence, code spans blanked).
import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh, MockDocument } from '../helpers/vscode-mock.ts';
import { nth } from '../helpers/nth.ts';

/** The toggle paths this suite drives with mock documents (not `vscode.TextDocument`). */
interface ToggleApi {
  _internal: {
    applyToggle(
      document: MockDocument,
      lines: number[],
      checked: boolean,
    ): void;
    applyCellToggle(
      document: MockDocument,
      lineNo: number,
      idx: number,
      checked: boolean,
    ): void;
  };
}

const vscode = install();
const { _internal } = await loadFresh<ToggleApi>('src/views/index.ts');
const { applyToggle, applyCellToggle } = _internal;

// The i-th recorded edit, which every toggle path writes as a replace.
function applied(i: number) {
  const op = nth(vscode._applied, i);
  assert.ok(op.kind === 'replace', `edit ${i} is a replace`);
  return op;
}

function freshDoc(text: string) {
  vscode._applied.length = 0;
  return new MockDocument(text);
}

test('applyToggle flips a single open box to checked', () => {
  const doc = freshDoc('- [ ] task');
  applyToggle(doc, [0], true);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(applied(0).text, 'x');
  assert.strictEqual(applied(0).range.start.character, 3);
});

test('applyToggle sets a uniform state across mixed lines in one edit', () => {
  const doc = freshDoc('- [ ] a\n- [x] b\n- [ ] c');
  applyToggle(doc, [0, 1, 2], true);
  assert.strictEqual(
    vscode._applied.length,
    3,
    'one WorkspaceEdit, three ops, single undo step',
  );
  for (let i = 0; i < vscode._applied.length; i++)
    assert.strictEqual(applied(i).text, 'x');
});

test('applyToggle skips lines that are no task items', () => {
  const doc = freshDoc('- [ ] a\nplain text');
  applyToggle(doc, [0, 1], true);
  assert.strictEqual(vscode._applied.length, 1);
});

test('applyToggle handles numbered and nested markers', () => {
  const doc = freshDoc('1. [ ] a\n  - [x] b');
  applyToggle(doc, [0, 1], false);
  assert.strictEqual(vscode._applied.length, 2);
  for (let i = 0; i < vscode._applied.length; i++)
    assert.strictEqual(applied(i).text, ' ');
});

test('applyToggle on a compound line changes exactly the box character', () => {
  const doc = freshDoc('1. - [ ] foo');
  applyToggle(doc, [0], true);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(applied(0).text, 'x');
  assert.strictEqual(applied(0).range.start.character, 6); // inside "[ ]"
  assert.strictEqual(applied(0).range.end.character, 7);
});

test('applyToggle handles a nested dash-led compound line', () => {
  const doc = freshDoc('  - 1. [x] b');
  applyToggle(doc, [0], false);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(applied(0).range.start.character, 8);
});

test('applyToggle flips a task item with an empty label', () => {
  const doc = freshDoc('8. [ ]');
  applyToggle(doc, [0], true);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(applied(0).range.start.character, 4);
});

test('applyCellToggle flips the nth bracket on a row line', () => {
  const line = '| app | [x] | [ ] |';
  const doc = freshDoc(line);
  applyCellToggle(doc, 0, 1, true);
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(
    applied(0).range.start.character,
    line.lastIndexOf('[ ]') + 1,
  );
});

test('applyCellToggle ignores brackets inside code spans (index parity with renderer)', () => {
  const line = '| git `[ ]` | [x] | [ ] |';
  const doc = freshDoc(line);
  applyCellToggle(doc, 0, 0, false);
  assert.strictEqual(applied(0).range.start.character, line.indexOf('[x]') + 1);
});

test('applyCellToggle is a no-op for out-of-range lines and indices', () => {
  const doc = freshDoc('| a | [ ] |');
  applyCellToggle(doc, 5, 0, true);
  applyCellToggle(doc, 0, 9, true);
  assert.strictEqual(vscode._applied.length, 0);
});

test('a multi-line toggle is one applyEdit call, so one undo step', () => {
  const doc = freshDoc('- [ ] a\n- [x] b\n- [ ] c');
  let calls = 0;
  const real = vscode.workspace.applyEdit;
  vscode.workspace.applyEdit = (edit) => {
    calls++;
    return real(edit);
  };
  try {
    applyToggle(doc, [0, 1, 2], true);
  } finally {
    vscode.workspace.applyEdit = real;
  }
  assert.strictEqual(calls, 1, 'one WorkspaceEdit for all three lines');
  assert.strictEqual(vscode._applied.length, 3, 'carrying all three flips');
});
