// The scroll-spy (#32 base): the pure activation decision and the active heading
// across scroll positions, bar insets and folds.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  headingEl,
  MM,
  scroll,
  tocCfg,
  topConfig,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

test('activeHeadingIndex: the last heading scrolled past the activation line', async () => {
  const r = await startWebview();
  const { activeHeadingIndex } = await r.load('scroll-spy/spy.ts');
  const tops = [0, 1000, 2000];
  assert.strictEqual(activeHeadingIndex(tops, 0, 8), 0); // h1 sits at the top
  assert.strictEqual(activeHeadingIndex(tops, 1500, 8), 1); // past the 2nd
  assert.strictEqual(activeHeadingIndex(tops, 5000, 8), 2); // past the last
});

test('activeHeadingIndex: -1 while the reader is above the first heading', async () => {
  const r = await startWebview();
  const { activeHeadingIndex } = await r.load('scroll-spy/spy.ts');
  assert.strictEqual(activeHeadingIndex([50, 100], 0, 8), -1); // prose before h1
  assert.strictEqual(activeHeadingIndex([], 0, 8), -1); // no headings
});

test('activeHeadingIndex: a folded-away heading is skipped, its zero top ignored (#44 P2)', async () => {
  const r = await startWebview();
  const { activeHeadingIndex } = await r.load('scroll-spy/spy.ts');
  // Heading 1 is folded away (hidden), so it carries a bogus top 0. Without the
  // mask its 0 <= line would flip the scan; with it, the reader past 2500 is under
  // heading 2, not the hidden heading 1.
  const tops = [0, 0, 2000];
  const hidden = [false, true, false];
  assert.strictEqual(
    activeHeadingIndex(tops, 2500, 8, null, hidden),
    2,
    'skips the hidden one, picks h3',
  );
  assert.strictEqual(
    activeHeadingIndex(tops, 500, 8, null, hidden),
    0,
    'still under the visible h1',
  );
  // Without the mask the bogus top would make the hidden heading a candidate.
  assert.strictEqual(
    activeHeadingIndex(tops, 500, 8, null, null),
    1,
    'no mask -> bogus top wins',
  );
});

test('the scroll-spy tracks the active heading across scroll positions', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { scrollSpy } = await r.load('scroll-spy/spy.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h1', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000),
  ]);
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    toc: tocCfg({ mode: 'rail' }),
  });
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(scrollSpy.active, 0);
  r.window.scrollY = 1500;
  scroll(r);
  assert.strictEqual(scrollSpy.active, 1);
  r.window.scrollY = 5000;
  scroll(r);
  assert.strictEqual(scrollSpy.active, 2);
});

test('the scroll-spy activation line sits below the top-bar inset (TOC-click marking)', async () => {
  // Regression for the off-by-one the owner saw: navigateToHash lands a target
  // at scrollY + topBarsOffset, so the activation line must include that inset,
  // else the heading above stays marked active.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { scrollSpy } = await r.load('scroll-spy/spy.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h1', 'b', 'B', 1000),
  ]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  // b (top 1000) lands 30px below the viewport top - above the bare 8px line but
  // below a 50px bar stack. With the inset it is active; without it, 'a' would be.
  scrollSpy.setTopInset(50);
  r.window.scrollY = 970;
  scroll(r);
  assert.strictEqual(
    scrollSpy.active,
    1,
    'the heading below the bars is active, not the one above',
  );
});

test('a #id jump to a deep heading marks that heading, not its parent, even from the top (#44)', async () => {
  // The in-document TOC lives at the top, so the active heading before the click is
  // -1 and the global inset is 0. A per-heading activation line is what makes the
  // landed heading active regardless of that stale global inset: the native jump
  // lands a deep h3 at its own bars (28 + 3*22 = 94) below the top, and the flat
  // 8px line would fall 86px above it - the h2 parent would stay marked.
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const { scrollSpy } = await r.load('scroll-spy/spy.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
    headingEl('h3', 'c', 'C', 3000),
  ]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 3000 - (28 + 3 * 22); // where the native #id jump lands c (its scroll-margin)
  scroll(r);
  assert.strictEqual(
    scrollSpy.active,
    2,
    'the clicked h3 is active, not its h2 parent',
  );
});

test('the scroll-spy no longer constructs an IntersectionObserver (rAF pump is the trigger)', async () => {
  let ioCount = 0;
  const previous = Reflect.get(globalThis, 'IntersectionObserver');
  Reflect.set(
    globalThis,
    'IntersectionObserver',
    class {
      constructor() {
        ioCount++;
      }
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  );
  try {
    const r = await startWebview({
      viewWidth: 1600,
      docHeight: 8000,
      viewHeight: 800,
    });
    withHeadings(r, [
      headingEl('h1', 'a', 'A', 0),
      headingEl('h1', 'b', 'B', 1000),
    ]);
    r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
    r.send({ type: 'render', html: 'x' });
    r.window.scrollY = 1500;
    scroll(r);
    assert.strictEqual(ioCount, 0, 'no IntersectionObserver created');
  } finally {
    Reflect.set(globalThis, 'IntersectionObserver', previous);
  }
});
