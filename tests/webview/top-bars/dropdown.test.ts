// The breadcrumb's sibling picker (#33): the pure sibling logic and the segment,
// picker, Escape and outside-click interaction. The dropdown rendering needs a real
// webview and is verified manually.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  globalListener,
  headingEl,
  keydown,
  listenerOf,
  segTarget,
  topBarsOffsetOf,
  topConfig,
  withActiveChain,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

test('siblingHeadings: same-level headings under the same parent, in order', async () => {
  const r = await startWebview();
  const { siblingHeadings } = await r.load('top-bars/dropdown.ts');
  // h1, h2, h2, h2 -> the three h2 are siblings of each other.
  assert.deepStrictEqual(siblingHeadings([1, 2, 2, 2], 2), [1, 2, 3]);
  // The h1 is the only root -> just itself.
  assert.deepStrictEqual(siblingHeadings([1, 2, 2, 2], 0), [0]);
});

test('siblingHeadings: a deeper heading between siblings (child of a sibling) is skipped', async () => {
  const r = await startWebview();
  const { siblingHeadings } = await r.load('top-bars/dropdown.ts');
  // h1, h2, h3, h2: the two h2 are siblings; the h3 (child of the first h2) is
  // skipped, not a boundary.
  assert.deepStrictEqual(siblingHeadings([1, 2, 3, 2], 1), [1, 3]);
  assert.deepStrictEqual(siblingHeadings([1, 2, 3, 2], 3), [1, 3]);
});

test('siblingHeadings: a shallower heading is the parent boundary', async () => {
  const r = await startWebview();
  const { siblingHeadings } = await r.load('top-bars/dropdown.ts');
  // h2, h1, h2: the leading h2 belongs to a different parent (the h1 boundary
  // sits between it and the trailing h2), so it is not a sibling.
  assert.deepStrictEqual(siblingHeadings([2, 1, 2], 2), [2]);
});

test('siblingHeadings: a level jump (h1 -> h4) groups the h4 with its bounded run', async () => {
  const r = await startWebview();
  const { siblingHeadings } = await r.load('top-bars/dropdown.ts');
  // h1, h4, h4, h2, h4: siblings of index 1 are the two h4 directly under the
  // h1 (bounded by the h2), not the trailing h4 in the h2 section.
  assert.deepStrictEqual(siblingHeadings([1, 4, 4, 2, 4], 1), [1, 2]);
  assert.deepStrictEqual(siblingHeadings([1, 4, 4, 2, 4], 4), [4]);
});

test('siblingHeadings: single child and the inactive (-1) case', async () => {
  const r = await startWebview();
  const { siblingHeadings } = await r.load('top-bars/dropdown.ts');
  assert.deepStrictEqual(siblingHeadings([1, 2], 1), [1]); // only child
  assert.deepStrictEqual(siblingHeadings([1, 2, 3], -1), []); // active = -1
  assert.deepStrictEqual(siblingHeadings([], 0), []); // no headings
});

test('above the first heading the breadcrumb root segment scrolls to the top, no picker', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' }); // scrollY 0 -> active = -1 -> root segment
  assert.strictEqual(
    r.state.bodyClasses['has-breadcrumb'],
    true,
    'the bar is present, not empty',
  );
  // The root segment carries the sentinel index -1.
  listenerOf(
    byId(r, 'breadcrumb'),
    'click',
  )({
    target: segTarget(-1, '#', '.breadcrumb-seg'),
    preventDefault() {},
  });
  assert.strictEqual(r.state.scrolledTo, 0, 'root scrolls to the top');
  assert.strictEqual(
    !!r.state.bodyClasses['breadcrumb-dropdown-open'],
    false,
    'no sibling picker for root',
  );
});

test('a breadcrumb segment scrolls to its heading and opens the sibling picker', async () => {
  const r = await withActiveChain([
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  byId(r, 'content').querySelector = (s) =>
    s === '#a' ? { getBoundingClientRect: () => ({ top: 100 }) } : null;
  listenerOf(
    byId(r, 'breadcrumb'),
    'click',
  )({
    target: segTarget(0, '#a', '.breadcrumb-seg'),
    preventDefault() {},
  });
  assert.strictEqual(
    r.state.scrolledTo,
    100 - (await topBarsOffsetOf(r)),
    'scrolled to the segment heading, below the bars',
  );
  assert.strictEqual(
    r.state.bodyClasses['breadcrumb-dropdown-open'],
    true,
    'picker opened',
  );
});

test('Escape closes the open sibling picker before clearing the selection', async () => {
  const r = await withActiveChain([
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  byId(r, 'content').querySelector = () => ({
    getBoundingClientRect: () => ({ top: 0 }),
  });
  listenerOf(
    byId(r, 'breadcrumb'),
    'click',
  )({
    target: segTarget(1, '#b', '.breadcrumb-seg'),
    preventDefault() {},
  });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true);
  keydown(r, 'Escape');
  assert.strictEqual(
    r.state.bodyClasses['breadcrumb-dropdown-open'],
    false,
    'Escape closed the picker',
  );
});

test('a click outside the breadcrumb and its picker closes the picker', async () => {
  const r = await withActiveChain([headingEl('h1', 'a', 'A', 100)]);
  byId(r, 'content').querySelector = () => ({
    getBoundingClientRect: () => ({ top: 0 }),
  });
  listenerOf(
    byId(r, 'breadcrumb'),
    'click',
  )({
    target: segTarget(0, '#a', '.breadcrumb-seg'),
    preventDefault() {},
  });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true);
  // An outside click: the target belongs to neither the dropdown nor a segment.
  globalListener(r, 'document', 'click')({ target: { closest: () => null } });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], false);
});

test('choosing a sibling from the picker navigates and closes it', async () => {
  const r = await withActiveChain([
    headingEl('h1', 'a', 'A', 100),
    headingEl('h1', 'c', 'C', 300),
  ]);
  byId(r, 'content').querySelector = (s) =>
    s === '#c' ? { getBoundingClientRect: () => ({ top: 300 }) } : null;
  listenerOf(
    byId(r, 'breadcrumb'),
    'click',
  )({
    target: segTarget(0, '#a', '.breadcrumb-seg'),
    preventDefault() {},
  });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true);
  listenerOf(
    byId(r, 'breadcrumb-dropdown'),
    'click',
  )({
    target: segTarget(1, '#c', '.breadcrumb-option'),
    preventDefault() {},
  });
  assert.strictEqual(
    r.state.scrolledTo,
    300 - (await topBarsOffsetOf(r)),
    'navigated to the chosen sibling',
  );
  assert.strictEqual(
    r.state.bodyClasses['breadcrumb-dropdown-open'],
    false,
    'picker closed',
  );
});
