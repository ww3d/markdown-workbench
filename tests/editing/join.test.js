// Ctrl+Delete / Ctrl+Backspace: join content lines across whitespace.

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
const editing = await loadFresh('src/editing/index.js');
const { joinForwardOrFallback, joinBackwardOrFallback } = editing._internal;

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

function withConfig(cfg, fn) {
  return async () => {
    Object.assign(vscode._config, cfg);
    try {
      await fn();
    } finally {
      for (const k of Object.keys(cfg)) delete vscode._config[k];
    }
  };
}

test('joinForward merges the next content line with one space', async () => {
  const editor = editorOn('- item one\n  zusaetzlich noch was', 0, 10);
  await joinForwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, [
    '- item one zusaetzlich noch was',
  ]);
});

test(
  'joinForward with joinSpaces 0 joins with no space',
  withConfig({ 'editing.joinSpaces': 0 }, async () => {
    const editor = editorOn('left\n    right', 0, 4);
    await joinForwardOrFallback();
    assert.deepStrictEqual(editor.document.lines, ['leftright']);
  }),
);

test(
  'joinForward with joinSpaces 2 joins with two spaces',
  withConfig({ 'editing.joinSpaces': 2 }, async () => {
    const editor = editorOn('left\n    right', 0, 4);
    await joinForwardOrFallback();
    assert.deepStrictEqual(editor.document.lines, ['left  right']);
  }),
);

test(
  'joinForward clamps a negative joinSpaces to zero',
  withConfig({ 'editing.joinSpaces': -3 }, async () => {
    const editor = editorOn('left\n  right', 0, 4);
    await joinForwardOrFallback();
    assert.deepStrictEqual(editor.document.lines, ['leftright']);
  }),
);

test('joinForward removes blank and whitespace-only lines in between', async () => {
  const editor = editorOn('a\n\n   \n\t\n  b', 0, 1);
  await joinForwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, ['a b']);
});

test('joinForward pulls up a flush-left paragraph line too', async () => {
  const editor = editorOn('first\nsecond', 0, 5);
  await joinForwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, ['first second']);
});

test('joinForward normalizes the seam to exactly joinSpaces, no double space', async () => {
  const editor = editorOn('abc   \n    def', 0, 6); // cursor among trailing spaces
  await joinForwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, ['abc def']);
});

test(
  'joinForward mid-line runs the configured fallback command',
  withConfig(
    { 'editing.forwardJoin.fallbackCommand': 'custom.fwd' },
    async () => {
      editorOn('- item one\n  cont', 0, 5);
      await joinForwardOrFallback();
      assert.strictEqual(vscode._executed[0].id, 'custom.fwd');
    },
  ),
);

test('joinForward with no following content line falls back', async () => {
  editorOn('a\n\n   ', 0, 1);
  await joinForwardOrFallback();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordRight');
});

test('joinBackward appends the line to the previous content line', async () => {
  const editor = editorOn('prev\n\n  cur', 2, 2); // cursor at first non-whitespace
  await joinBackwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, ['prev cur']);
});

test(
  'joinBackward normalizes the seam and reads joinSpaces',
  withConfig({ 'editing.joinSpaces': 0 }, async () => {
    const editor = editorOn('prev   \n   cur', 1, 3);
    await joinBackwardOrFallback();
    assert.deepStrictEqual(editor.document.lines, ['prevcur']);
  }),
);

test('joinBackward with only blank lines above falls back', async () => {
  editorOn('\n\ncur', 2, 0);
  await joinBackwardOrFallback();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordLeft');
});

test(
  'joinBackward mid-line runs the configured fallback command',
  withConfig(
    { 'editing.backwardJoin.fallbackCommand': 'custom.bwd' },
    async () => {
      editorOn('prev\ncur', 1, 2);
      await joinBackwardOrFallback();
      assert.strictEqual(vscode._executed[0].id, 'custom.bwd');
    },
  ),
);

test('joinForward on an empty line pulls up the next content without a leading space', async () => {
  // Cursor on the empty middle line; blank lines below collapse, lines above stay.
  const editor = editorOn(
    '1. a dadasdasdasdasda s\n\n\n\n\n\n6. dasdssdAASDASD',
    3,
    0,
  );
  await joinForwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a dadasdasdasdasda s',
    '',
    '',
    '6. dasdssdAASDASD',
  ]);
});

test('joinBackward on an empty line moves to the end of the previous content', async () => {
  const editor = editorOn(
    '1. a dadasdasdasdasda s\n\n\n\n\n\n6. dasdssdAASDASD',
    3,
    0,
  );
  await joinBackwardOrFallback();
  assert.deepStrictEqual(editor.document.lines, [
    '1. a dadasdasdasdasda s',
    '',
    '',
    '6. dasdssdAASDASD',
  ]);
  assert.strictEqual(editor.selection.active.line, 0);
  assert.strictEqual(
    editor.selection.active.character,
    '1. a dadasdasdasdasda s'.length,
  );
});

test('joinForward on an empty line with only blanks below falls back', async () => {
  editorOn('x\n\n\n', 1, 0);
  await joinForwardOrFallback();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordRight');
});

test('joinBackward on an empty line with only blanks above falls back', async () => {
  editorOn('\n\nx', 1, 0);
  await joinBackwardOrFallback();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordLeft');
});

test('join commands fall back on a non-empty selection', async () => {
  editorOn('left\n  right', 0, 0, 0, 4); // a real selection
  await joinForwardOrFallback();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordRight');
  editorOn('left\n  right', 1, 2, 1, 5);
  await joinBackwardOrFallback();
  assert.strictEqual(vscode._executed[0].id, 'deleteWordLeft');
});

test(
  'both directions read joinSpaces from the same setting',
  withConfig({ 'editing.joinSpaces': 3 }, async () => {
    let editor = editorOn('left\n    right', 0, 4);
    await joinForwardOrFallback();
    assert.deepStrictEqual(editor.document.lines, ['left   right']);
    editor = editorOn('prev\n   cur', 1, 3);
    await joinBackwardOrFallback();
    assert.deepStrictEqual(editor.document.lines, ['prev   cur']);
  }),
);
