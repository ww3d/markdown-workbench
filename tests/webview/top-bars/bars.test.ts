// Breadcrumb + sticky-scroll stack (#33): the class/config wiring through the mock,
// the per-heading scroll margins, the sticky-row clicks and the stylesheet contract
// (reserved padding, bar visibility, the content-region insets that keep the bars
// off the minimap/TOC rail). The live sticky pinning needs a real webview and is
// verified manually.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  headingEl,
  listenerOf,
  MM,
  scroll,
  segTarget,
  tocCfg,
  topBarsOffsetOf,
  topConfig,
  withActiveChain,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

const css = sheet('top-bars/top-bars.css');

test('a sticky-row twistie click folds its section (synced with the fold set); the label navigates (#44 P2)', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  const { foldedIds } = await r.load('folding/sections.ts');
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  scroll(r); // chain [a, b] -> sticky rows built
  const stickyClick = (id: string, onGutter: boolean) =>
    listenerOf(
      byId(r, 'sticky-scroll'),
      'click',
    )({
      target: {
        closest: (s: string) =>
          s === '.sticky-row'
            ? { dataset: { id } }
            : s === '.sticky-gutter' && onGutter
              ? {}
              : null,
      },
      preventDefault() {},
    });
  stickyClick('a', true);
  assert.strictEqual(
    foldedIds.has('a'),
    true,
    'a gutter click folds the section',
  );
  stickyClick('a', true);
  assert.strictEqual(
    foldedIds.has('a'),
    false,
    'a second gutter click unfolds it',
  );
  // A label click (not on the gutter) navigates instead of folding.
  byId(r, 'content').querySelector = () => ({
    getBoundingClientRect: () => ({ top: 100 }),
  });
  stickyClick('a', false);
  assert.strictEqual(foldedIds.has('a'), false, 'a label click does not fold');
  assert.notStrictEqual(r.state.scrolledTo, null, 'a label click navigates');
});

test('each heading gets its own scroll-margin-top = its bars height (#44)', async () => {
  // A VS Code webview performs the native #id fragment jump on a control-link click
  // (preventDefault does not stop it), landing the heading at its scroll-margin-top.
  // The shared --toc-scroll-margin is the document maximum, so a shallow heading
  // landed too low and the scroll-spy's activation line (at that heading's own,
  // smaller bars height) fell above it - the previous heading stayed selected. Each
  // heading now carries its own margin = breadcrumb + its chain depth in sticky rows.
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  const hs = [
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
    headingEl('h3', 'c', 'C', 300),
    headingEl('h1', 'd', 'D', 4000),
  ];
  withHeadings(r, hs);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(
    hs[0]?.style.scrollMarginTop,
    `${28 + 1 * 22}px`,
    'H1 alone: depth 1',
  );
  assert.strictEqual(
    hs[2]?.style.scrollMarginTop,
    `${28 + 3 * 22}px`,
    'H3<H2<H1: depth 3',
  );
  assert.strictEqual(
    hs[3]?.style.scrollMarginTop,
    `${28 + 1 * 22}px`,
    'H1 again: depth 1',
  );
});

test('the top bars show for a document with headings and publish the constant vars', async () => {
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
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(
    r.state.bodyClasses['has-breadcrumb'],
    true,
    'breadcrumb bar reserved',
  );
  // At the top (active = -1) there is no chain, so the sticky stack is hidden.
  assert.strictEqual(
    r.state.bodyClasses['has-sticky'],
    false,
    'no sticky stack above the first heading',
  );
  // The bar vars are constants published once (not measured): --breadcrumb-height
  // is the fixed 28px, --toc-scroll-margin the maximum stack height (28 + 5x22 + 8).
  assert.strictEqual(r.state.cssVars?.['--breadcrumb-height'], '28px');
  assert.strictEqual(
    r.state.cssVars?.['--toc-scroll-margin'],
    `${28 + 5 * 22 + 8}px`,
  );
});

test('the sticky stack appears once the reader is under a heading', async () => {
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
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.state.bodyClasses['has-sticky'], false);
  r.window.scrollY = 700; // past both headings -> active chain [h1, h2]
  scroll(r);
  assert.strictEqual(
    r.state.bodyClasses['has-sticky'],
    true,
    'the chain pins as a stack',
  );
});

test('breadcrumb.enabled false hides the breadcrumb but keeps the sticky stack', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  r.send(topConfig({ breadcrumb: { enabled: false } }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  scroll(r);
  assert.strictEqual(
    r.state.bodyClasses['has-breadcrumb'],
    false,
    'breadcrumb off',
  );
  assert.strictEqual(
    r.state.bodyClasses['has-sticky'],
    true,
    'sticky stays on independently',
  );
});

test('stickyScroll.enabled false hides the stack but keeps the breadcrumb', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  r.send(topConfig({ stickyScroll: { enabled: false } }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  scroll(r);
  assert.strictEqual(
    r.state.bodyClasses['has-sticky'],
    false,
    'sticky off even when scrolled',
  );
  assert.strictEqual(
    r.state.bodyClasses['has-breadcrumb'],
    true,
    'breadcrumb stays on independently',
  );
});

test('undefined top-bar config keeps both bars enabled (defensive default)', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  // No breadcrumb/stickyScroll fields in the config message at all.
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true);
  r.window.scrollY = 700;
  scroll(r);
  assert.strictEqual(r.state.bodyClasses['has-sticky'], true);
});

test('a document without headings shows no top bars', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  r.send(topConfig());
  r.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(!!r.state.bodyClasses['has-breadcrumb'], false);
  assert.strictEqual(!!r.state.bodyClasses['has-sticky'], false);
});

test('toggling a top-bar setting live takes effect at once (force-emit, no scroll)', async () => {
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
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  scroll(r); // active chain [h1, h2]
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true);
  assert.strictEqual(r.state.bodyClasses['has-sticky'], true);
  // A config message alone (no render, no scroll event) must apply immediately.
  r.send(
    topConfig({
      breadcrumb: { enabled: false },
      stickyScroll: { enabled: false },
    }),
  );
  assert.strictEqual(
    r.state.bodyClasses['has-breadcrumb'],
    false,
    'breadcrumb hidden at once',
  );
  assert.strictEqual(
    r.state.bodyClasses['has-sticky'],
    false,
    'sticky hidden at once',
  );
});

test('a depth-changing drag never measures the stack nor rewrites the margin var (#44 review 6)', async () => {
  // The freeze fix: the stack height is computed (rows x row height), never
  // measured, and --toc-scroll-margin is a constant published once at init. So a
  // drag that changes the chain DEPTH every step still forces 0 layout reads on
  // the stack and 0 --toc-scroll-margin writes (the round-8 regress was a var
  // write per depth change, which recalced every heading's scroll-margin).
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h2', 'b', 'B', 1000),
    headingEl('h3', 'c', 'C', 2000),
    headingEl('h2', 'd', 'D', 3000),
  ]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  let measures = 0;
  byId(r, 'sticky-scroll').getBoundingClientRect = () => {
    measures++;
    return { height: 24 };
  };
  let marginWrites = 0;
  const root = r.document.documentElement.style;
  const realSet = root.setProperty;
  root.setProperty = (k, v) => {
    if (k === '--toc-scroll-margin') marginWrites++;
    return realSet(k, v);
  };
  for (const y of [1500, 2500, 3500, 2500, 1500]) {
    // chain depth 2 -> 3 -> 2 -> 3 -> 2
    r.window.scrollY = y;
    scroll(r);
  }
  assert.strictEqual(
    measures,
    0,
    'the stack height is computed, never measured',
  );
  assert.strictEqual(
    marginWrites,
    0,
    'the scroll-margin var is a constant, not rewritten per depth change',
  );
});

test('a sticky-scroll row scrolls to its heading', async () => {
  const r = await withActiveChain([
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  byId(r, 'content').querySelector = (s) =>
    s === '#a' ? { getBoundingClientRect: () => ({ top: 100 }) } : null;
  listenerOf(
    byId(r, 'sticky-scroll'),
    'click',
  )({
    target: segTarget(0, '#a', '.sticky-row'),
    preventDefault() {},
  });
  assert.strictEqual(r.state.scrolledTo, 100 - (await topBarsOffsetOf(r)));
});

test('the breadcrumb reserves body top padding from its measured height', () => {
  assert.match(
    css.ruleBody('body.has-breadcrumb'),
    /padding-top:\s*calc\(var\(--breadcrumb-height/,
  );
});

test('the sticky stack sits directly below the breadcrumb', () => {
  assert.match(
    css.ruleBody('#sticky-scroll'),
    /top:\s*var\(--breadcrumb-height/,
  );
});

test('both bars and the picker are hidden until their body classes are set', () => {
  assert.match(css.ruleBody('#breadcrumb'), /display:\s*none/);
  assert.match(css.ruleBody('#sticky-scroll'), /display:\s*none/);
  assert.match(css.ruleBody('#breadcrumb-dropdown'), /display:\s*none/);
  assert.match(
    css.ruleBody('body.has-breadcrumb #breadcrumb'),
    /display:\s*flex/,
  );
  assert.match(
    css.ruleBody('body.has-sticky #sticky-scroll'),
    /display:\s*flex/,
  );
  assert.match(
    css.ruleBody('body.breadcrumb-dropdown-open #breadcrumb-dropdown'),
    /display:\s*flex/,
  );
});

test('the bars fill the content region via insets that clear the minimap and TOC rail', () => {
  assert.match(css.ruleBody('#breadcrumb'), /left:\s*var\(--bar-inset-left\)/);
  assert.match(
    css.ruleBody('#breadcrumb'),
    /right:\s*var\(--bar-inset-right\)/,
  );
  assert.match(
    css.ruleBody('body.has-minimap:not(.minimap-left)'),
    /--bar-inset-right:\s*104px/,
  );
  // The TOC-rail inset shares its selector with the existing rail-padding rule,
  // so assert the declaration exists in the sheet rather than via ruleBody.
  assert.match(css.text, /--bar-inset-left:\s*240px/);
  assert.match(css.text, /--bar-inset-right:\s*240px/);
});

test('a forced re-emit with an unchanged chain rebuilds nothing', async () => {
  const r = await withActiveChain([
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
  ]);
  const { scrollSpy } = await r.load('scroll-spy/spy.ts');
  r.window.scrollY = 700; // back under b: the same chain [a, b]
  let writes = 0;
  const toggle = r.document.body.classList.toggle;
  r.document.body.classList.toggle = (c, v) => {
    if (c === 'has-breadcrumb' || c === 'has-sticky') writes++;
    toggle(c, v);
  };
  const created = r.state.created.length;
  scrollSpy.update(true);
  assert.strictEqual(writes, 0, 'no bar class rewritten');
  assert.strictEqual(r.state.created.length, created, 'no node created');
});

test('a chain change of the same depth updates the bar links in place', async () => {
  const r = await withActiveChain([
    headingEl('h1', 'a', 'A', 100),
    headingEl('h2', 'b', 'B', 200),
    headingEl('h1', 'c', 'C', 3000),
    headingEl('h2', 'd', 'D', 3100),
  ]);
  const before = [...(byId(r, 'breadcrumb')._links ?? [])];
  assert.strictEqual(before.length, 2);
  const created = r.state.created.length;
  r.window.scrollY = 3500; // chain [c, d]: same depth
  scroll(r);
  const after = byId(r, 'breadcrumb')._links ?? [];
  assert.ok(
    after.length === 2 && after.every((link, i) => Object.is(link, before[i])),
    'the same link nodes',
  );
  assert.strictEqual(r.state.created.length, created, 'no node created');
  assert.strictEqual(after[0]?._text, 'C', 'relabelled in place');
});

test('the layers stack in the documented z-index order', () => {
  // Top to bottom: breadcrumb picker > TOC overlay > FAB/backdrop > minimap/TOC
  // rail > top bars > sticky table header (top-bars.css, the #33 comment).
  const layers = sheet(
    'minimap/minimap.css',
    'tables/tables.css',
    'toc/rail.css',
    'toc/fab.css',
    'top-bars/top-bars.css',
  );
  const z = (selector: string) =>
    Number(layers.ruleBody(selector).match(/z-index:\s*(\d+)/)?.[1]);
  const order = [
    z('#breadcrumb-dropdown'),
    z('body.toc-fab.toc-open #toc'),
    z('#toc-fab'),
    z('#minimap'),
    z('#breadcrumb'),
    z('th'),
  ];
  assert.deepStrictEqual(order, [8, 7, 6, 5, 4, 2]);
  assert.strictEqual(
    z('#toc-backdrop'),
    z('#toc-fab'),
    'backdrop with the FAB',
  );
  assert.strictEqual(z('#toc'), z('#minimap'), 'TOC rail with the minimap');
  assert.strictEqual(z('#sticky-scroll'), z('#breadcrumb'), 'both top bars');
});
