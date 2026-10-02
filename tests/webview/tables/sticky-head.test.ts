// Sticky table headers: wide tables scroll in their own wrapper, whose header pin is
// emulated from cached geometry; the native th pin docks under the top bars.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  headingEl,
  MM,
  mkScrollWrap,
  scroll,
  topConfig,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

test('render toggles scrolls only on overflowing top-level table wrappers', async () => {
  const r = await startWebview({ docHeight: 8000, viewHeight: 800 });
  const wrap = (scrollWidth: number, clientWidth: number) => {
    const classes: Record<string, boolean | undefined> = {};
    return {
      scrollWidth,
      clientWidth,
      querySelector: () => null, // no thead: updateStickyHeads skips it
      classList: {
        toggle: (c: string, v?: boolean) => {
          classes[c] = v === undefined ? !classes[c] : v;
        },
        contains: (c: string) => !!classes[c],
      },
    };
  };
  const wide = wrap(1400, 900),
    narrow = wrap(700, 700);
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === ':scope > .table-wrap' ? [wide, narrow] : [];
  r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
  r.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(wide.classList.contains('scrolls'), true);
  assert.strictEqual(narrow.classList.contains('scrolls'), false);
});

test('stickyHeadOffset: explicit geometries', async () => {
  const r = await startWebview();
  const { stickyHeadOffset } = await r.load('tables/sticky-head.ts');
  // No inset: the header follows the window scroll from the table top.
  assert.strictEqual(stickyHeadOffset(100, 300, 400, 40, 0), 0);
  assert.strictEqual(stickyHeadOffset(500, 300, 400, 40, 0), 200);
  // Clamped at the table end: never beyond tableHeight - headHeight = 360.
  assert.strictEqual(stickyHeadOffset(900, 300, 400, 40, 0), 360);
  // A constant inset docks the pin that much lower (below the bars).
  assert.strictEqual(stickyHeadOffset(300, 300, 400, 40, 50), 50);
  assert.strictEqual(stickyHeadOffset(100, 300, 400, 40, 50), 0);
});

test('updateStickyHeads pins only scrolls wrappers and clears the rest', async () => {
  const r = await startWebview();
  const { updateStickyHeads, updateTableScroll } = await r.load(
    'tables/sticky-head.ts',
  );
  r.window.scrollY = 1000;
  const pinned = mkScrollWrap(true, -200); // table top 200px above the viewport top
  const plain = mkScrollWrap(false, -200); // not scrolling: leftover transform cleared
  const below = mkScrollWrap(true, 100); // table top still below the viewport top
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === ':scope > .table-wrap' ? [pinned, plain, below] : [];
  updateTableScroll(); // classify + cache geometry (render/config/resize, not the scroll path)
  const measuredAfterCache = pinned.table.gbcr;
  updateStickyHeads();
  assert.strictEqual(pinned.head.style.transform, 'translateY(200px)');
  assert.strictEqual(plain.head.style.transform, '');
  assert.strictEqual(below.head.style.transform, '');
  // The scroll hot path reads cached geometry - it never re-measures the table
  // (a getBoundingClientRect per frame forced a synchronous layout: the freeze).
  assert.strictEqual(
    pinned.table.gbcr,
    measuredAfterCache,
    'no getBoundingClientRect on the scroll path',
  );
});

test('updateStickyHeads skips its DOM query entirely when no table scrolls (hot-path gate)', async () => {
  const r = await startWebview();
  const { updateStickyHeads, updateTableScroll } = await r.load(
    'tables/sticky-head.ts',
  );
  let queries = 0;
  byId(r, 'content').querySelectorAll = (sel) => {
    if (sel === ':scope > .table-wrap') queries++;
    return [];
  };
  updateTableScroll(); // no scrolling wrapper -> empty cache
  const afterClassify = queries;
  updateStickyHeads(); // the scroll hot path must do no DOM work
  assert.strictEqual(
    queries,
    afterClassify,
    'no per-frame table-wrap query when nothing scrolls',
  );
});

test('the emulated header re-measures the table geometry after a reflow (#44)', async () => {
  // The dock offset uses the table's document top, which the breadcrumb's body
  // padding shifts after the first classification - and resize/image reflow shift
  // it again. refreshScrollingHeads re-reads it, so the pin is never frozen at the
  // stale pre-reflow position.
  const r = await startWebview();
  const { updateStickyHeads, updateTableScroll, refreshScrollingHeads } =
    await r.load('tables/sticky-head.ts');
  r.window.scrollY = 1000;
  const wrap = mkScrollWrap(true, -200); // table top 200px above the viewport
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === ':scope > .table-wrap' ? [wrap] : [];
  updateTableScroll();
  updateStickyHeads();
  assert.strictEqual(wrap.head.style.transform, 'translateY(200px)');
  // Reflow moves the table down 60px (e.g. the breadcrumb padding is applied).
  wrap.table.getBoundingClientRect = () => ({ top: -140, height: 400 });
  refreshScrollingHeads();
  updateStickyHeads();
  assert.strictEqual(
    wrap.head.style.transform,
    'translateY(140px)',
    're-measured, not frozen',
  );
});

test('a wide (scrolling) table switches off native th sticky so the emulated pin is the only one', () => {
  // Native th sticky left on stacks on top of the emulated thead transform and
  // docks the header a stack height too low; the scrolls wrapper turns it off.
  assert.match(
    sheet('tables/tables.css').ruleBody('.table-wrap.scrolls th'),
    /position:\s*static/,
  );
});

test('the sticky table header docks FLUSH under the current stack, per-thead not on :root (#44 perf)', async () => {
  // The header docks directly under the CURRENT stack (breadcrumb + the current
  // chain's rows), so a shallow section docks under its shorter stack rather than a
  // document-wide maximum that left a gap. --sticky-head-top is an inherited custom
  // property: written on :root it re-resolves inheritance for the whole document (a
  // measured 10x style-recalc blow-up), so it is written on the thead subtrees - its
  // only consumers - and only when the depth changes, never per scroll frame.
  assert.match(
    sheet('tables/tables.css').ruleBody('th'),
    /top:\s*var\(--sticky-head-top/,
    'th docks at the var',
  );

  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  // Max depth 3 (H1>H2>H3), but with a shallow H1>H2 section further down.
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
    headingEl('h3', 'c', 'C', 300),
    headingEl('h1', 'd', 'D', 3000),
    headingEl('h2', 'e', 'E', 3100),
  ]);
  // Observe the dock var on a thead; the mock content has none of its own. Compose
  // with withHeadings' selector so heading collection still works.
  const writes: string[] = [];
  const thead = {
    style: {
      setProperty: (k: string, v: string) => {
        if (k === '--sticky-head-top') writes.push(v);
      },
    },
  };
  const content = byId(r, 'content');
  const baseQSA = content.querySelectorAll;
  content.querySelectorAll = (sel) =>
    sel === 'thead' ? [thead] : baseQSA(sel);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  // Under the deep H3 (chain h1>h2>h3): dock = breadcrumb 28 + 3 rows x 22 = 94.
  r.window.scrollY = 400;
  scroll(r);
  assert.strictEqual(
    writes.at(-1),
    `${28 + 3 * 22}px`,
    'docks flush under the 3-row stack',
  );
  // Into the shallow H1>H2 section (chain h1>h2): dock drops to 28 + 2x22 = 72 -
  // flush under the shorter stack, NOT the document max of 94 (no gap).
  r.window.scrollY = 3300;
  scroll(r);
  assert.strictEqual(
    writes.at(-1),
    `${28 + 2 * 22}px`,
    'follows the current shallower stack',
  );
  // A scroll that stays inside the section (no depth change) writes nothing more.
  const n = writes.length;
  r.window.scrollY = 3400;
  scroll(r);
  assert.strictEqual(
    writes.length,
    n,
    'no per-frame write when the depth is unchanged',
  );
});

test('a cell holding exactly one checkbox shows the pointer hand as a whole', () => {
  // The bare-click toggle works on such a cell (not on one with several boxes), so
  // the whole cell says it is clickable.
  assert.match(
    sheet('tables/tables.css').ruleBody(
      'td:has(input.cell-task):not(:has(input.cell-task ~ input.cell-task))',
    ),
    /cursor:\s*pointer/,
  );
});
