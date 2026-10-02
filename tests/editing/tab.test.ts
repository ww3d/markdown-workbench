// Tab / Shift+Tab: structural list nesting, renumbering and re-lettering.

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
const { indentUnitFor, onTabKey, onShiftTabKey } =
  await loadFresh<typeof import('../../src/editing/tab.ts')>(
    'src/editing/tab.ts',
  );
const { execListItem } = await loadFresh<
  typeof import('../../src/editing/list-markers.ts')
>('src/editing/list-markers.ts');

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

function listItem(text: string) {
  const m = execListItem(text);
  assert.ok(m, text);
  return m;
}

test('indentUnitFor is marker plus gap width', () => {
  assert.strictEqual(indentUnitFor(listItem('- x')).length, 2);
  assert.strictEqual(indentUnitFor(listItem('10. x')).length, 4);
});

test('Tab on a compound item touches only the leading marker', async () => {
  const editor = editorOn('1. - [ ] a\n2. - [ ] b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. - [ ] a',
    '   1. - [ ] b',
  ]);
});

test('Shift+Tab on a compound item touches only the leading marker', async () => {
  const editor = editorOn('1. - [ ] a\n   1. - [ ] b', 1, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. - [ ] a', '2. - [ ] b']);
});

test('Tab nests by the adaptive marker width', async () => {
  const editor = editorOn('- item', 0, 3);
  await onTabKey();
  assert.strictEqual(editor.document.lines[0], '  - item');
});

test('Tab on a markerless line with no stops indents by a tab-size step', async () => {
  const editor = editorOn('plain', 0, 0); // tabSize default 4, no surrounding stops
  await onTabKey();
  assert.strictEqual(editor.document.lines[0], '    plain');
});

test('Shift+Tab un-nests and stops at column zero', async () => {
  const editor = editorOn('  - item', 0, 4);
  await onShiftTabKey();
  assert.strictEqual(editor.document.lines[0], '- item');
  await onShiftTabKey(); // already at zero indent -> outdent fallback
  assert.strictEqual(vscode._executed.at(-1)?.id, 'outdent');
});

test('Tab restarts a numbered item as a new sublist at 1', async () => {
  const editor = editorOn('1. a\n2. b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '   1. b']);
});

test('Tab keeps the paren delimiter on the restarted number', async () => {
  const editor = editorOn('1) a\n2) b', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1) a', '   1) b']);
});

test('Tab closes the gap in the sequence left behind', async () => {
  const editor = editorOn('1. a\n2. b\n3. c', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. a', '   1. b', '2. c']);
});

test('Tab gap-closing skips children of the tabbed item', async () => {
  const editor = editorOn('1. a\n2. b\n   1. bb\n3. c', 1, 0);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a',
    '   1. b',
    '   1. bb',
    '2. c',
  ]);
});

test('Tab on a multi-line selection moves the block by a common delta, numbers untouched', async () => {
  const editor = editorOn('1. a\n2. b', 0, 0, 1, 4);
  await onTabKey();
  // Both shift by the same delta (tab size), markers unchanged.
  assert.deepStrictEqual(editor.document.lines, ['    1. a', '    2. b']);
});

test('Shift+Tab joins the target sequence and renumbers both sequences', async () => {
  const editor = editorOn('1. a\n   1. x\n   2. y\n   3. z\n2. b', 1, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a',
    '2. x',
    '   1. y',
    '   2. z',
    '3. b',
  ]);
});

test('Shift+Tab without a preceding target-level sibling starts at 1', async () => {
  const editor = editorOn('   3. only', 0, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, ['1. only']);
});

test('Shift+Tab leaves dash markers and sibling numbers untouched', async () => {
  // Outdent by the dash's own unit (2), marker unrewritten, no renumbering.
  const editor = editorOn('1. parent\n   - dash\n2. next', 1, 3);
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. parent',
    ' - dash',
    '2. next',
  ]);
});

test('Tab into a populated deeper level joins its sequence instead of duplicating', async () => {
  // zwei 1 already sits one level deeper; tabbing zwei 2 in must continue the
  // sequence (-> 2.), not restart at 1 and leave a `1.`/`1.` pair. The level
  // left behind closes its gap.
  const editor = editorOn(
    '1. eins\n2. zwei\n      1. zwei 1\n   1. zwei 2\n   2. zwei 3',
    3,
    3,
  );
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. eins',
    '2. zwei',
    '      1. zwei 1',
    '      2. zwei 2',
    '   1. zwei 3',
  ]);
});

test('Tab joining a deeper sequence counts past nine into two digits', async () => {
  const nine = Array.from({ length: 9 }, (_, i) => `      ${i + 1}. d${i + 1}`);
  const editor = editorOn(`1. p\n${nine.join('\n')}\n   1. x\n   2. y`, 10, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. p',
    ...nine,
    '      10. x',
    '   1. y',
  ]);
});

test('Tab on the first child nests it and closes the gap left behind (Fall B)', async () => {
  const editor = editorOn(
    '1. eins\n2. zwei\n   1. zwei 1\n   2. zwei 2\n   3. zwei 3',
    2,
    3,
  );
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. eins',
    '2. zwei',
    '      1. zwei 1',
    '   1. zwei 2',
    '   2. zwei 3',
  ]);
});

test('Shift+Tab on the first child renumbers both levels (Fall A)', async () => {
  const editor = editorOn(
    '1. eins\n2. zwei\n   1. zwei 1\n   2. zwei 2\n   3. zwei 3',
    2,
    3,
  );
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. eins',
    '2. zwei',
    '3. zwei 1',
    '   1. zwei 2',
    '   2. zwei 3',
  ]);
});

test('Shift+Tab out of a deeper level joins a populated parent across three levels', async () => {
  // Level 3 item moves up into the populated level 2 sequence; the level it
  // leaves closes its gap, the level it joins continues after it.
  const editor = editorOn(
    '1. a\n   1. b\n      1. p\n      2. q\n   2. c',
    2,
    6,
  );
  await onShiftTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a',
    '   1. b',
    '   2. p',
    '      1. q',
    '   3. c',
  ]);
});

test('Tab joining a deeper level keeps the paren delimiter', async () => {
  const editor = editorOn('1) p\n      1) x\n   1) y', 2, 3);
  await onTabKey();
  assert.deepStrictEqual(editor.document.lines, [
    '1) p',
    '      1) x',
    '      2) y',
  ]);
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

function withExtraMarkers(markers: string[], fn: () => void | Promise<void>) {
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
  'Tab nests a custom item with the markerCycle marker for the depth',
  withExtraMarkers(ALL_EXTRA, async () => {
    // Default markerCycle ["1.","a)","1)","a."]; depth 1 -> "a)".
    const editor = editorOn('a) parent\nb) child', 1, 0);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, ['a) parent', '   a) child']);
  }),
);

test(
  'Tab nests a numbered item by the cycle when custom markers are active',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('1. parent\n2. child', 1, 0);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, ['1. parent', '   a) child']);
  }),
);

test(
  'Tab follows markerCycle to the second depth',
  withExtraMarkers(ALL_EXTRA, async () => {
    // depth 2 -> "1)".
    const editor = editorOn('1. p\n   a) q\n   b) r', 2, 3);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, [
      '1. p',
      '   a) q',
      '      1) r',
    ]);
  }),
);

test(
  'Tab joins an existing deeper custom sequence',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('x) p\n   a) first\nb) second', 2, 0);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, [
      'x) p',
      '   a) first',
      '   b) second',
    ]);
  }),
);

test(
  'Tab on a symbol item keeps its bullet, only indents',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn('-> x', 0, 0);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, ['   -> x']);
  }),
);

test(
  'Tab on a custom item renumbers the sequence left behind',
  withExtraMarkers(ALL_EXTRA, async () => {
    // a) b) c) d) at one level; Tab on c) -> left behind a) b) c) (d -> c).
    const editor = editorOn('a) one\nb) two\nc) three\nd) four', 2, 0);
    await onTabKey();
    assert.deepStrictEqual(editor.document.lines, [
      'a) one',
      'b) two',
      '   a) three',
      'c) four',
    ]);
  }),
);

test(
  'Shift+Tab joins a parent custom sequence',
  withExtraMarkers(ALL_EXTRA, async () => {
    const editor = editorOn(
      'a) parent\n   a) child\n      1) childchild',
      2,
      6,
    );
    await onShiftTabKey();
    assert.deepStrictEqual(editor.document.lines, [
      'a) parent',
      '   a) child',
      '   b) childchild',
    ]);
  }),
);

test(
  'Shift+Tab closes a custom letter gap seamlessly',
  withExtraMarkers(ALL_EXTRA, async () => {
    // Outdent the first child; the remaining children re-letter a) b).
    const editor = editorOn('a) parent\n   a) x\n   b) y\n   c) z', 1, 3);
    await onShiftTabKey();
    assert.deepStrictEqual(editor.document.lines, [
      'a) parent',
      'b) x',
      '   a) y',
      '   b) z',
    ]);
  }),
);
