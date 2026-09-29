// Column stops for markerless continuation lines, driven through Tab/Shift+Tab.

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
const { onTabKey, onShiftTabKey } = editing._internal;

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

function tabbed(editor, tabSize, insertSpaces) {
  editor.options = { tabSize, insertSpaces: insertSpaces !== false };
  return editor;
}

test('Tab on a continuation line stops at a word start above it', async () => {
  // The line above contributes a word start at column 3; Tab on the markerless
  // line stops there, not at the full tab-size multiple (4).
  const editor = editorOn('2. word2 word3\nbb', 1, 2);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['2. word2 word3', '   bb']);
});

test('Tab on a continuation line with no stops steps by the tab size', async () => {
  const editor = tabbed(editorOn('   note', 0, 7), 2);
  await onTabKey();
  assert.strictEqual(editor.document.lines[0], '    note'); // 3 -> next 2-multiple = 4
});

test('Shift+Tab on a continuation line steps back by the tab size', async () => {
  const editor = tabbed(editorOn('   note', 0, 7), 2);
  await onShiftTabKey();
  assert.strictEqual(editor.document.lines[0], '  note'); // 3 -> next lower 2-multiple = 2
});

test('Tab on a continuation line stops at column 3 before the tab-size multiple', async () => {
  // tabSize 8, a content/word stop at column 3 above -> Tab stops at 3, not 8.
  const editor = tabbed(editorOn('1. x\nbb', 1, 2), 8);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. x', '   bb']);
});

test('Tab indents several markerless lines together', async () => {
  const editor = editorOn('aa\nbb', 0, 0, 1, 2);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['    aa', '    bb']);
});

test('mixed selection moves markers and markerless lines as one block', async () => {
  const editor = editorOn('1. a\n2. b\ncont', 0, 0, 2, 4);
  await onTabKey();
  // One common delta (tab size) over all three; markers not renumbered.
  assert.deepStrictEqual(editor.document.lines, [
    '    1. a',
    '    2. b',
    '    cont',
  ]);
});

test('Tab moves several markerless lines as a block, keeping relative indent', async () => {
  // Depths 0/2/4; the topmost snaps to 4 (tabSize), all shift +4 -> 4/6/8.
  const editor = editorOn('aaa\n  bb\n    c', 0, 0, 2, 5);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '    aaa',
    '      bb',
    '        c',
  ]);
});

test('Shift+Tab moves a markerless block left, capped by the flattest line', async () => {
  // Depths 2/4/6, tabSize 2; topmost wants -2, flattest is 2 -> -2 -> 0/2/4.
  const editor = tabbed(editorOn('  bb\n    cc\n      dd', 0, 0, 2, 8), 2);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['bb', '  cc', '    dd']);
});

test('Shift+Tab leaves a markerless block unchanged when the flattest line is at 0', async () => {
  const editor = editorOn('a\n  b\n    c', 0, 0, 2, 5);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['a', '  b', '    c']);
});

test('mixed selection keeps relative indent moving as one block', async () => {
  const editor = editorOn('1. a\n2. b\ncont1\n  cont2', 0, 0, 3, 7);
  await onTabKey();
  // Common delta (tab size = 4): cont2 stays two columns deeper than the rest.
  assert.deepStrictEqual(editor.document.lines, [
    '    1. a',
    '    2. b',
    '    cont1',
    '      cont2',
  ]);
});

test('Tab on a multi-marker block shifts one- and two-digit markers by one delta', async () => {
  const editor = editorOn('8. a\n9. b\n10. c\n11. d', 0, 0, 3, 5);
  await onTabKey();
  // All shift by the same delta (tab size); the differing marker widths no
  // longer drift the indentation apart, and markers are not renumbered.
  assert.deepStrictEqual(editor.document.lines, [
    '    8. a',
    '    9. b',
    '    10. c',
    '    11. d',
  ]);
});

test('Shift+Tab on a multi-marker block moves it back, clamped at column 0', async () => {
  const editor = editorOn(
    '    8. a\n    9. b\n    10. c\n    11. d',
    0,
    0,
    3,
    9,
  );
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '8. a',
    '9. b',
    '10. c',
    '11. d',
  ]);
});

test('Tab on a multi-marker block does not renumber the markers', async () => {
  const editor = editorOn('5. a\n9. b', 0, 0, 1, 4); // intentionally non-sequential
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['    5. a', '    9. b']);
});

function withExtraMarkers(markers, fn) {
  return async () => {
    vscode._config['lists.extraMarkers'] = markers;
    vscode._config['lists.extraMarkersEnabled'] = true;
    try {
      await fn();
    } finally {
      delete vscode._config['lists.extraMarkers'];
      delete vscode._config['lists.extraMarkersEnabled'];
    }
  };
}

test(
  'Tab on a custom-marker block shifts by one delta without renumbering',
  withExtraMarkers(['a)'], async () => {
    const editor = editorOn('a) x\nb) y\nzi) z', 0, 0, 2, 5);
    await onTabKey();
    // Different marker widths, one common delta, markers a)/b)/zi) untouched.
    assert.deepStrictEqual(editor.document.lines, [
      '    a) x',
      '    b) y',
      '    zi) z',
    ]);
  }),
);

test('continuationStopRadius bounds the stop-collection window', async () => {
  // A word start at column 2 sits two lines above the target.
  const text = '  near\nq\nw\ntt';
  vscode._config['indent.continuationStopRadius'] = 1;
  let editor = editorOn(text, 3, 2);
  await onTabKey();
  assert.strictEqual(editor.document.lines[3], '    tt'); // col-2 stop out of window -> tab-size 4
  vscode._config['indent.continuationStopRadius'] = 3;
  editor = editorOn(text, 3, 2);
  await onTabKey();
  assert.strictEqual(editor.document.lines[3], '  tt'); // col-2 stop now in window
  delete vscode._config['indent.continuationStopRadius'];
});

test(
  'custom-marker lines are list items, not continuation lines',
  withExtraMarkers(['a)'], async () => {
    // "a) x" is recognized as a list item, so Tab nests it structurally (cycle
    // marker) instead of snapping it to a column stop (which would keep "a)").
    const editor = editorOn('a) x', 0, 0);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, ['   1. x']);
  }),
);
