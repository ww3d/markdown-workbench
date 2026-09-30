// Table of contents (#32): the rail/FAB switch, its side, the defensive config, the
// overlay, and the rail/FAB stylesheet contract. Real rail/FAB rendering and overlay
// interaction need a live webview and are verified manually.
import { test } from 'node:test';
import assert from 'node:assert';
import { sheet } from '../../helpers/css-rules.ts';
import { startWebview } from '../../helpers/webview-dom.ts';
import {
  byId,
  headingEl,
  keydown,
  listenerOf,
  MM,
  tocCfg,
  withHeadings,
} from '../../helpers/webview-fixtures.ts';

test('railFits: viewport must hold content + TOC reserve + the opposite side', async () => {
  const r = await startWebview();
  const { railFits } = await r.load('toc/layout.ts');
  assert.strictEqual(railFits(1600, 980, 240, 104), true);
  assert.strictEqual(railFits(1200, 980, 240, 104), false);
  assert.strictEqual(railFits(1252, 980, 240, 32), true); // exact fit (>=)
});

test('TOC auto mode: rail when the viewport is wide, fab when it is narrow', async () => {
  const wide = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(wide, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h2', 'b', 'B', 100),
  ]);
  wide.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ enabled: false }),
    toc: tocCfg(),
  });
  wide.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(wide.state.bodyClasses['has-toc'], true);
  assert.strictEqual(wide.state.bodyClasses['toc-rail'], true);
  assert.strictEqual(wide.state.bodyClasses['toc-fab'], false);

  const narrow = await startWebview({
    viewWidth: 700,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(narrow, [headingEl('h1', 'a', 'A', 0)]);
  narrow.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ enabled: false }),
    toc: tocCfg(),
  });
  narrow.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(narrow.state.bodyClasses['toc-fab'], true);
  assert.strictEqual(narrow.state.bodyClasses['toc-rail'], false);
});

test('TOC mode overrides force rail/fab regardless of width', async () => {
  const railed = await startWebview({
    viewWidth: 400,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(railed, [headingEl('h1', 'a', 'A', 0)]);
  railed.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    toc: tocCfg({ mode: 'rail' }),
  });
  railed.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(railed.state.bodyClasses['toc-rail'], true);

  const fabbed = await startWebview({
    viewWidth: 3000,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(fabbed, [headingEl('h1', 'a', 'A', 0)]);
  fabbed.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    toc: tocCfg({ mode: 'fab' }),
  });
  fabbed.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(fabbed.state.bodyClasses['toc-fab'], true);
});

test('the TOC takes the side opposite the minimap', async () => {
  const r = await startWebview({ viewWidth: 1600 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ side: 'right' }),
    toc: tocCfg(),
  });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['toc-left'], true); // minimap right -> toc left
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ side: 'left' }),
    toc: tocCfg(),
  });
  assert.strictEqual(r.state.bodyClasses['toc-left'], false); // minimap left -> toc right
});

test('toc.enabled false hides the TOC entirely', async () => {
  const r = await startWebview({ viewWidth: 1600 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM(),
    toc: tocCfg({ enabled: false }),
  });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['has-toc'], false);
  assert.strictEqual(!!r.state.bodyClasses['toc-rail'], false);
});

test('undefined toc config keeps the TOC enabled (defensive default)', async () => {
  const r = await startWebview({ viewWidth: 1600 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: undefined });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['has-toc'], true);
});

test('a document without headings shows no TOC', async () => {
  const r = await startWebview({ viewWidth: 1600 });
  // no withHeadings: content.querySelectorAll returns [] for the heading query
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(r.state.bodyClasses['has-toc'], false);
});

test('the FAB opens the overlay and Escape closes it', async () => {
  const r = await startWebview({
    viewWidth: 500,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['toc-fab'], true);
  listenerOf(byId(r, 'toc-fab'), 'click')({});
  assert.strictEqual(r.state.bodyClasses['toc-open'], true);
  keydown(r, 'Escape');
  assert.strictEqual(r.state.bodyClasses['toc-open'], false);
});

test('the backdrop click closes the overlay', async () => {
  const r = await startWebview({
    viewWidth: 500,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  listenerOf(byId(r, 'toc-fab'), 'click')({});
  assert.strictEqual(r.state.bodyClasses['toc-open'], true);
  listenerOf(byId(r, 'toc-backdrop'), 'click')({});
  assert.strictEqual(r.state.bodyClasses['toc-open'], false);
});

// --- TOC stylesheet contract (#32): rail reserve + FAB/overlay visibility. ---

test('the rail reserves body padding on the TOC side', () => {
  const css = sheet('toc/rail.css');
  assert.match(
    css.ruleBody('body.has-toc.toc-rail.toc-left'),
    /padding-left:\s*240px/,
  );
  assert.match(
    css.ruleBody('body.has-toc.toc-rail:not(.toc-left)'),
    /padding-right:\s*240px/,
  );
});

test('the FAB and overlay are hidden until their body classes are set', () => {
  const css = sheet('toc/rail.css', 'toc/fab.css');
  assert.match(css.ruleBody('#toc'), /display:\s*none/);
  assert.match(css.ruleBody('#toc-fab'), /display:\s*none/);
  assert.match(css.ruleBody('#toc-backdrop'), /display:\s*none/);
  assert.match(css.ruleBody('body.has-toc.toc-rail #toc'), /display:\s*flex/);
  assert.match(
    css.ruleBody('body.has-toc.toc-fab #toc-fab'),
    /display:\s*inline-flex/,
  );
  assert.match(css.ruleBody('body.toc-open #toc-backdrop'), /display:\s*block/);
});

test('the TOC rail is layout/paint contained like the top bars', () => {
  assert.match(
    sheet('toc/rail.css').ruleBody('#toc'),
    /contain:\s*layout\s+paint/,
  );
});

test('a content-box change re-decides rail or FAB without a window resize', async () => {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({
    type: 'config',
    maxWidth: '980px',
    minimap: MM({ enabled: false }),
    toc: tocCfg(),
  });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['toc-rail'], true);
  r.window.innerWidth = 700;
  const observer = r.state.resizeObserver;
  assert.ok(observer, 'the webview observes the body');
  observer();
  assert.strictEqual(r.state.bodyClasses['toc-fab'], true, 'now too narrow');
});

test('resolveCssWidthPx measures a font-relative width with a hidden probe', async () => {
  const r = await startWebview();
  const { resolveCssWidthPx } = await r.load('toc/layout.ts');
  const create = r.document.createElement;
  let removed = false;
  r.document.createElement = (tag) => {
    const el = create(tag);
    el.getBoundingClientRect = () => ({ width: 720 });
    el.remove = () => {
      removed = true;
    };
    return el;
  };
  Reflect.set(r.document.body, 'appendChild', () => {});
  assert.strictEqual(resolveCssWidthPx('72ch'), 720, 'measured, not 72 * 8');
  assert.ok(removed, 'the probe is removed again');
  assert.strictEqual(resolveCssWidthPx('980px'), 980);
});
