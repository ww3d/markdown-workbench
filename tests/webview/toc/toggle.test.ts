// TOC clicks: a label navigates, a chevron toggles its branch by hand, and the
// manual state is sticky against the scroll-spy (#48).
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  fireTocClick,
  listenerOf,
  scroll,
  tocFixture,
  topBarsOffsetOf,
} from '../../helpers/webview-fixtures.ts';

test('clicking a TOC entry scrolls to its heading', async () => {
  const r = await startWebview({ scrollY: 0 });
  const heading = { getBoundingClientRect: () => ({ top: 500 }) };
  byId(r, 'content').querySelector = (s) => (s === '#sec' ? heading : null);
  const link = {
    dataset: { idx: '0', id: 'sec' },
    closest: (s: string): unknown => (s === '.toc-link' ? link : null),
  };
  listenerOf(byId(r, 'toc'), 'click')({ target: link, preventDefault() {} });
  assert.strictEqual(r.state.scrolledTo, 500);
});

test('a TOC chevron click toggles the branch (manual), a leaf entry has no branch to toggle', async () => {
  const r = await tocFixture();
  const { tocBranches } = await r.load('toc/tree.ts');
  r.window.scrollY = 1500;
  scroll(r); // active b -> branch 0 expanded (on path)
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
  );
  fireTocClick(r, 0, true); // chevron zone on the parent -> collapse
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    true,
    'chevron collapsed it',
  );
  fireTocClick(r, 0, true); // toggle back -> expand
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
    'chevron expanded it',
  );
  assert.strictEqual(tocBranches[2], null, 'a leaf entry has no branch');
});

test('a manually collapsed TOC branch stays collapsed even on the active path (sticky)', async () => {
  const r = await tocFixture();
  const { tocBranches } = await r.load('toc/tree.ts');
  r.window.scrollY = 1500;
  scroll(r); // active b, branch 0 expanded
  fireTocClick(r, 0, true); // manual collapse
  assert.strictEqual(tocBranches[0]?.classList.contains('toc-collapsed'), true);
  r.window.scrollY = 2500;
  scroll(r); // active c (branch 0 off path)
  r.window.scrollY = 1500;
  scroll(r); // active b again (branch 0 on path)
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    true,
    'the automatic does not re-expand a manually collapsed branch',
  );
});

test('a manually expanded TOC branch stays expanded even off the active path (sticky)', async () => {
  const r = await tocFixture();
  const { tocBranches } = await r.load('toc/tree.ts');
  r.window.scrollY = 2500;
  scroll(r); // active c -> branch 0 collapsed (off path)
  assert.strictEqual(tocBranches[0]?.classList.contains('toc-collapsed'), true);
  fireTocClick(r, 0, true); // manual expand while off path
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
  );
  r.window.scrollY = 1500;
  scroll(r); // active b (branch 0 on path)
  r.window.scrollY = 2500;
  scroll(r); // active c again (branch 0 leaves the path)
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
    'the automatic does not re-collapse a manually expanded branch',
  );
});

test('a re-render resets the sticky manual TOC state', async () => {
  // Re-render at scrollY 0 so the re-collected heading tops are unshifted (the
  // headingEl mock returns viewport-fixed rects). Manually collapse an on-path
  // branch, then a fresh tree drops the manual state and the automatic re-expands.
  // The re-render carries changed HTML: an identical one is now a no-op (idempotent
  // render, #44 P2), so a real content re-render is what rebuilds the tree.
  const r = await tocFixture(); // rendered at scrollY 0 -> active a -> branch 0 expanded
  const { tocBranches } = await r.load('toc/tree.ts');
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
    'auto-expanded on path',
  );
  fireTocClick(r, 0, true); // manually collapse the on-path branch
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    true,
    'manually collapsed',
  );
  r.send({ type: 'render', html: 'y' }); // fresh tree resets the manual state (scrollY still 0)
  assert.strictEqual(
    tocBranches[0]?.classList.contains('toc-collapsed'),
    false,
    'after a re-render the branch follows the automatic again (on path -> expanded)',
  );
});

test('a TOC label click navigates; a chevron click only toggles', async () => {
  const r = await tocFixture();
  r.window.scrollY = 1500;
  scroll(r);
  byId(r, 'content').querySelector = () => ({
    getBoundingClientRect: () => ({ top: 500 }),
  });
  fireTocClick(r, 0, true); // chevron zone -> toggle, no navigation
  assert.strictEqual(
    r.state.scrolledTo,
    null,
    'a chevron click does not navigate',
  );
  r.window.scrollY = 0; // so absTop == the heading's rect top
  fireTocClick(r, 0, false); // label zone -> navigate (below the top bars)
  assert.strictEqual(
    r.state.scrolledTo,
    500 - (await topBarsOffsetOf(r)),
    'a label click navigates to the heading',
  );
});

test('a manual TOC toggle arms the animation flag; the scroll-driven auto path does not (#44 P5)', async () => {
  const r = await tocFixture();
  r.window.scrollY = 1500;
  scroll(r); // active b -> auto expand, no animation
  assert.strictEqual(
    !!r.state.bodyClasses['toc-animating'],
    false,
    'the scroll-driven auto expand does not animate',
  );
  fireTocClick(r, 0, true); // manual toggle -> arm the transition
  assert.strictEqual(
    r.state.bodyClasses['toc-animating'],
    true,
    'a manual toggle animates',
  );
});
