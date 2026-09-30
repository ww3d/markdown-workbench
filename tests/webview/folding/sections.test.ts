// Content section folding (#44 P2): the pure section logic and the fold mask.
import { test } from 'node:test';
import assert from 'node:assert';
import { nth } from '../../helpers/nth.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import { byId, renderFoldDom } from '../../helpers/webview-fixtures.ts';

/** The fold mask check, driven with mock nodes (not DOM elements). */
interface SectionsView {
  isInHiddenBlock(el: object): boolean;
}

test('computeFoldHidden hides a folded section and respects nesting (#44 P2)', async () => {
  const r = await startWebview();
  const { computeFoldHidden } = await r.load('folding/sections.ts');
  const blocks = [
    { level: 1, id: 'a' },
    { level: 0, id: '' }, // h1 a, p
    { level: 2, id: 'b' },
    { level: 0, id: '' }, // h2 b (under a), p
    { level: 1, id: 'c' },
    { level: 0, id: '' }, // h1 c, p
  ];
  assert.deepStrictEqual(
    computeFoldHidden(blocks, new Set(['b'])),
    [false, false, false, true, false, false],
    'folding b hides only its own block',
  );
  assert.deepStrictEqual(
    computeFoldHidden(blocks, new Set(['a'])),
    [false, true, true, true, false, false],
    'folding a hides its whole section incl. the nested h2',
  );
  assert.deepStrictEqual(
    computeFoldHidden(blocks, new Set(['a', 'b'])),
    [false, true, true, true, false, false],
    'a already hides b, so the extra fold changes nothing',
  );
  assert.deepStrictEqual(
    computeFoldHidden(blocks, new Set()),
    [false, false, false, false, false, false],
    'nothing folded -> nothing hidden',
  );
});

test('isFoldable: a heading is foldable iff its section is non-empty (#44 P2)', async () => {
  const r = await startWebview();
  const { isFoldable } = await r.load('folding/sections.ts');
  const blocks = [
    { level: 1, id: 'a' },
    { level: 0, id: '' }, // 0 h1 a (has a p) -> foldable
    { level: 2, id: 'b' }, // 2 h2 b, immediately followed by h1 -> empty
    { level: 1, id: 'c' }, // 3 h1 c, last -> empty
  ];
  assert.strictEqual(
    isFoldable(blocks, 0),
    true,
    'h1 with a following paragraph',
  );
  assert.strictEqual(
    isFoldable(blocks, 2),
    false,
    'h2 immediately followed by an h1',
  );
  assert.strictEqual(isFoldable(blocks, 3), false, 'the last block');
});

test('visibleFoldAnchor redirects a folded-away heading to its collapsed section header (#44 P2)', async () => {
  // Navigating (TOC / breadcrumb / sticky) to a heading inside a folded section
  // must land on the collapsed section header, not on the display:none target
  // (whose 0-rect walked the view upward on every click).
  const r = await startWebview();
  const { visibleFoldAnchor, foldedIds } = await r.load('folding/sections.ts');
  const block = (tag: string, id: string) => ({ tagName: tag, id });
  byId(r, 'content').children = [
    block('H1', 'a'),
    block('P', ''),
    block('H2', 'b'),
    block('P', ''), // b is under a
    block('H3', 'c'),
    block('P', ''), // c is under b
  ];
  assert.strictEqual(
    visibleFoldAnchor('c'),
    'c',
    'nothing folded -> the id resolves to itself',
  );
  foldedIds.add('b');
  assert.strictEqual(
    visibleFoldAnchor('c'),
    'b',
    'a folded child lands on the collapsed parent',
  );
  assert.strictEqual(
    visibleFoldAnchor('b'),
    'b',
    'the folded heading itself stays the target',
  );
  foldedIds.add('a');
  assert.strictEqual(
    visibleFoldAnchor('c'),
    'a',
    'nested folds collapse to the outermost visible ancestor',
  );
  assert.strictEqual(
    visibleFoldAnchor('b'),
    'a',
    'a hidden folded heading itself redirects further up',
  );
  assert.strictEqual(
    visibleFoldAnchor('a'),
    'a',
    'the outermost folded heading is visible',
  );
  assert.strictEqual(
    visibleFoldAnchor('nope'),
    'nope',
    'a non-heading id is returned unchanged',
  );
});

test('the scroll-spy fold mask covers a nested heading without a layout read (#44 P2 perf)', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { toggleFold } = await r.load('folding/fold.ts');
  const sections: SectionsView = await r.load('folding/sections.ts');
  const { blocks } = renderFoldDom(r);
  const nested = { parentElement: nth(blocks, 3) }; // a heading inside a folded-away block
  assert.strictEqual(
    sections.isInHiddenBlock(nested),
    false,
    'nothing folded -> visible',
  );
  toggleFold('b');
  assert.strictEqual(
    sections.isInHiddenBlock(nested),
    true,
    'inside a folded section -> hidden, resolved through its ancestors',
  );
  assert.strictEqual(
    sections.isInHiddenBlock(nth(blocks, 2)),
    false,
    'the folded heading itself stays visible (it carries the collapsed chevron)',
  );
  assert.strictEqual(
    nth(blocks, 3).offsetParentReads,
    0,
    'derived from the fold set, not from layout',
  );
});
