// Enter / Shift+Enter: list continuation, code-fence auto-close and hanging
// continuation lines.

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
const { FENCE_RE, fenceIsUnclosed, onEnterKey, onShiftEnterKey } =
  editing._internal;

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

test('FENCE_RE matches backtick and tilde fences with language info', () => {
  assert.ok(FENCE_RE.test('```'));
  assert.ok(FENCE_RE.test('  ~~~~powershell'));
  assert.ok(!FENCE_RE.test('``inline``'));
});

test('fenceIsUnclosed pairs later delimiters', () => {
  const open = new MockDocument('```js\ncode');
  assert.strictEqual(fenceIsUnclosed(open, 0), true);
  const closed = new MockDocument('```js\ncode\n```');
  assert.strictEqual(fenceIsUnclosed(closed, 0), false);
});

test('Enter continues a bullet task item with a fresh checkbox', async () => {
  const editor = editorOn('- [x] done', 0, 10);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '- [ ] ');
});

test('Enter increments numbered items', async () => {
  const editor = editorOn('3. item', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '4. ');
});

test('Enter keeps the paren delimiter', async () => {
  const editor = editorOn('3) item', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '4) ');
});

test('Enter continues a numbered task item with a fresh checkbox', async () => {
  const editor = editorOn('1. [x] done', 0, 11);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '2. [ ] ');
});

test('Enter increments into two digits', async () => {
  const editor = editorOn('9. nine', 0, 7);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '10. ');
});

test('Enter on an empty numbered item removes the marker', async () => {
  const editor = editorOn('1. ', 0, 3);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[0], '');
});

test('Enter mid-sequence renumbers the following siblings', async () => {
  const editor = editorOn('1. a\n2. b\n3. c', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a',
    '2. ',
    '3. b',
    '4. c',
  ]);
});

test('Enter renumbering skips children and stops at a type change', async () => {
  const editor = editorOn('1. a\n   1. aa\n2. b\n- dash', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a',
    '2. ',
    '   1. aa',
    '3. b',
    '- dash',
  ]);
});

test('Enter continues a compound task item with a fresh box', async () => {
  const editor = editorOn('1. - [ ] asd', 0, 12);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '2. - [ ] ');
});

test('Enter keeps the paren delimiter on a compound task item', async () => {
  const editor = editorOn('1) - [x] asd', 0, 12);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '2) - [ ] ');
});

test('Enter on a dash-led compound never increments the inner number', async () => {
  const editor = editorOn('- 1. [ ] x', 0, 10);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[1], '- 1. [ ] ');
});

test('Enter on an empty compound item removes the whole marker', async () => {
  const editor = editorOn('2. - [ ] ', 0, 9);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[0], '');
});

test('Enter mid-sequence renumbers across compound siblings', async () => {
  const editor = editorOn('1. - [ ] a\n2. - [ ] b', 0, 10);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. - [ ] a',
    '2. - [ ] ',
    '3. - [ ] b',
  ]);
});

test('Enter renumbering stops at a delimiter change', async () => {
  const editor = editorOn('1. a\n1) other', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '2. ', '1) other']);
});

test('Enter on an empty item removes the marker (list termination)', async () => {
  const editor = editorOn('- [ ] ', 0, 6);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[0], '');
});

test('Enter inside the marker falls back to default newline', async () => {
  editorOn('- [ ] text', 0, 2);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

test('Enter on a non-list line falls back', async () => {
  editorOn('plain', 0, 5);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

test('Enter at the end of an unclosed fence inserts the closing fence as an unindented snippet', async () => {
  const editor = editorOn('```js', 0, 5);
  await onEnterKey();
  assert.strictEqual(editor.insertedSnippets.length, 1);
  // No indentation in the snippet: VS Code auto-indents continuation lines.
  assert.strictEqual(editor.insertedSnippets[0].snippet.value, '\n$0\n```');
});

test('Enter on an already-paired fence falls back', async () => {
  editorOn('```js\nx\n```', 0, 5);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0]?.id, 'default:type');
});

test('Enter on a dash item under a numbered parent continues the dash', async () => {
  const editor = editorOn('1. parent\n   - dash', 1, 9);
  await onEnterKey();
  assert.strictEqual(editor.document.lines[2], '   - ');
});

test('Shift+Enter on a numbered item hangs at the content column', async () => {
  const editor = editorOn('2. ', 0, 3);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. ', '   ']);
});

test('Shift+Enter on a nested task item hangs at column nine', async () => {
  const editor = editorOn('   - [ ] ', 0, 9);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['   - [ ] ', '         ']);
});

test('Shift+Enter on a compound item hangs at the compound content column', async () => {
  const editor = editorOn('1. - [ ] ', 0, 9);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['1. - [ ] ', '         ']);
});

test('Shift+Enter splits the line, rest text moves to the hanging line', async () => {
  const editor = editorOn('2. foobar', 0, 5);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. fo', '   obar']);
});

test('Shift+Enter on a continuation line hangs at the same column, no marker', async () => {
  const editor = editorOn('2. foo\n   cont', 1, 5);
  await onShiftEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['2. foo', '   co', '   nt']);
});

test('Shift+Enter outside a list falls back to the default newline', async () => {
  editorOn('plain', 0, 5);
  await onShiftEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

test('Enter on a continuation line opens the next numbered sibling', async () => {
  const editor = editorOn('2. foo\n   buttons rechts\n3. bar', 1, 17);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '2. foo',
    '   buttons rechts',
    '3. ',
    '4. bar',
  ]);
});

test('Enter on a continuation line of a bullet repeats the bullet', async () => {
  const editor = editorOn('- foo\n  cont', 1, 6);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, ['- foo', '  cont', '- ']);
});

test('renumber skips a wrapped continuation line mid-sequence', async () => {
  const editor = editorOn('1. a\n2. b\n   wrapped\n3. c', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a',
    '2. ',
    '3. b',
    '   wrapped',
    '4. c',
  ]);
});

test('Enter on a continuation line over children opens the next parent sibling', async () => {
  // Cursor on the markerless continuation line of `3.`, with deeper `1.`/`2.`
  // children in between. Enter must continue `3.` -> `4.`, not fall back.
  const editor = editorOn(
    '3. parent\n   1. child a\n   2. child b\n   more text',
    3,
    12,
  );
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '3. parent',
    '   1. child a',
    '   2. child b',
    '   more text',
    '4. ',
  ]);
});

test('Enter on an empty hanging line over children opens the next parent sibling', async () => {
  // The reproduced @ww3d case: empty hanging line at column 6 over the children
  // of `   3.`. Enter creates `   4.` at column 3.
  const editor = editorOn(
    '   3. tenant\n      1. kind eins\n      2. kind zwei\n      ich denke\n      noch eine\n      ',
    5,
    6,
  );
  await onEnterKey();
  assert.strictEqual(editor.document.lines[6], '   4. ');
});

test('Enter on a continuation line under a blank line falls back', async () => {
  editorOn('3. parent\n   1. child\n\n   orphan', 3, 9);
  await onEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

test('renumber steps over a continuation across a one-/two-digit transition', async () => {
  // The continuation under 10. still hangs at column 3 (it was written under a
  // single-digit marker); the seed - the trigger item's content column - is a
  // stable floor, so the run does not break at the wider 10. marker.
  const editor = editorOn('9. i\n10. j\n   cont\n11. k', 0, 4);
  await onEnterKey();
  assert.deepStrictEqual(editor.document.lines, [
    '9. i',
    '10. ',
    '11. j',
    '   cont',
    '12. k',
  ]);
});

test('Shift+Enter with the cursor inside the marker falls back to default', async () => {
  editorOn('2. foo', 0, 1);
  await onShiftEnterKey();
  assert.strictEqual(vscode._executed[0].id, 'default:type');
});

const ALL_EXTRA = [
  '->',
  '→',
  '❯',
  'a)',
  'A)',
  'a.',
  'A.',
  '1)',
  'a:',
  'A:',
  '1:',
];

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
  'Enter counts up a lettered custom item',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('a) one', 0, 6);
    await onEnterKey();
    assert.strictEqual(editor.document.lines[1], 'b) ');
  }),
);

test(
  'Enter rolls a lettered item past z into za',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('z) last', 0, 7);
    await onEnterKey();
    assert.strictEqual(editor.document.lines[1], 'za) ');
  }),
);

test(
  'Enter keeps the delimiter on a colon-delimited custom item',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('a: one', 0, 6);
    await onEnterKey();
    assert.strictEqual(editor.document.lines[1], 'b: ');
  }),
);

test(
  'Enter repeats a symbol bullet without a sequence',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('-> bullet', 0, 9);
    await onEnterKey();
    assert.strictEqual(editor.document.lines[1], '-> ');
  }),
);

test(
  'Enter counts up a colon-delimited numeric custom item',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('1: one', 0, 6);
    await onEnterKey();
    assert.strictEqual(editor.document.lines[1], '2: ');
  }),
);

test(
  'Renumbering a custom item preserves a multi-space gap',
  withExtraMarkers(ALL_EXTRA, async () => {
    // The second item has two spaces after the marker. Enter on a) inserts b),
    // and the following b) re-letters to c) while its two-space gap is kept
    // (only the marker token is rewritten).
    const editor = editorOn('a) one\nb)  two', 0, 6);
    await onEnterKey();
    assert.deepStrictEqual(editor.document.lines, ['a) one', 'b) ', 'c)  two']);
  }),
);
