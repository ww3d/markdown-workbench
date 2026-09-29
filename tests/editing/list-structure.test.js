// List structure: content column, the item enclosing a line, and marker-type
// propagation across siblings.

import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh, MockDocument } from '../helpers/vscode-mock.ts';

const vscode = install();
const editing = await loadFresh('src/editing/index.js');
const { LIST_ITEM_RE } = editing;
const { contentColumn, enclosingListItem, propagateMarkerType } =
  editing._internal;

test('contentColumn measures the text column of every item shape', () => {
  assert.strictEqual(contentColumn(LIST_ITEM_RE.exec('2. ')), 3);
  assert.strictEqual(contentColumn(LIST_ITEM_RE.exec('   - [ ] ')), 9);
  assert.strictEqual(contentColumn(LIST_ITEM_RE.exec('1. - [ ] foo')), 9);
});

test('enclosingListItem returns the item directly when the line is one', () => {
  const doc = new MockDocument('2. foo');
  const item = enclosingListItem(doc, 0);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 3);
});

test('enclosingListItem walks up one continuation line', () => {
  const doc = new MockDocument('2. foo\n   cont');
  const item = enclosingListItem(doc, 1);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 3);
});

test('enclosingListItem walks up several continuation lines', () => {
  const doc = new MockDocument('2. foo\n   cont one\n   cont two');
  const item = enclosingListItem(doc, 2);
  assert.strictEqual(item.line, 0);
});

test('enclosingListItem stops at a too-shallow markerless line', () => {
  const doc = new MockDocument('2. foo\n shallow');
  assert.strictEqual(enclosingListItem(doc, 1), null);
});

test('enclosingListItem stops at a blank line', () => {
  const doc = new MockDocument('2. foo\n\n   orphan');
  assert.strictEqual(enclosingListItem(doc, 2), null);
});

test('enclosingListItem steps over deeper children to the owning item', () => {
  // The continuation line hangs at the parent content column (3); the deeper
  // `1.`/`2.` children (content column 6) sit in between and must be skipped.
  const doc = new MockDocument(
    '3. parent\n   1. child a\n   2. child b\n   more text',
  );
  const item = enclosingListItem(doc, 3);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 3);
});

test('enclosingListItem resolves a whitespace-only hanging line over children', () => {
  // The reproduced @ww3d case: cursor on the empty hanging line at column 6.
  const doc = new MockDocument(
    '   3. tenant test\n      1. kind eins\n      2. kind zwei\n      ich denke\n      noch eine\n      ',
  );
  const item = enclosingListItem(doc, 5);
  assert.strictEqual(item.line, 0);
  assert.strictEqual(item.contentCol, 6);
});

test('enclosingListItem stops at a blank line above the children', () => {
  const doc = new MockDocument('3. parent\n   1. child\n\n   orphan');
  assert.strictEqual(enclosingListItem(doc, 3), null);
});

test('enclosingListItem stops at a markerless line shallower than the start', () => {
  const doc = new MockDocument('3. parent\n   1. child\n shallow\n   here');
  assert.strictEqual(enclosingListItem(doc, 3), null);
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
  'propagateMarkerType pulls siblings to the first item type',
  withExtraMarkers(ALL_EXTRA, () => {
    const doc = new MockDocument('1) x\nb) y\nc) z');
    const ops = [];
    propagateMarkerType(
      doc,
      { replace: (r, t) => ops.push({ kind: 'replace', range: r, text: t }) },
      0,
    );
    doc._apply(ops);
    assert.deepStrictEqual(doc.lines, ['1) x', '2) y', '3) z']);
  }),
);

test(
  'propagateMarkerType never rewrites child levels',
  withExtraMarkers(ALL_EXTRA, () => {
    const doc = new MockDocument('1) x\n   a) child\n   b) child\nb) y');
    const ops = [];
    propagateMarkerType(
      doc,
      { replace: (r, t) => ops.push({ kind: 'replace', range: r, text: t }) },
      0,
    );
    doc._apply(ops);
    assert.deepStrictEqual(doc.lines, [
      '1) x',
      '   a) child',
      '   b) child',
      '2) y',
    ]);
  }),
);
