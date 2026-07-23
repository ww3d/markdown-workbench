// Webview behavior, executed headlessly against media/webview.js: config/
// render flow, minimap size modes, defensive config handling, navigation
// math. Plus a smoke test for the getWebviewHtml skeleton (CSP/nonce/assets).
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh } = require('./helpers/vscode-mock');
const { runWebviewScript } = require('./helpers/dom-mock');

const MM = (over) => Object.assign(
  { enabled: true, size: 'proportional', showSlider: 'always', side: 'right' }, over);

test('webview script parses and registers a message listener', () => {
  const { state } = runWebviewScript();
  assert.ok(state.listeners.window['message']);
});

test('render shows the minimap for long documents', () => {
  const { state, send } = runWebviewScript({ docHeight: 8000, viewHeight: 800 });
  send({ type: 'config', maxWidth: '980px', minimap: MM() });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], true);
});

test('the minimap clone strips ids so it never shadows the real anchor targets', () => {
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800 });
  const removed = [];
  const content = r.document.getElementById('content');
  content.cloneNode = () => ({
    querySelectorAll: (sel) =>
      sel === '[id]' ? [{ removeAttribute: (a) => removed.push(a) }] : []
  });
  r.send({ type: 'config', maxWidth: '980px', minimap: MM() });
  r.send({ type: 'render', html: '<h1 id="x">x</h1>' });
  assert.ok(removed.includes('id'), 'heading id stripped from the minimap clone');
});

test('short documents hide the minimap', () => {
  const { state, send } = runWebviewScript({ docHeight: 500, viewHeight: 800 });
  send({ type: 'config', maxWidth: '980px', minimap: MM() });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], false);
});

test('render toggles scrolls only on overflowing top-level table wrappers', () => {
  const { send, document } = runWebviewScript({ docHeight: 8000, viewHeight: 800 });
  const wrap = (scrollWidth, clientWidth) => {
    const classes = {};
    return {
      scrollWidth, clientWidth,
      querySelector: () => null, // no thead: updateStickyHeads skips it
      classList: {
        toggle: (c, v) => { classes[c] = v === undefined ? !classes[c] : v; },
        contains: (c) => !!classes[c]
      }
    };
  };
  const wide = wrap(1400, 900), narrow = wrap(700, 700);
  const content = document.getElementById('content');
  content.querySelectorAll = (sel) => sel === ':scope > .table-wrap' ? [wide, narrow] : [];
  send({ type: 'config', maxWidth: '980px', minimap: MM() });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(wide.classList.contains('scrolls'), true);
  assert.strictEqual(narrow.classList.contains('scrolls'), false);
});

test('stickyHeadOffset: explicit geometries', () => {
  const { fns } = runWebviewScript({ expose: ['stickyHeadOffset'] });
  // No inset: the header follows the window scroll from the table top.
  assert.strictEqual(fns.stickyHeadOffset(100, 300, 400, 40, 0), 0);
  assert.strictEqual(fns.stickyHeadOffset(500, 300, 400, 40, 0), 200);
  // Clamped at the table end: never beyond tableHeight - headHeight = 360.
  assert.strictEqual(fns.stickyHeadOffset(900, 300, 400, 40, 0), 360);
  // A constant inset docks the pin that much lower (below the bars).
  assert.strictEqual(fns.stickyHeadOffset(300, 300, 400, 40, 50), 50);
  assert.strictEqual(fns.stickyHeadOffset(100, 300, 400, 40, 50), 0);
});

// A wrapper mock whose table counts getBoundingClientRect calls, so a test can
// assert the scroll path never measures (it reads cached geometry instead).
function mkScrollWrap(scrolls, viewportTop) {
  const head = { style: { transform: 'translateY(99px)' }, getBoundingClientRect: () => ({ height: 40 }) };
  const table = { gbcr: 0, getBoundingClientRect() { this.gbcr++; return { top: viewportTop, height: 400 }; } };
  const classes = {};
  return {
    head, table,
    scrollWidth: scrolls ? 200 : 100, clientWidth: 100, // scrollWidth > clientWidth -> element-scrolling
    classList: { toggle: (c, v) => { classes[c] = v; }, contains: (c) => !!classes[c] },
    querySelector: (sel) => sel === 'thead' ? head : table
  };
}

test('updateStickyHeads pins only scrolls wrappers and clears the rest', () => {
  const { fns, document, window } = runWebviewScript({ expose: ['updateStickyHeads', 'updateTableScroll'] });
  window.scrollY = 1000;
  const pinned = mkScrollWrap(true, -200); // table top 200px above the viewport top
  const plain = mkScrollWrap(false, -200); // not scrolling: leftover transform cleared
  const below = mkScrollWrap(true, 100);   // table top still below the viewport top
  const content = document.getElementById('content');
  content.querySelectorAll = (sel) => sel === ':scope > .table-wrap' ? [pinned, plain, below] : [];
  fns.updateTableScroll(); // classify + cache geometry (render/config/resize, not the scroll path)
  const measuredAfterCache = pinned.table.gbcr;
  fns.updateStickyHeads();
  assert.strictEqual(pinned.head.style.transform, 'translateY(200px)');
  assert.strictEqual(plain.head.style.transform, '');
  assert.strictEqual(below.head.style.transform, '');
  // The scroll hot path reads cached geometry - it never re-measures the table
  // (a getBoundingClientRect per frame forced a synchronous layout: the freeze).
  assert.strictEqual(pinned.table.gbcr, measuredAfterCache, 'no getBoundingClientRect on the scroll path');
});

test('updateStickyHeads skips its DOM query entirely when no table scrolls (hot-path gate)', () => {
  const { fns, document } = runWebviewScript({ expose: ['updateStickyHeads', 'updateTableScroll'] });
  let queries = 0;
  const content = document.getElementById('content');
  content.querySelectorAll = (sel) => { if (sel === ':scope > .table-wrap') queries++; return []; };
  fns.updateTableScroll();          // no scrolling wrapper -> empty cache
  const afterClassify = queries;
  fns.updateStickyHeads();          // the scroll hot path must do no DOM work
  assert.strictEqual(queries, afterClassify, 'no per-frame table-wrap query when nothing scrolls');
});

test('the emulated header re-measures the table geometry after a reflow (#44)', () => {
  // The dock offset uses the table's document top, which the breadcrumb's body
  // padding shifts after the first classification - and resize/image reflow shift
  // it again. refreshScrollingHeads re-reads it, so the pin is never frozen at the
  // stale pre-reflow position.
  const { fns, document, window } = runWebviewScript({
    expose: ['updateStickyHeads', 'updateTableScroll', 'refreshScrollingHeads'] });
  window.scrollY = 1000;
  const wrap = mkScrollWrap(true, -200); // table top 200px above the viewport
  const content = document.getElementById('content');
  content.querySelectorAll = (sel) => sel === ':scope > .table-wrap' ? [wrap] : [];
  fns.updateTableScroll();
  fns.updateStickyHeads();
  assert.strictEqual(wrap.head.style.transform, 'translateY(200px)');
  // Reflow moves the table down 60px (e.g. the breadcrumb padding is applied).
  wrap.table.getBoundingClientRect = () => ({ top: -140, height: 400 });
  fns.refreshScrollingHeads();
  fns.updateStickyHeads();
  assert.strictEqual(wrap.head.style.transform, 'translateY(140px)', 're-measured, not frozen');
});

test('a wide (scrolling) table switches off native th sticky so the emulated pin is the only one', () => {
  // Native th sticky left on stacks on top of the emulated thead transform and
  // docks the header a stack height too low; the scrolls wrapper turns it off.
  assert.match(ruleBody('.table-wrap.scrolls th'), /position:\s*static/);
});

test('proportional mode pans: known slider geometry', () => {
  const { state, send, window } = runWebviewScript({ docHeight: 8000, viewHeight: 800, railHeight: 800, contentWidth: 700, railWidth: 88 });
  window.scrollY = 3600;
  send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'proportional' }) });
  send({ type: 'render', html: '<p>x</p>' });
  // k=88/700; mapDocH=8000k=1005.71; overflow=205.71; offset=-(3600/7200)*205.71=-102.86
  // slider top = 3600k + offset = 452.57-102.86 = 349.71
  const top = parseFloat(state.els['minimap-slider'].style.top);
  assert.ok(Math.abs(top - 349.71) < 0.5, String(top));
  assert.match(state.els['minimap-content'].style.transform, /translateY\(-102\.8/);
});

test('fill mode aligns the slider with the scrollbar and never pans', () => {
  const { state, send, window } = runWebviewScript({ docHeight: 8000, viewHeight: 800, railHeight: 800 });
  window.scrollY = 3600;
  send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  send({ type: 'render', html: '<p>x</p>' });
  // sy = 800/8000 = 0.1 -> top = 360 = scrollbar thumb position; h = 80
  assert.strictEqual(parseFloat(state.els['minimap-slider'].style.top), 360);
  assert.strictEqual(parseFloat(state.els['minimap-slider'].style.height), 80);
  assert.match(state.els['minimap-content'].style.transform, /translateY\(0px\)/);
});

test('fit mode caps the scale at the rail and never stretches', () => {
  const { state, send, window } = runWebviewScript({ docHeight: 8000, viewHeight: 800, railHeight: 800, contentWidth: 700, railWidth: 88 });
  window.scrollY = 3600;
  send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fit' }) });
  send({ type: 'render', html: '<p>x</p>' });
  // sy = min(88/700, 800/8000) = 0.1 -> identical mapping to fill here
  assert.strictEqual(parseFloat(state.els['minimap-slider'].style.top), 360);
});

test('fit equals proportional while the document still fits the rail', () => {
  const opts = { docHeight: 3000, viewHeight: 800, railHeight: 800, contentWidth: 700, railWidth: 88 };
  // k=0.12571; docH*k=377 < 800 -> proportional: no pan; fit: sy=min(k, 0.2667)=k
  const a = runWebviewScript(opts);
  a.window.scrollY = 1000;
  a.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'proportional' }) });
  a.send({ type: 'render', html: '<p>x</p>' });
  const b = runWebviewScript(opts);
  b.window.scrollY = 1000;
  b.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fit' }) });
  b.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(a.state.els['minimap-slider'].style.top, b.state.els['minimap-slider'].style.top);
});

test('undefined or missing minimap config falls back to defaults (regression 0.21.1)', () => {
  const { state, send } = runWebviewScript({ docHeight: 8000, viewHeight: 800 });
  send({ type: 'config', maxWidth: '980px', minimap: { enabled: undefined } });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], true);
  send({ type: 'config', maxWidth: '980px', minimap: undefined });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], true);
});

test('enabled:false hides the rail even for long documents', () => {
  const { state, send } = runWebviewScript({ docHeight: 8000, viewHeight: 800 });
  send({ type: 'config', maxWidth: '980px', minimap: MM({ enabled: false }) });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['has-minimap'], false);
});

test('side and slider visibility map to classes', () => {
  const { state, send } = runWebviewScript({ docHeight: 8000, viewHeight: 800 });
  send({ type: 'config', maxWidth: '980px', minimap: MM({ side: 'left', showSlider: 'mouseover' }) });
  send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(state.bodyClasses['minimap-left'], true);
  assert.strictEqual(state.els['minimap']._classes['slider-mouseover'], true);
});

test('the webview persists the document URI from config for restore-after-restart', () => {
  const r = runWebviewScript();
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg(),
    breadcrumb: { enabled: true }, stickyScroll: { enabled: true },
    documentUri: 'file:///ws/doc.md' });
  assert.deepStrictEqual(r.state.savedState, { documentUri: 'file:///ws/doc.md' },
    'setState persisted the document URI (read back by the panel serializer)');
});

test('config sets the width variable', () => {
  const { state, send } = runWebviewScript();
  send({ type: 'config', maxWidth: '72ch', minimap: MM() });
  assert.strictEqual(state.cssVars['--mc-max-width'], '72ch');
});

test('scroll handler updates the minimap even while sync-suppressed (regression 0.18.0)', () => {
  const { state, send, window } = runWebviewScript({ docHeight: 8000, viewHeight: 800, railHeight: 800 });
  send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  send({ type: 'render', html: '<p>x</p>' });
  send({ type: 'scrollTo', line: 0 }); // arms suppression
  window.scrollY = 4000;
  state.listeners.window['scroll']();
  assert.strictEqual(parseFloat(state.els['minimap-slider'].style.top), 400);
});

test('minimap navigation centers the clicked position (fill)', () => {
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, railHeight: 800, expose: ['minimapNavigate'] });
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  r.fns.minimapNavigate(400); // railY 400 -> docY 4000 -> centered: 4000-400
  assert.strictEqual(r.state.scrolledTo, 3600);
});

// Slider grab behavior (like the editor minimap). Fixed geometry for all
// three tests: fill mode, doc 8000, view 800, rail 800 -> mapSy = 0.1,
// mapOffset = 0; scrollY 3600 -> slider rect [360, 440] (top 360, height 80).
function sliderSetup() {
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, railHeight: 800 });
  r.window.scrollY = 3600;
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  const minimap = r.state.els['minimap'];
  const fire = (type, clientY) =>
    minimap._listeners[type]({ clientY, pointerId: 1, preventDefault() {} });
  return { r, fire };
}

test('pointerdown on the slider grabs it without jumping', () => {
  const { r, fire } = sliderSetup();
  fire('pointerdown', 400); // inside [360, 440]
  assert.strictEqual(r.state.scrolledTo, null, 'grab must not scroll');
  assert.strictEqual(r.window.scrollY, 3600);
});

test('dragging the grabbed slider scrolls relative by px / mapSy', () => {
  const { r, fire } = sliderSetup();
  fire('pointerdown', 400); // grabOffset = 400 - 360 = 40
  fire('pointermove', 450); // sliderTop = 450 - 40 = 410 -> scrollY = 410 / 0.1
  assert.strictEqual(r.state.scrolledTo, 4100, '50px drag = +500 scroll at mapSy 0.1');
  fire('pointermove', 350); // sliderTop = 310 -> 3100
  assert.strictEqual(r.state.scrolledTo, 3100);
});

test('pointerdown outside the slider still centers, also after a grab', () => {
  const { r, fire } = sliderSetup();
  fire('pointerdown', 200); // outside [360, 440]: docY 2000 - 400 = 1600
  assert.strictEqual(r.state.scrolledTo, 1600);
  fire('pointerup', 200);
  // After the centering click scrollY is 1600 -> slider sits at [160, 240];
  // a fresh pointerdown at 396 is outside again and must center, proving a
  // previous interaction leaves no grab mode armed: docY 3960 - 400 = 3560.
  fire('pointerdown', 396);
  assert.strictEqual(r.state.scrolledTo, 3560);
});

// --- Stylesheet contract (#15): the body is selectable, user-select: none is
// confined to the minimap and the checkbox inputs. ---

const fs = require('fs');
const path = require('path');
const CSS = fs.readFileSync(path.resolve(__dirname, '..', 'media', 'webview.css'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, ''); // drop comments so they can't carry braces

// Declarations of the first rule whose comma-separated selector list contains
// exactly `selector` (this stylesheet has no nesting).
function ruleBody(selector) {
  for (const rule of CSS.match(/[^{}]+\{[^{}]*\}/g) || []) {
    const i = rule.indexOf('{');
    const selectors = rule.slice(0, i).split(',').map((s) => s.trim());
    if (selectors.includes(selector)) return rule.slice(i + 1, -1);
  }
  return null;
}

test('body is selectable (user-select: text)', () => {
  assert.match(ruleBody('body'), /user-select:\s*text/);
});

test('the minimap keeps user-select: none', () => {
  assert.match(ruleBody('#minimap'), /user-select:\s*none/);
});

test('both checkbox inputs keep user-select: none', () => {
  assert.match(ruleBody('.task-row input[type=checkbox]'), /user-select:\s*none/);
  assert.match(ruleBody('input.cell-task'), /user-select:\s*none/);
});

// --- Task toggle gating (#15): text stays selectable, the toggle is decided
// at click time instead of by a global user-select lock. ---

test('canToggleFromBareClick: empty selection + single click toggles', () => {
  const { fns } = runWebviewScript({ expose: ['canToggleFromBareClick'] });
  assert.strictEqual(fns.canToggleFromBareClick('', 1), true);
});

test('canToggleFromBareClick: a non-empty selection blocks the toggle', () => {
  const { fns } = runWebviewScript({ expose: ['canToggleFromBareClick'] });
  assert.strictEqual(fns.canToggleFromBareClick('some text', 1), false);
});

test('canToggleFromBareClick: a multi-click (detail > 1) blocks the toggle', () => {
  const { fns } = runWebviewScript({ expose: ['canToggleFromBareClick'] });
  assert.strictEqual(fns.canToggleFromBareClick('', 2), false);
});

// Click-path helpers: build minimal targets whose closest()/querySelectorAll()
// answer the exact selectors the delegated handler probes, then fire the
// content click listener captured by the dom mock.
function fireClick(r, target, over = {}) {
  const e = Object.assign(
    { target, detail: 1, shiftKey: false, ctrlKey: false, metaKey: false, preventDefault() {} },
    over);
  r.document.getElementById('content')._listeners['click'](e);
}

function listCheckboxTarget(line, checked) {
  const li = { dataset: { line: String(line), checked: checked ? 'true' : 'false' },
    closest: (s) => s === 'li.task' ? li : null };
  const input = {
    hasAttribute: () => checked,
    closest: (s) => {
      if (s === '.task-row input[type=checkbox]') return input;
      if (s === 'li.task') return li;
      return null;
    }
  };
  return input;
}

function labelTarget(line, checked) {
  const li = { dataset: { line: String(line), checked: checked ? 'true' : 'false' },
    closest: (s) => s === 'li.task' ? li : null };
  const row = { closest: (s) => s === 'li.task' ? li : null };
  return { closest: (s) => s === '.task-row' ? row : null };
}

function cellCheckboxTarget(line, idx, checked) {
  const input = { hasAttribute: () => checked, dataset: { line: String(line), idx: String(idx) } };
  input.closest = (s) => s === 'input.cell-task' ? input : null;
  return input;
}

function cellBodyTarget(box) {
  const td = { querySelectorAll: (s) => s === 'input.cell-task' ? [box] : [],
    closest: (s) => s === 'td' ? td : null };
  return { closest: (s) => s === 'td' ? td : null };
}

test('clicking a list checkbox toggles regardless of an active selection', () => {
  const r = runWebviewScript();
  r.window.__selection = 'dragged out some text'; // would block a bare click
  fireClick(r, listCheckboxTarget(3, false));
  const msg = r.state.posted.at(-1);
  assert.strictEqual(msg.type, 'toggle');
  assert.deepStrictEqual(msg.lines, [3]);
  assert.strictEqual(msg.checked, true);
});

test('clicking a table checkbox toggles via toggleCell, ungated', () => {
  const r = runWebviewScript();
  r.window.__selection = 'text';
  fireClick(r, cellCheckboxTarget(4, 1, false));
  const msg = r.state.posted.at(-1);
  assert.strictEqual(msg.type, 'toggleCell');
  assert.strictEqual(msg.line, 4);
  assert.strictEqual(msg.idx, 1);
  assert.strictEqual(msg.checked, true);
});

test('a bare label click toggles only without an active selection', () => {
  const r = runWebviewScript();
  fireClick(r, labelTarget(2, false));
  assert.strictEqual(r.state.posted.at(-1).type, 'toggle');
  const before = r.state.posted.length;
  r.window.__selection = 'highlighted';
  fireClick(r, labelTarget(2, false));
  assert.strictEqual(r.state.posted.length, before, 'selection present: no toggle');
});

test('a double click on the label selects a word instead of toggling', () => {
  const r = runWebviewScript();
  const before = r.state.posted.length;
  fireClick(r, labelTarget(2, false), { detail: 2 });
  assert.strictEqual(r.state.posted.length, before);
});

test('a bare click in a single-checkbox cell is gated like the label', () => {
  const r = runWebviewScript();
  fireClick(r, cellBodyTarget(cellCheckboxTarget(4, 0, false)));
  assert.strictEqual(r.state.posted.at(-1).type, 'toggleCell');
  const before = r.state.posted.length;
  r.window.__selection = 'sel';
  fireClick(r, cellBodyTarget(cellCheckboxTarget(4, 0, false)));
  assert.strictEqual(r.state.posted.length, before, 'selection present: no cell toggle');
  r.window.__selection = '';
  fireClick(r, cellBodyTarget(cellCheckboxTarget(4, 0, false)), { detail: 2 });
  assert.strictEqual(r.state.posted.length, before, 'double click: no cell toggle');
});

// Internal anchor links ([Text](#slug)) resolve the target heading via a lookup
// scoped to #content and scroll to it; a missing target is a no-op (no toggle
// fallthrough). Helper seeds content.querySelector with the expected heading.
function anchorTarget(href) {
  // A rendered internal anchor is converted to a .mw-anchor button (id in data-id,
  // no href); external/cross-file and the bare '#' stay plain <a href>.
  const internal = href.startsWith('#') && href !== '#';
  const a = {
    dataset: internal ? { id: href.slice(1) } : {},
    getAttribute: (n) => (n === 'href' ? href : null)
  };
  a.closest = (s) => {
    if (s === '.mw-anchor') return internal ? a : null;
    if (s === 'a') return a;
    return null;
  };
  return a;
}

function seedHeading(r, selector, top) {
  const el = { getBoundingClientRect: () => ({ top }) };
  r.document.getElementById('content').querySelector = (s) => (s === selector ? el : null);
  return el;
}

test('clicking an internal anchor link scrolls to the target heading', () => {
  const r = runWebviewScript({ scrollY: 100 });
  seedHeading(r, '#sec-two', 250); // absTop = 250 + scrollY 100
  fireClick(r, anchorTarget('#sec-two'));
  assert.strictEqual(r.state.scrolledTo, 350, 'scrolls to the target position');
  assert.ok(!r.state.posted.some((m) => m.type === 'toggle'), 'no task toggle');
});

test('an encoded anchor href is decoded before the lookup', () => {
  const r = runWebviewScript();
  seedHeading(r, '#gr\u00fc\u00dfe', 40); // ASCII source, unicode id
  fireClick(r, anchorTarget('#gr%C3%BC%C3%9Fe'));
  assert.strictEqual(r.state.scrolledTo, 40);
});

test('a malformed percent-escape in the href falls back to the literal hash', () => {
  // A raw HTML anchor (html: true) can carry a malformed escape like "#100%";
  // decodeURIComponent would throw. The handler must degrade to the literal
  // hash and still resolve it, not die with an URIError.
  const r = runWebviewScript();
  const el = { getBoundingClientRect: () => ({ top: 60 }) };
  r.document.getElementById('content').querySelector = () => el; // literal-hash lookup resolves
  assert.doesNotThrow(() => fireClick(r, anchorTarget('#100%')));
  assert.strictEqual(r.state.scrolledTo, 60, 'resolves the literal hash');
});

test('a heading whose slug collides with a skeleton id is still navigable', () => {
  // "# Content" slugs to "content", which also names the #content container.
  // A document-wide getElementById would hit the container; the scoped lookup
  // (content.querySelector) must find the heading descendant instead.
  const r = runWebviewScript();
  seedHeading(r, '#content', 500);
  fireClick(r, anchorTarget('#content'));
  assert.strictEqual(r.state.scrolledTo, 500, 'scoped to the heading, not the container');
});

test('an empty hash (href="#") is a no-op without an exception', () => {
  const r = runWebviewScript();
  // The empty-hash guard must short-circuit before querySelector: '#' alone is
  // an invalid selector and CSS.escape('') would build one.
  r.document.getElementById('content').querySelector = () => {
    throw new Error('querySelector must not run for an empty hash');
  };
  const before = r.state.posted.length;
  assert.doesNotThrow(() => fireClick(r, anchorTarget('#')));
  assert.strictEqual(r.state.scrolledTo, null, 'no scroll');
  assert.strictEqual(r.state.posted.length, before, 'no message posted');
});

test('an internal anchor with no matching target does nothing', () => {
  const r = runWebviewScript();
  r.document.getElementById('content').querySelector = () => null;
  const before = r.state.posted.length;
  fireClick(r, anchorTarget('#missing'));
  assert.strictEqual(r.state.scrolledTo, null, 'no scroll');
  assert.strictEqual(r.state.posted.length, before, 'no message posted');
});

test('the anchor lookup CSS.escapes the hash (a raw dotted fragment is escaped)', () => {
  // Records the exact selector: proves CSS.escape is load-bearing. Dropping it
  // would query '#foo.bar' (a compound selector) instead of the escaped '#foo\\.bar'.
  const r = runWebviewScript();
  let seen = null;
  r.document.getElementById('content').querySelector = (sel) => { seen = sel; return null; };
  fireClick(r, anchorTarget('#foo.bar'));
  assert.strictEqual(seen, '#foo\\.bar', 'the "." must be CSS.escape-d');
});

test('a non-hash link (external or cross-file) is left to the browser, no scroll/toggle', () => {
  for (const href of ['https://example.com', './other.md#y']) {
    const r = runWebviewScript();
    // Would throw if the code queried it: proves the non-hash href never reaches the lookup.
    r.document.getElementById('content').querySelector = () => { throw new Error('must not query for ' + href); };
    const before = r.state.posted.length;
    assert.doesNotThrow(() => fireClick(r, anchorTarget(href)), href);
    assert.strictEqual(r.state.scrolledTo, null, href);
    assert.strictEqual(r.state.posted.length, before, href);
  }
});

test('internal anchors are converted to buttons (no href, id in data-id) so no native #id jump fires (#44)', () => {
  const r = runWebviewScript({ expose: ['convertInternalAnchors'] });
  const mk = (href) => {
    const attrs = { href };
    return {
      getAttribute: (n) => attrs[n], removeAttribute: (n) => { delete attrs[n]; },
      setAttribute: (n, v) => { attrs[n] = v; }, dataset: {},
      classList: { _c: [], add(c) { this._c.push(c); }, contains(c) { return this._c.includes(c); } },
      _attrs: attrs
    };
  };
  const internal = mk('#sec'), bare = mk('#');
  // The browser scopes a[href^="#"] to internal + the bare '#'; external never reaches it.
  r.document.getElementById('content').querySelectorAll = (sel) =>
    (sel === 'a[href^="#"]' ? [internal, bare] : []);
  r.fns.convertInternalAnchors();
  assert.strictEqual(internal.dataset.id, 'sec', 'id moved to data-id');
  assert.strictEqual(internal._attrs.href, undefined, 'href removed so no native jump fights navigateToHash');
  assert.strictEqual(internal._attrs.role, 'button');
  assert.ok(internal.classList.contains('mw-anchor'));
  assert.strictEqual(bare._attrs.href, '#', 'a bare "#" is left a plain anchor');
  assert.ok(!bare.classList.contains('mw-anchor'));
});

test('batch select (Ctrl/Shift) fires from the checkbox, never from the label', () => {
  const r = runWebviewScript({ expose: ['selection'] });
  // Ctrl on the label does NOT add to the batch selection (stays a plain toggle).
  fireClick(r, labelTarget(5, false), { ctrlKey: true });
  assert.strictEqual(r.fns.selection.size, 0, 'label Ctrl+click is not batch');
  assert.strictEqual(r.state.posted.at(-1).type, 'toggle');
  // Ctrl on the checkbox is membership batch: it adds and posts nothing.
  const before = r.state.posted.length;
  fireClick(r, listCheckboxTarget(5, false), { ctrlKey: true });
  assert.ok(r.fns.selection.has(5), 'checkbox Ctrl+click adds to the selection');
  assert.strictEqual(r.state.posted.length, before, 'membership batch posts no toggle');
});

test('Escape clears the batch selection (regression)', () => {
  const r = runWebviewScript({ expose: ['selection'] });
  fireClick(r, listCheckboxTarget(7, false), { ctrlKey: true });
  assert.ok(r.fns.selection.has(7));
  r.state.listeners.document['keydown']({ key: 'Escape' });
  assert.strictEqual(r.fns.selection.size, 0, 'Escape empties the selection');
});

// --- Preview readability settings (#25 follow-up): three opt-in/opt-out
// knobs, defaults reproduce #25 exactly. ---

const sendCfg = (r, over) =>
  r.send(Object.assign({ type: 'config', maxWidth: '980px', minimap: MM() }, over));

test('bareClickToggles: selection off always toggles; on it delegates to the gate', () => {
  const { fns } = runWebviewScript({ expose: ['bareClickToggles'] });
  // textSelection off: no text interaction to protect -> always toggles.
  assert.strictEqual(fns.bareClickToggles(false, 'some text', 2), true);
  // textSelection on: defers to canToggleFromBareClick.
  assert.strictEqual(fns.bareClickToggles(true, '', 1), true);
  assert.strictEqual(fns.bareClickToggles(true, 'sel', 1), false);
  assert.strictEqual(fns.bareClickToggles(true, '', 2), false);
});

test('config toggles mw-no-text-select only when textSelection is false', () => {
  const r = runWebviewScript();
  sendCfg(r, { textSelection: true });
  assert.strictEqual(!!r.state.bodyClasses['mw-no-text-select'], false);
  sendCfg(r, { textSelection: false });
  assert.strictEqual(!!r.state.bodyClasses['mw-no-text-select'], true);
});

test('config sets mw-task-text-cursor only with textSelection on AND the cursor flag', () => {
  const r = runWebviewScript();
  sendCfg(r, { textSelection: true, taskRowTextCursor: true });
  assert.strictEqual(!!r.state.bodyClasses['mw-task-text-cursor'], true);
  // cursor flag off -> absent
  sendCfg(r, { textSelection: true, taskRowTextCursor: false });
  assert.strictEqual(!!r.state.bodyClasses['mw-task-text-cursor'], false);
  // textSelection off wins even with the cursor flag on
  sendCfg(r, { textSelection: false, taskRowTextCursor: true });
  assert.strictEqual(!!r.state.bodyClasses['mw-task-text-cursor'], false);
});

test('taskBatchSelect "row": Ctrl/Shift on the label drives the batch', () => {
  const r = runWebviewScript({ expose: ['selection'] });
  // The range branch reads the task list off the DOM; supply line-tagged lis.
  const content = r.document.getElementById('content');
  content.querySelectorAll = (sel) => sel === 'li.task'
    ? [2, 3, 4, 5].map((n) => ({ dataset: { line: String(n) }, classList: { toggle() {} } }))
    : [];
  sendCfg(r, { taskBatchSelect: 'row' });
  // Ctrl on the label is membership batch: grows the selection, posts nothing.
  const before = r.state.posted.length;
  fireClick(r, labelTarget(2, false), { ctrlKey: true });
  assert.ok(r.fns.selection.has(2), 'Ctrl on label adds to the selection in row mode');
  assert.strictEqual(r.state.posted.length, before, 'membership batch posts no toggle');
  // Shift after the anchor range-selects 2..5 inclusive.
  fireClick(r, labelTarget(5, false), { shiftKey: true });
  assert.ok(r.fns.selection.has(5), 'Shift on label range-selects in row mode');
  assert.ok(r.fns.selection.has(3), 'range fills in between');
});

test('taskBatchSelect "checkbox" (default): Ctrl on the label plain-toggles', () => {
  const r = runWebviewScript({ expose: ['selection'] });
  sendCfg(r, { taskBatchSelect: 'checkbox' });
  fireClick(r, labelTarget(2, false), { ctrlKey: true });
  assert.strictEqual(r.fns.selection.size, 0, 'label Ctrl+click is not batch in checkbox mode');
  assert.strictEqual(r.state.posted.at(-1).type, 'toggle');
});

test('textSelection false: the label toggles despite a selection or a double click', () => {
  const r = runWebviewScript();
  sendCfg(r, { textSelection: false });
  r.window.__selection = 'highlighted text'; // would block a gated bare click
  fireClick(r, labelTarget(2, false));
  assert.strictEqual(r.state.posted.at(-1).type, 'toggle', 'selection present still toggles');
  const before = r.state.posted.length;
  fireClick(r, labelTarget(2, false), { detail: 2 });
  assert.strictEqual(r.state.posted.length, before + 1, 'double click still toggles');
  assert.strictEqual(r.state.posted.at(-1).type, 'toggle');
});

test('mw-no-text-select locks selection; the text-cursor rules apply to the row', () => {
  assert.match(ruleBody('body.mw-no-text-select'), /user-select:\s*none/);
  assert.match(ruleBody('body.mw-task-text-cursor .task-row'), /cursor:\s*text/);
  assert.match(ruleBody('body.mw-task-text-cursor .task-row input[type=checkbox]'),
    /cursor:\s*pointer/);
});

test('getWebviewHtml embeds CSP, a script nonce and both webview asset URIs', () => {
  install();
  const views = loadFresh('src/views.js');
  views.setExtensionUri('EXT');
  const webview = {
    cspSource: 'vscode-webview://host',
    asWebviewUri: (uri) => 'https://webview/' + String(uri)
  };
  const html = views.getWebviewHtml(webview);
  // Content-Security-Policy with a nonce'd script source.
  assert.match(html, /<meta http-equiv="Content-Security-Policy"/);
  const nonce = html.match(/script-src 'nonce-([A-Za-z0-9]+)'/)[1];
  assert.ok(nonce.length >= 16, 'nonce is present and non-trivial');
  // The <script> tag carries the very same nonce.
  assert.match(html, new RegExp('<script nonce="' + nonce + '" src='));
  // Both media assets are linked through asWebviewUri (mock joins with "/").
  assert.match(html, /href="https:\/\/webview\/EXT\/media\/webview\.css"/);
  assert.match(html, /src="https:\/\/webview\/EXT\/media\/webview\.js"/);
  // style-src must allow inline styles: Shiki emits token colors as inline
  // style="color:..." attributes; a strict style-src would blank them out
  // (the headless DOM tests don't parse innerHTML, so only this guards it).
  const styleSrc = html.match(/style-src ([^;]+);/)[1];
  assert.match(styleSrc, /'unsafe-inline'/);
});

// --- Table of contents (#32): scroll-spy base + rail/FAB switch. The pure
// decision functions are unit-tested directly; the DOM/interaction wiring is
// exercised through the mock. Real rail/FAB rendering and overlay interaction
// need a live webview and are verified manually. ---

const TOC_FNS = ['activeHeadingIndex', 'ancestorChain', 'tocTree', 'railFits'];

test('activeHeadingIndex: the last heading scrolled past the activation line', () => {
  const { fns } = runWebviewScript({ expose: TOC_FNS });
  const tops = [0, 1000, 2000];
  assert.strictEqual(fns.activeHeadingIndex(tops, 0, 8), 0);     // h1 sits at the top
  assert.strictEqual(fns.activeHeadingIndex(tops, 1500, 8), 1);  // past the 2nd
  assert.strictEqual(fns.activeHeadingIndex(tops, 5000, 8), 2);  // past the last
});

test('activeHeadingIndex: -1 while the reader is above the first heading', () => {
  const { fns } = runWebviewScript({ expose: TOC_FNS });
  assert.strictEqual(fns.activeHeadingIndex([50, 100], 0, 8), -1); // prose before h1
  assert.strictEqual(fns.activeHeadingIndex([], 0, 8), -1);        // no headings
});

test('ancestorChain: root-first chain of strictly-smaller levels', () => {
  const { fns } = runWebviewScript({ expose: TOC_FNS });
  // h1 > h2 > h3 > h2(active): drops the h3, keeps h1 and the nearest h2 above.
  assert.deepStrictEqual(fns.ancestorChain([1, 2, 3, 2], 3), [0, 3]);
  assert.deepStrictEqual(fns.ancestorChain([1, 2, 3], 2), [0, 1, 2]);
  assert.deepStrictEqual(fns.ancestorChain([1], 0), [0]);
});

test('ancestorChain: a level jump (h1 -> h4) takes the nearest shallower heading', () => {
  const { fns } = runWebviewScript({ expose: TOC_FNS });
  assert.deepStrictEqual(fns.ancestorChain([1, 4], 1), [0, 1]);
  assert.deepStrictEqual(fns.ancestorChain([1, 4, 2], 2), [0, 2]);
  assert.deepStrictEqual(fns.ancestorChain([2, 4], -1), []); // nothing active
});

test('tocTree: nests by level and honors jumps', () => {
  const { fns } = runWebviewScript({ expose: TOC_FNS });
  const tree = fns.tocTree([1, 2, 2]);
  assert.strictEqual(tree.length, 1);
  assert.strictEqual(tree[0].idx, 0);
  assert.deepStrictEqual(tree[0].children.map((n) => n.idx), [1, 2]);
  // h1 -> h4 jump: the h4 still nests under the h1.
  const jump = fns.tocTree([1, 4]);
  assert.deepStrictEqual(jump[0].children.map((n) => n.idx), [1]);
  // Two top-level roots when the first level is deeper than the second.
  assert.strictEqual(fns.tocTree([2, 1]).length, 2);
  assert.deepStrictEqual(fns.tocTree([]), []); // document without headings
});

test('railFits: viewport must hold content + TOC reserve + the opposite side', () => {
  const { fns } = runWebviewScript({ expose: TOC_FNS });
  assert.strictEqual(fns.railFits(1600, 980, 240, 104), true);
  assert.strictEqual(fns.railFits(1200, 980, 240, 104), false);
  assert.strictEqual(fns.railFits(1252, 980, 240, 32), true); // exact fit (>=)
});

// Feed headings to the scroll-spy through content.querySelectorAll.
function headingEl(tag, id, text, top) {
  return { tagName: tag.toUpperCase(), id, textContent: text, style: {},
    getBoundingClientRect: () => ({ top }) };
}
function withHeadings(r, headings) {
  const content = r.document.getElementById('content');
  content.querySelectorAll = (sel) => (sel === 'h1,h2,h3,h4,h5,h6' ? headings : []);
}
const tocCfg = (over) => Object.assign({ enabled: true, mode: 'auto' }, over);

test('TOC auto mode: rail when the viewport is wide, fab when it is narrow', () => {
  const wide = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(wide, [headingEl('h1', 'a', 'A', 0), headingEl('h2', 'b', 'B', 100)]);
  wide.send({ type: 'config', maxWidth: '980px', minimap: MM({ enabled: false }), toc: tocCfg() });
  wide.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(wide.state.bodyClasses['has-toc'], true);
  assert.strictEqual(wide.state.bodyClasses['toc-rail'], true);
  assert.strictEqual(wide.state.bodyClasses['toc-fab'], false);

  const narrow = runWebviewScript({ viewWidth: 700, docHeight: 8000, viewHeight: 800 });
  withHeadings(narrow, [headingEl('h1', 'a', 'A', 0)]);
  narrow.send({ type: 'config', maxWidth: '980px', minimap: MM({ enabled: false }), toc: tocCfg() });
  narrow.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(narrow.state.bodyClasses['toc-fab'], true);
  assert.strictEqual(narrow.state.bodyClasses['toc-rail'], false);
});

test('TOC mode overrides force rail/fab regardless of width', () => {
  const railed = runWebviewScript({ viewWidth: 400, docHeight: 8000, viewHeight: 800 });
  withHeadings(railed, [headingEl('h1', 'a', 'A', 0)]);
  railed.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg({ mode: 'rail' }) });
  railed.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(railed.state.bodyClasses['toc-rail'], true);

  const fabbed = runWebviewScript({ viewWidth: 3000, docHeight: 8000, viewHeight: 800 });
  withHeadings(fabbed, [headingEl('h1', 'a', 'A', 0)]);
  fabbed.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg({ mode: 'fab' }) });
  fabbed.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(fabbed.state.bodyClasses['toc-fab'], true);
});

test('the TOC takes the side opposite the minimap', () => {
  const r = runWebviewScript({ viewWidth: 1600 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ side: 'right' }), toc: tocCfg() });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['toc-left'], true); // minimap right -> toc left
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ side: 'left' }), toc: tocCfg() });
  assert.strictEqual(r.state.bodyClasses['toc-left'], false); // minimap left -> toc right
});

test('toc.enabled false hides the TOC entirely', () => {
  const r = runWebviewScript({ viewWidth: 1600 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg({ enabled: false }) });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['has-toc'], false);
  assert.strictEqual(!!r.state.bodyClasses['toc-rail'], false);
});

test('undefined toc config keeps the TOC enabled (defensive default)', () => {
  const r = runWebviewScript({ viewWidth: 1600 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: undefined });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['has-toc'], true);
});

test('a document without headings shows no TOC', () => {
  const r = runWebviewScript({ viewWidth: 1600 });
  // no withHeadings: content.querySelectorAll returns [] for the heading query
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(r.state.bodyClasses['has-toc'], false);
});

test('the scroll-spy tracks the active heading across scroll positions', () => {
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, expose: ['scrollSpy'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h1', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg({ mode: 'rail' }) });
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.fns.scrollSpy.active, 0);
  r.window.scrollY = 1500;
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.fns.scrollSpy.active, 1);
  r.window.scrollY = 5000;
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.fns.scrollSpy.active, 2);
});

test('the initial TOC state is applied deterministically above the first heading', () => {
  // active = -1 (reader above the first heading): the freshly rendered TOC must
  // collapse subsections up front, matching the state a scroll-back-to-top
  // produces (update() emits only on change, so the rebuild forces it).
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800,
    expose: ['tocBranches'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg({ mode: 'rail' }) });
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true,
    'the h1 subsection is collapsed initially (active = -1)');
});

test('clicking a TOC entry scrolls to its heading', () => {
  const r = runWebviewScript({ scrollY: 0 });
  const heading = { getBoundingClientRect: () => ({ top: 500 }) };
  r.document.getElementById('content').querySelector = (s) => (s === '#sec' ? heading : null);
  const link = { dataset: { idx: '0', id: 'sec' } };
  link.closest = (s) => (s === '.toc-link' ? link : null);
  r.state.els['toc']._listeners['click']({ target: link, preventDefault() {} });
  assert.strictEqual(r.state.scrolledTo, 500);
});

test('navigation lands a heading at its own per-heading bars margin, not the transient global offset (#44)', () => {
  // Each heading carries its own published scroll-margin-top (its bars height incl.
  // its sticky depth). Using it - not the global topBarsOffset of the current
  // position - is what makes the first jump from the top land correctly instead of
  // shifting a few px once the sticky stack appears.
  const r = runWebviewScript({ scrollY: 0, expose: ['navigateToHash'] });
  const heading = { style: { scrollMarginTop: '72px' }, getBoundingClientRect: () => ({ top: 4000 }) };
  r.document.getElementById('content').querySelector = (s) => (s === '#deep' ? heading : null);
  r.fns.navigateToHash('deep', true);
  assert.strictEqual(r.state.scrolledTo, 4000 - 72, 'landed at absTop minus the heading own margin');
  assert.strictEqual(r.state.scrolledSmooth, true, 'and smoothly');
});

test('the FAB opens the overlay and Escape closes it', () => {
  const r = runWebviewScript({ viewWidth: 500, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  assert.strictEqual(r.state.bodyClasses['toc-fab'], true);
  r.state.els['toc-fab']._listeners['click']();
  assert.strictEqual(r.state.bodyClasses['toc-open'], true);
  r.state.listeners.document['keydown']({ key: 'Escape' });
  assert.strictEqual(r.state.bodyClasses['toc-open'], false);
});

test('the backdrop click closes the overlay', () => {
  const r = runWebviewScript({ viewWidth: 500, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0)]);
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  r.state.els['toc-fab']._listeners['click']();
  assert.strictEqual(r.state.bodyClasses['toc-open'], true);
  r.state.els['toc-backdrop']._listeners['click']();
  assert.strictEqual(r.state.bodyClasses['toc-open'], false);
});

// --- TOC stylesheet contract (#32): rail reserve + FAB/overlay visibility. ---

test('the rail reserves body padding on the TOC side', () => {
  assert.match(ruleBody('body.has-toc.toc-rail.toc-left'), /padding-left:\s*240px/);
  assert.match(ruleBody('body.has-toc.toc-rail:not(.toc-left)'), /padding-right:\s*240px/);
});

test('the FAB and overlay are hidden until their body classes are set', () => {
  assert.match(ruleBody('#toc'), /display:\s*none/);
  assert.match(ruleBody('#toc-fab'), /display:\s*none/);
  assert.match(ruleBody('#toc-backdrop'), /display:\s*none/);
  assert.match(ruleBody('body.has-toc.toc-rail #toc'), /display:\s*flex/);
  assert.match(ruleBody('body.has-toc.toc-fab #toc-fab'), /display:\s*inline-flex/);
  assert.match(ruleBody('body.toc-open #toc-backdrop'), /display:\s*block/);
});

test('headings carry a scroll-margin-top so anchors clear the top edge', () => {
  assert.match(ruleBody('h1'), /scroll-margin-top/);
});

test('the TOC rail is layout/paint contained like the top bars', () => {
  assert.match(ruleBody('#toc'), /contain:\s*layout\s+paint/);
});

// --- Breadcrumb + sticky-scroll stack (#33): pure sibling/scroll-margin logic,
// the class/config wiring through the mock, and the dropdown interaction. The
// live sticky pinning and the dropdown rendering need a real webview and are
// verified manually. ---

const TOP_FNS = ['siblingHeadings', 'topBarsHeight', 'rootLabel'];

// A config message that turns both top bars on (with the minimap/TOC defaults).
function topConfig(over) {
  return Object.assign({
    type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg(),
    breadcrumb: { enabled: true }, stickyScroll: { enabled: true }
  }, over);
}

test('each heading gets its own scroll-margin-top = its bars height (#44)', () => {
  // A VS Code webview performs the native #id fragment jump on a control-link click
  // (preventDefault does not stop it), landing the heading at its scroll-margin-top.
  // The shared --toc-scroll-margin is the document maximum, so a shallow heading
  // landed too low and the scroll-spy's activation line (at that heading's own,
  // smaller bars height) fell above it - the previous heading stayed selected. Each
  // heading now carries its own margin = breadcrumb + its chain depth in sticky rows.
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  const hs = [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200),
    headingEl('h3', 'c', 'C', 300), headingEl('h1', 'd', 'D', 4000)];
  withHeadings(r, hs);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(hs[0].style.scrollMarginTop, (28 + 1 * 22) + 'px', 'H1 alone: depth 1');
  assert.strictEqual(hs[2].style.scrollMarginTop, (28 + 3 * 22) + 'px', 'H3<H2<H1: depth 3');
  assert.strictEqual(hs[3].style.scrollMarginTop, (28 + 1 * 22) + 'px', 'H1 again: depth 1');
});

test('siblingHeadings: same-level headings under the same parent, in order', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  // h1, h2, h2, h2 -> the three h2 are siblings of each other.
  assert.deepStrictEqual(fns.siblingHeadings([1, 2, 2, 2], 2), [1, 2, 3]);
  // The h1 is the only root -> just itself.
  assert.deepStrictEqual(fns.siblingHeadings([1, 2, 2, 2], 0), [0]);
});

test('siblingHeadings: a deeper heading between siblings (child of a sibling) is skipped', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  // h1, h2, h3, h2: the two h2 are siblings; the h3 (child of the first h2) is
  // skipped, not a boundary.
  assert.deepStrictEqual(fns.siblingHeadings([1, 2, 3, 2], 1), [1, 3]);
  assert.deepStrictEqual(fns.siblingHeadings([1, 2, 3, 2], 3), [1, 3]);
});

test('siblingHeadings: a shallower heading is the parent boundary', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  // h2, h1, h2: the leading h2 belongs to a different parent (the h1 boundary
  // sits between it and the trailing h2), so it is not a sibling.
  assert.deepStrictEqual(fns.siblingHeadings([2, 1, 2], 2), [2]);
});

test('siblingHeadings: a level jump (h1 -> h4) groups the h4 with its bounded run', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  // h1, h4, h4, h2, h4: siblings of index 1 are the two h4 directly under the
  // h1 (bounded by the h2), not the trailing h4 in the h2 section.
  assert.deepStrictEqual(fns.siblingHeadings([1, 4, 4, 2, 4], 1), [1, 2]);
  assert.deepStrictEqual(fns.siblingHeadings([1, 4, 4, 2, 4], 4), [4]);
});

test('siblingHeadings: single child and the inactive (-1) case', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  assert.deepStrictEqual(fns.siblingHeadings([1, 2], 1), [1]); // only child
  assert.deepStrictEqual(fns.siblingHeadings([1, 2, 3], -1), []); // active = -1
  assert.deepStrictEqual(fns.siblingHeadings([], 0), []);         // no headings
});

test('rootLabel: the leading H1 is the root label, else a neutral fallback', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  assert.strictEqual(fns.rootLabel([{ level: 1, text: 'My Title' }]), 'My Title');
  assert.strictEqual(fns.rootLabel([{ level: 2, text: 'Sub' }]), 'Document'); // no leading H1
  assert.strictEqual(fns.rootLabel([{ level: 1, text: '' }]), 'Document');    // empty H1
  assert.strictEqual(fns.rootLabel([]), 'Document');                          // no headings
});

test('topBarsHeight: computed from the fixed geometry (breadcrumb 28 + rows x 22)', () => {
  const { fns } = runWebviewScript({ expose: TOP_FNS });
  assert.strictEqual(fns.topBarsHeight(false, 0), 0, 'both bars hidden -> 0');
  assert.strictEqual(fns.topBarsHeight(true, 0), 28, 'breadcrumb only');
  assert.strictEqual(fns.topBarsHeight(true, 3), 28 + 66, 'breadcrumb + 3 sticky rows');
  assert.strictEqual(fns.topBarsHeight(false, 2), 44, 'stack only');
});

test('the top bars show for a document with headings and publish the constant vars', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true, 'breadcrumb bar reserved');
  // At the top (active = -1) there is no chain, so the sticky stack is hidden.
  assert.strictEqual(r.state.bodyClasses['has-sticky'], false, 'no sticky stack above the first heading');
  // The bar vars are constants published once (not measured): --breadcrumb-height
  // is the fixed 28px, --toc-scroll-margin the maximum stack height (28 + 5x22 + 8).
  assert.strictEqual(r.state.cssVars['--breadcrumb-height'], '28px');
  assert.strictEqual(r.state.cssVars['--toc-scroll-margin'], (28 + 5 * 22 + 8) + 'px');
});

test('the sticky stack appears once the reader is under a heading', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.state.bodyClasses['has-sticky'], false);
  r.window.scrollY = 700; // past both headings -> active chain [h1, h2]
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.state.bodyClasses['has-sticky'], true, 'the chain pins as a stack');
});

test('the sticky table header docks FLUSH under the current stack, per-thead not on :root (#44 perf)', () => {
  // The header docks directly under the CURRENT stack (breadcrumb + the current
  // chain's rows), so a shallow section docks under its shorter stack rather than a
  // document-wide maximum that left a gap. --sticky-head-top is an inherited custom
  // property: written on :root it re-resolves inheritance for the whole document (a
  // measured 10x style-recalc blow-up), so it is written on the thead subtrees - its
  // only consumers - and only when the depth changes, never per scroll frame.
  assert.match(ruleBody('th'), /top:\s*var\(--sticky-head-top/, 'th docks at the var');

  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  // Max depth 3 (H1>H2>H3), but with a shallow H1>H2 section further down.
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200),
    headingEl('h3', 'c', 'C', 300), headingEl('h1', 'd', 'D', 3000), headingEl('h2', 'e', 'E', 3100)]);
  // Observe the dock var on a thead; the mock content has none of its own. Compose
  // with withHeadings' selector so heading collection still works.
  const writes = [];
  const thead = { style: { setProperty: (k, v) => { if (k === '--sticky-head-top') writes.push(v); } } };
  const content = r.document.getElementById('content');
  const baseQSA = content.querySelectorAll;
  content.querySelectorAll = (sel) => (sel === 'thead' ? [thead] : baseQSA(sel));
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  // Under the deep H3 (chain h1>h2>h3): dock = breadcrumb 28 + 3 rows x 22 = 94.
  r.window.scrollY = 400; r.state.listeners.window['scroll']();
  assert.strictEqual(writes.at(-1), (28 + 3 * 22) + 'px', 'docks flush under the 3-row stack');
  // Into the shallow H1>H2 section (chain h1>h2): dock drops to 28 + 2x22 = 72 -
  // flush under the shorter stack, NOT the document max of 94 (no gap).
  r.window.scrollY = 3300; r.state.listeners.window['scroll']();
  assert.strictEqual(writes.at(-1), (28 + 2 * 22) + 'px', 'follows the current shallower stack');
  // A scroll that stays inside the section (no depth change) writes nothing more.
  const n = writes.length;
  r.window.scrollY = 3400; r.state.listeners.window['scroll']();
  assert.strictEqual(writes.length, n, 'no per-frame write when the depth is unchanged');
});

test('breadcrumb.enabled false hides the breadcrumb but keeps the sticky stack', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  r.send(topConfig({ breadcrumb: { enabled: false } }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], false, 'breadcrumb off');
  assert.strictEqual(r.state.bodyClasses['has-sticky'], true, 'sticky stays on independently');
});

test('stickyScroll.enabled false hides the stack but keeps the breadcrumb', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  r.send(topConfig({ stickyScroll: { enabled: false } }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.state.bodyClasses['has-sticky'], false, 'sticky off even when scrolled');
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true, 'breadcrumb stays on independently');
});

test('undefined top-bar config keeps both bars enabled (defensive default)', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100)]);
  // No breadcrumb/stickyScroll fields in the config message at all.
  r.send({ type: 'config', maxWidth: '980px', minimap: MM(), toc: tocCfg() });
  r.send({ type: 'render', html: 'x' });
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true);
  r.window.scrollY = 700;
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.state.bodyClasses['has-sticky'], true);
});

test('a document without headings shows no top bars', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  r.send(topConfig());
  r.send({ type: 'render', html: '<p>x</p>' });
  assert.strictEqual(!!r.state.bodyClasses['has-breadcrumb'], false);
  assert.strictEqual(!!r.state.bodyClasses['has-sticky'], false);
});

test('above the first heading the breadcrumb root segment scrolls to the top, no picker', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' }); // scrollY 0 -> active = -1 -> root segment
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true, 'the bar is present, not empty');
  // The root segment carries the sentinel index -1.
  r.state.els['breadcrumb']._listeners['click'](
    { target: segTarget(-1, '#', '.breadcrumb-seg'), preventDefault() {} });
  assert.strictEqual(r.state.scrolledTo, 0, 'root scrolls to the top');
  assert.strictEqual(!!r.state.bodyClasses['breadcrumb-dropdown-open'], false, 'no sibling picker for root');
});

test('toggling a top-bar setting live takes effect at once (force-emit, no scroll)', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  r.state.listeners.window['scroll'](); // active chain [h1, h2]
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], true);
  assert.strictEqual(r.state.bodyClasses['has-sticky'], true);
  // A config message alone (no render, no scroll event) must apply immediately.
  r.send(topConfig({ breadcrumb: { enabled: false }, stickyScroll: { enabled: false } }));
  assert.strictEqual(r.state.bodyClasses['has-breadcrumb'], false, 'breadcrumb hidden at once');
  assert.strictEqual(r.state.bodyClasses['has-sticky'], false, 'sticky hidden at once');
});

test('the scroll-spy activation line sits below the top-bar inset (TOC-click marking)', () => {
  // Regression for the off-by-one the owner saw: navigateToHash lands a target
  // at scrollY + topBarsOffset, so the activation line must include that inset,
  // else the heading above stays marked active.
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, expose: ['scrollSpy'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h1', 'b', 'B', 1000)]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  // b (top 1000) lands 30px below the viewport top - above the bare 8px line but
  // below a 50px bar stack. With the inset it is active; without it, 'a' would be.
  r.fns.scrollSpy.setTopInset(50);
  r.window.scrollY = 970;
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.fns.scrollSpy.active, 1, 'the heading below the bars is active, not the one above');
});

test('a #id jump to a deep heading marks that heading, not its parent, even from the top (#44)', () => {
  // The in-document TOC lives at the top, so the active heading before the click is
  // -1 and the global inset is 0. A per-heading activation line is what makes the
  // landed heading active regardless of that stale global inset: the native jump
  // lands a deep h3 at its own bars (28 + 3*22 = 94) below the top, and the flat
  // 8px line would fall 86px above it - the h2 parent would stay marked.
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, expose: ['scrollSpy'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200),
    headingEl('h3', 'c', 'C', 3000)]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 3000 - (28 + 3 * 22); // where the native #id jump lands c (its scroll-margin)
  r.state.listeners.window['scroll']();
  assert.strictEqual(r.fns.scrollSpy.active, 2, 'the clicked h3 is active, not its h2 parent');
});

test('a depth-changing drag never measures the stack nor rewrites the margin var (#44 review 6)', () => {
  // The freeze fix: the stack height is computed (rows x row height), never
  // measured, and --toc-scroll-margin is a constant published once at init. So a
  // drag that changes the chain DEPTH every step still forces 0 layout reads on
  // the stack and 0 --toc-scroll-margin writes (the round-8 regress was a var
  // write per depth change, which recalced every heading's scroll-margin).
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h2', 'b', 'B', 1000),
    headingEl('h3', 'c', 'C', 2000), headingEl('h2', 'd', 'D', 3000)]);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  let measures = 0;
  r.state.els['sticky-scroll'].getBoundingClientRect = () => { measures++; return { height: 24 }; };
  let marginWrites = 0;
  const root = r.document.documentElement.style;
  const realSet = root.setProperty;
  root.setProperty = (k, v) => { if (k === '--toc-scroll-margin') marginWrites++; return realSet(k, v); };
  for (const y of [1500, 2500, 3500, 2500, 1500]) { // chain depth 2 -> 3 -> 2 -> 3 -> 2
    r.window.scrollY = y;
    r.state.listeners.window['scroll']();
  }
  assert.strictEqual(measures, 0, 'the stack height is computed, never measured');
  assert.strictEqual(marginWrites, 0, 'the scroll-margin var is a constant, not rewritten per depth change');
});

test('the active TOC entry is scrolled into view only when it is outside the panel', () => {
  // Performance (#44 review 4): the reveal must not force a reflow per active
  // change - it is coalesced into a rAF and skips the scroll when the entry is
  // already visible.
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800,
    expose: ['tocLinks'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h1', 'b', 'B', 1000)]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  r.state.els['toc'].getBoundingClientRect = () => ({ top: 0, bottom: 400 });
  const linkB = r.fns.tocLinks[1];
  let scrolled = 0;
  linkB.scrollIntoView = () => { scrolled++; };
  linkB.getBoundingClientRect = () => ({ top: 100, bottom: 130 }); // inside [0,400]
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active = b, in view
  assert.strictEqual(scrolled, 0, 'an in-view active entry is not scrolled');
  linkB.getBoundingClientRect = () => ({ top: 500, bottom: 530 }); // below the panel bottom
  r.window.scrollY = 0; r.state.listeners.window['scroll'](); // active -1
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active = b again, out of view
  assert.strictEqual(scrolled, 1, 'an out-of-view active entry is scrolled into view');
});

// --- Scroll-sync throttle + IntersectionObserver removal (#44 review 5). ---

test('scrollPostDecision: skip a sub-line change, post once the window elapsed, else defer', () => {
  const { fns } = runWebviewScript({ expose: ['scrollPostDecision'] });
  // Same line as last -> skip (delta gate).
  assert.strictEqual(fns.scrollPostDecision(5.0, 5.0, 1000, 0, 33, 0.01), 'skip');
  // Meaningful change, window elapsed -> post.
  assert.strictEqual(fns.scrollPostDecision(6.0, 5.0, 1000, 900, 33, 0.01), 'post');
  // Meaningful change, still within the window -> defer (trailing).
  assert.strictEqual(fns.scrollPostDecision(6.0, 5.0, 910, 900, 33, 0.01), 'defer');
  // First post (lastLine -1) is never skipped.
  assert.strictEqual(fns.scrollPostDecision(0, -1, 1000, 0, 33, 0.01), 'post');
});

function seedLineEntries(r, entries) {
  const els = entries.map((e) => ({
    dataset: { line: String(e.line) },
    getBoundingClientRect: () => ({ top: e.top - r.window.scrollY, height: e.height || 20 })
  }));
  r.document.getElementById('content').querySelectorAll = (sel) => (sel === '[data-line]' ? els : []);
  r.fns.lineMetrics.collect(); // cache the seeded tops (as a render would)
}

test('the scrolled sync is delta-gated: repeated frames at the same line post once', () => {
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, scrollY: 300, expose: ['lineMetrics'] });
  seedLineEntries(r, [{ line: 5, top: 0, height: 1000 }]); // constant scrollY -> constant line
  const count = () => r.state.posted.filter((m) => m.type === 'scrolled').length;
  for (let i = 0; i < 5; i++) r.state.listeners.window['scroll']();
  assert.strictEqual(count(), 1, 'five frames at the same source line -> one message');
});

test('a synchronous scroll burst coalesces to one immediate scrolled post', () => {
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, expose: ['lineMetrics'] });
  seedLineEntries(r, [{ line: 0, top: 0 }, { line: 100, top: 4000 }]);
  const count = () => r.state.posted.filter((m) => m.type === 'scrolled').length;
  for (const y of [100, 200, 300, 400, 500, 600]) {
    r.window.scrollY = y;
    r.state.listeners.window['scroll']();
  }
  assert.strictEqual(count(), 1, 'a same-window burst posts once (the rest are deferred/coalesced)');
});

test('sourceLineAtTop reads at most one rect per frame, not one per line entry (#44 perf)', () => {
  // The scroll-sync freeze: the old scan called getBoundingClientRect on EVERY
  // [data-line] element each frame. The tops are cached (binary search), so a
  // scroll frame reads at most one rect (the resolved entry, for its height).
  const r = runWebviewScript({ docHeight: 8000, viewHeight: 800, expose: ['lineMetrics'] });
  let rectCalls = 0;
  const els = [];
  for (let i = 0; i < 50; i++) els.push({
    dataset: { line: String(i * 10) },
    getBoundingClientRect: () => { rectCalls++; return { top: i * 100 - r.window.scrollY, height: 90 }; }
  });
  r.document.getElementById('content').querySelectorAll = (sel) => (sel === '[data-line]' ? els : []);
  r.fns.lineMetrics.collect(); // caches all 50 tops here, once
  rectCalls = 0;               // count only the scroll-path reads
  r.window.scrollY = 2500;
  r.state.listeners.window['scroll']();
  assert.ok(rectCalls <= 1, `at most one rect read per scroll frame, got ${rectCalls} for 50 entries`);
});

test('the scroll-spy no longer constructs an IntersectionObserver (rAF pump is the trigger)', () => {
  let ioCount = 0;
  const previous = global.IntersectionObserver;
  global.IntersectionObserver = class { constructor() { ioCount++; } observe() {} unobserve() {} disconnect() {} };
  try {
    const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800 });
    withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h1', 'b', 'B', 1000)]);
    r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
    r.send({ type: 'render', html: 'x' });
    r.window.scrollY = 1500; r.state.listeners.window['scroll']();
    assert.strictEqual(ioCount, 0, 'no IntersectionObserver created');
  } finally {
    global.IntersectionObserver = previous;
  }
});

// --- TOC expand/collapse chevrons, sticky manual state (#48). ---

function fireTocClick(r, idx, chevron) {
  // chevron=true simulates a click on the twistie gutter (toggles the branch);
  // chevron=false a click on the label (navigates).
  const link = { dataset: { idx: String(idx), id: 'h' + idx } };
  link.closest = (s) => {
    if (s === '.toc-link') return link;
    if (s === '.toc-gutter') return chevron ? { className: 'toc-gutter' } : null;
    return null;
  };
  r.state.els['toc']._listeners['click']({ target: link, preventDefault() {} });
}
// a,b(child of a),c: tocBranches[0] holds b (a parent), [1]/[2] are null (leaves).
function tocFixture(expose) {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800, expose });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h2', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000)]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  return r;
}

test('a TOC chevron click toggles the branch (manual), a leaf entry has no branch to toggle', () => {
  const r = tocFixture(['tocBranches']);
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active b -> branch 0 expanded (on path)
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false);
  fireTocClick(r, 0, true);  // chevron zone on the parent -> collapse
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true, 'chevron collapsed it');
  fireTocClick(r, 0, true);  // toggle back -> expand
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false, 'chevron expanded it');
  assert.strictEqual(r.fns.tocBranches[2], null, 'a leaf entry has no branch');
});

test('a manually collapsed TOC branch stays collapsed even on the active path (sticky)', () => {
  const r = tocFixture(['tocBranches']);
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active b, branch 0 expanded
  fireTocClick(r, 0, true); // manual collapse
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true);
  r.window.scrollY = 2500; r.state.listeners.window['scroll'](); // active c (branch 0 off path)
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active b again (branch 0 on path)
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true,
    'the automatic does not re-expand a manually collapsed branch');
});

test('a manually expanded TOC branch stays expanded even off the active path (sticky)', () => {
  const r = tocFixture(['tocBranches']);
  r.window.scrollY = 2500; r.state.listeners.window['scroll'](); // active c -> branch 0 collapsed (off path)
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true);
  fireTocClick(r, 0, true); // manual expand while off path
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false);
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active b (branch 0 on path)
  r.window.scrollY = 2500; r.state.listeners.window['scroll'](); // active c again (branch 0 leaves the path)
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false,
    'the automatic does not re-collapse a manually expanded branch');
});

test('a re-render resets the sticky manual TOC state', () => {
  // Re-render at scrollY 0 so the re-collected heading tops are unshifted (the
  // headingEl mock returns viewport-fixed rects). Manually collapse an on-path
  // branch, then a fresh tree drops the manual state and the automatic re-expands.
  const r = tocFixture(['tocBranches']); // rendered at scrollY 0 -> active a -> branch 0 expanded
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false, 'auto-expanded on path');
  fireTocClick(r, 0, true); // manually collapse the on-path branch
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true, 'manually collapsed');
  r.send({ type: 'render', html: 'x' }); // fresh tree resets the manual state (scrollY still 0)
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false,
    'after a re-render the branch follows the automatic again (on path -> expanded)');
});

test('a TOC label click navigates; a chevron click only toggles', () => {
  const r = tocFixture(['tocBranches', 'getTopBarsOffset']);
  r.window.scrollY = 1500; r.state.listeners.window['scroll']();
  r.document.getElementById('content').querySelector = () => ({ getBoundingClientRect: () => ({ top: 500 }) });
  fireTocClick(r, 0, true);   // chevron zone -> toggle, no navigation
  assert.strictEqual(r.state.scrolledTo, null, 'a chevron click does not navigate');
  r.window.scrollY = 0;    // so absTop == the heading's rect top
  fireTocClick(r, 0, false); // label zone -> navigate (below the top bars)
  assert.strictEqual(r.state.scrolledTo, 500 - r.fns.getTopBarsOffset(), 'a label click navigates to the heading');
});

test('the TOC twistie is the native codicon chevron, centered in a gutter, rotated when expanded (#44)', () => {
  // The vendored codicon font renders at its native 16px metrics; chevron-right
  // is the \eab6 glyph; the gutter is a fixed 16px flex box that centers it
  // against the text; collapsed points right (0deg), expanded points down (90deg).
  assert.match(CSS, /@font-face\s*\{[^}]*font-family:\s*"codicon"[^}]*codicon\.ttf[^}]*\}/,
    'the codicon font is declared and loaded from the vendored ttf');
  assert.match(ruleBody('.codicon[class*="codicon-"]'), /16px\/1 codicon/, 'native codicon metrics');
  assert.match(ruleBody('.codicon-chevron-right::before'), /content:\s*"\\eab6"/, 'the chevron-right glyph');
  assert.match(ruleBody('.toc-gutter'), /flex:\s*0 0 16px/, 'the gutter is a fixed 16px slot');
  assert.match(ruleBody('.toc-gutter'), /align-items:\s*center/, 'centers the chevron vertically');
  assert.match(ruleBody('.toc-gutter'), /justify-content:\s*center/, 'centers the chevron horizontally');
  assert.match(ruleBody('.toc-link'), /align-items:\s*center/, 'the row centers the gutter against the label');
  assert.match(ruleBody('.toc-twistie'), /rotate\(0deg\)/, 'collapsed: points right');
  assert.match(
    ruleBody('.toc-item:has(> .toc-sublist-wrap > .toc-sublist:not(.toc-collapsed)) > .toc-link .toc-twistie'),
    /rotate\(90deg\)/, 'expanded: points down');
});

test('the TOC sublist expand/collapse is animated only on a manual toggle (#44 P5)', () => {
  // grid-template-rows 0fr<->1fr animates to the content height with no magic
  // number; the transition is armed only while body.toc-animating is set (a
  // manual toggle), so the scroll-driven auto expand/collapse stays instant.
  assert.match(ruleBody('.toc-sublist-wrap'), /grid-template-rows:\s*1fr/, 'expanded track');
  assert.match(ruleBody('.toc-sublist-wrap:has(> .toc-sublist.toc-collapsed)'),
    /grid-template-rows:\s*0fr/, 'collapsed track');
  assert.match(ruleBody('body.toc-animating .toc-sublist-wrap'),
    /transition:\s*grid-template-rows/, 'the transition is gated to a manual toggle');
  assert.match(CSS, /prefers-reduced-motion:\s*reduce[\s\S]*?body\.toc-animating\s*\.toc-sublist-wrap\s*\{\s*transition:\s*none/,
    'reduced-motion disables the animation');
  // The sublist clips during the collapse so the rows do not spill.
  assert.match(CSS, /\.toc-sublist\s*\{[^}]*overflow:\s*hidden/, 'the sublist clips while collapsing');
});

test('a manual TOC toggle arms the animation flag; the scroll-driven auto path does not (#44 P5)', () => {
  const r = tocFixture(['tocBranches']);
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active b -> auto expand, no animation
  assert.strictEqual(!!r.state.bodyClasses['toc-animating'], false,
    'the scroll-driven auto expand does not animate');
  fireTocClick(r, 0, true); // manual toggle -> arm the transition
  assert.strictEqual(r.state.bodyClasses['toc-animating'], true, 'a manual toggle animates');
});

test('the TOC highlight delta marks the active path and re-collapses on the way out', () => {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800,
    expose: ['tocLinks', 'tocBranches'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 0), headingEl('h2', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000)]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 1500; r.state.listeners.window['scroll'](); // active = b (h2 under a)
  assert.strictEqual(r.fns.tocLinks[1].classList.contains('toc-active'), true, 'b active');
  assert.strictEqual(r.fns.tocLinks[0].classList.contains('toc-in-path'), true, 'a on the path');
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), false, 'a expanded');
  r.window.scrollY = 2500; r.state.listeners.window['scroll'](); // active = c (sibling h1)
  assert.strictEqual(r.fns.tocLinks[2].classList.contains('toc-active'), true, 'c active');
  assert.strictEqual(r.fns.tocLinks[1].classList.contains('toc-active'), false, 'b no longer active');
  assert.strictEqual(r.fns.tocBranches[0].classList.contains('toc-collapsed'), true, 'a re-collapsed');
});

// Drive the top bars into an active chain, then return the harness so the
// breadcrumb/dropdown click handlers can be exercised.
function withActiveChain(headings) {
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800,
    expose: ['getTopBarsOffset'] });
  withHeadings(r, headings);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  r.state.listeners.window['scroll']();
  r.window.scrollY = 0; // chain is established; reset so absTop == the heading's rect top
  return r;
}
function segTarget(idx, href, cls) {
  // The controls carry the target id in data-id (not an href): they are buttons,
  // not native #id anchors, so the smooth navigateToHash is not overridden (#44).
  const el = { dataset: { idx: String(idx), id: href.slice(1) },
    getBoundingClientRect: () => ({ left: 10, bottom: 30 }) };
  el.closest = (s) => (s === cls ? el : null);
  return el;
}

test('a breadcrumb segment scrolls to its heading and opens the sibling picker', () => {
  const r = withActiveChain([headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.document.getElementById('content').querySelector =
    (s) => (s === '#a' ? { getBoundingClientRect: () => ({ top: 100 }) } : null);
  r.state.els['breadcrumb']._listeners['click'](
    { target: segTarget(0, '#a', '.breadcrumb-seg'), preventDefault() {} });
  assert.strictEqual(r.state.scrolledTo, 100 - r.fns.getTopBarsOffset(),
    'scrolled to the segment heading, below the bars');
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true, 'picker opened');
});

test('one central mousedown handler suppresses the click focus on every control (#44)', () => {
  // A mouse click that focuses a control makes a VS Code webview scroll it into
  // view - a first-click page jump, and for a TOC twistie a spurious active-heading
  // drift (the toggle appeared to select the entry above). One delegated mousedown
  // preventDefault over every click target fixes both; keyboard focus is untouched.
  const { state, fns } = runWebviewScript({ expose: ['CLICK_FOCUS_TARGETS'] });
  const sel = fns.CLICK_FOCUS_TARGETS;
  // Content links and checkboxes (a, input) as well as the nav controls: any
  // focusable target, so no click focuses (and scrolls) anything.
  for (const target of ['a', 'input', 'button',
    '.breadcrumb-seg', '.breadcrumb-option', '.toc-link', '.sticky-row']) {
    assert.ok(sel.split(/\s*,\s*/).includes(target), 'the delegated selector covers ' + target);
  }
  const md = state.listeners.document['mousedown'];
  assert.ok(md, 'a document mousedown listener is registered');
  let prevented = false;
  md({ target: { closest: (s) => (s === sel ? {} : null) }, preventDefault: () => { prevented = true; } });
  assert.strictEqual(prevented, true, 'a mousedown on a control is prevented (no focus, no scroll-into-view)');
  let plain = false;
  md({ target: { closest: () => null }, preventDefault: () => { plain = true; } });
  assert.strictEqual(plain, false, 'a mousedown on plain content is untouched (text selection stays normal)');
});

test('pointer focus shows no outline anywhere; keyboard focus-visible keeps the ring (#44)', () => {
  // VS Code injects an --vscode-focusBorder outline on every focusable element; on
  // a click (content link, tabindex=-1 checkbox/cell, nav control) that is just
  // visual noise. One global rule drops it for pointer/programmatic focus and
  // keeps it for :focus-visible (keyboard), so a11y is unaffected.
  assert.match(ruleBody(':focus:not(:focus-visible)'), /outline:\s*none/);
});

test('Escape closes the open sibling picker before clearing the selection', () => {
  const r = withActiveChain([headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.document.getElementById('content').querySelector = () => ({ getBoundingClientRect: () => ({ top: 0 }) });
  r.state.els['breadcrumb']._listeners['click'](
    { target: segTarget(1, '#b', '.breadcrumb-seg'), preventDefault() {} });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true);
  r.state.listeners.document['keydown']({ key: 'Escape' });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], false, 'Escape closed the picker');
});

test('a click outside the breadcrumb and its picker closes the picker', () => {
  const r = withActiveChain([headingEl('h1', 'a', 'A', 100)]);
  r.document.getElementById('content').querySelector = () => ({ getBoundingClientRect: () => ({ top: 0 }) });
  r.state.els['breadcrumb']._listeners['click'](
    { target: segTarget(0, '#a', '.breadcrumb-seg'), preventDefault() {} });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true);
  // An outside click: the target belongs to neither the dropdown nor a segment.
  r.state.listeners.document['click']({ target: { closest: () => null } });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], false);
});

test('choosing a sibling from the picker navigates and closes it', () => {
  const r = withActiveChain([headingEl('h1', 'a', 'A', 100), headingEl('h1', 'c', 'C', 300)]);
  r.document.getElementById('content').querySelector =
    (s) => (s === '#c' ? { getBoundingClientRect: () => ({ top: 300 }) } : null);
  r.state.els['breadcrumb']._listeners['click'](
    { target: segTarget(0, '#a', '.breadcrumb-seg'), preventDefault() {} });
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], true);
  r.state.els['breadcrumb-dropdown']._listeners['click'](
    { target: segTarget(1, '#c', '.breadcrumb-option'), preventDefault() {} });
  assert.strictEqual(r.state.scrolledTo, 300 - r.fns.getTopBarsOffset(), 'navigated to the chosen sibling');
  assert.strictEqual(r.state.bodyClasses['breadcrumb-dropdown-open'], false, 'picker closed');
});

test('a sticky-scroll row scrolls to its heading', () => {
  const r = withActiveChain([headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.document.getElementById('content').querySelector =
    (s) => (s === '#a' ? { getBoundingClientRect: () => ({ top: 100 }) } : null);
  r.state.els['sticky-scroll']._listeners['click'](
    { target: segTarget(0, '#a', '.sticky-row'), preventDefault() {} });
  assert.strictEqual(r.state.scrolledTo, 100 - r.fns.getTopBarsOffset());
});

test('the nav controls render as buttons (role=button + data-id, no href) so smooth scroll is not overridden (#44)', () => {
  // The VS Code webview runs a native, instant #id jump on any real anchor click
  // (preventDefault does not stop it), which would win the final scroll position
  // and defeat the smooth navigateToHash. Rendering the controls as buttons with
  // the target in data-id (not an href) removes that native jump, so the smooth
  // scroll is the only motion. (In-file markdown [..](#id) links stay real anchors
  // and remain instant by design.)
  const r = runWebviewScript({ viewWidth: 1600, docHeight: 8000, viewHeight: 800,
    expose: ['tocLinks'] });
  withHeadings(r, [headingEl('h1', 'a', 'A', 100), headingEl('h2', 'b', 'B', 200)]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700; r.state.listeners.window['scroll'](); // active chain [a, b] -> bars built
  const check = (el, where) => {
    assert.strictEqual(el._attrs && el._attrs.role, 'button', where + ' is a button, not a link');
    assert.ok(el.dataset.id, where + ' carries its target id in data-id');
    assert.strictEqual(el.href, undefined, where + ' has no href (no native #id jump to override the smooth scroll)');
  };
  check(r.state.els['breadcrumb']._links[0], 'a breadcrumb segment');
  check(r.state.els['sticky-scroll']._links[0], 'a sticky row');
  check(r.fns.tocLinks[0], 'a TOC entry');
});

test('every hrefless nav control declares cursor:pointer (buttons no longer inherit the anchor hand) (#44)', () => {
  // Dropping the href turned the controls into generic elements, which show the
  // text I-beam by default - each must declare the pointer cursor explicitly.
  for (const sel of ['.toc-link', '.breadcrumb-seg', '.sticky-row', '.breadcrumb-option']) {
    assert.match(ruleBody(sel), /cursor:\s*pointer/, sel + ' shows the hand cursor');
  }
});

test('every breadcrumb segment is the same fixed-height box (#44 review 8)', () => {
  // The bar is a fixed height and each segment fills it as a flex box, so a
  // highlighted or long-label segment cannot render a different box height than a
  // plain one. (The rendered pixel height is a manual VS Code check; the fixed
  // geometry is the headless contract.)
  assert.match(ruleBody('#breadcrumb'), /height:\s*28px/, 'the bar is a fixed height');
  assert.doesNotMatch(ruleBody('#breadcrumb'), /min-height/, 'not a content-dependent min-height');
  assert.match(ruleBody('.breadcrumb-seg'), /display:\s*inline-flex/, 'segment is a flex box');
  assert.match(ruleBody('.breadcrumb-seg'), /align-items:\s*center/);
  assert.match(ruleBody('.breadcrumb-seg'), /height:\s*100%/, 'every segment fills the bar height');
});

test('the breadcrumb highlight is a label pill, so the separator sits outside it (#44 review 8)', () => {
  // The hover background is on the inner .breadcrumb-label (the text), never on
  // the segment box; the separator is a ::before on the segment, outside that
  // label - so no highlight is ever drawn under it.
  assert.match(ruleBody('.breadcrumb-seg:hover .breadcrumb-label'),
    /background:\s*var\(--vscode-list-hoverBackground\)/, 'highlight is on the label pill');
  assert.doesNotMatch(ruleBody('.breadcrumb-seg:hover'), /background/,
    'the segment box itself carries no highlight background');
  assert.doesNotMatch(ruleBody('.breadcrumb-seg'), /background/,
    'nor does the base segment, so the separator never sits on a highlight');
  assert.match(CSS, /\.breadcrumb-seg:not\(:first-child\)::before\s*\{[^}]*content:\s*"\\eab6"/,
    'the separator is the native codicon chevron ::before, outside the label');
  assert.match(CSS, /\.breadcrumb-seg:not\(:first-child\)::before\s*\{[^}]*codicon/,
    'the separator uses the codicon font, not a thin angle-quote');
});

// --- Top-bars stylesheet contract (#33): reserved padding, bar visibility, the
// content-region insets that keep the bars off the minimap/TOC rail. ---

test('the breadcrumb reserves body top padding from its measured height', () => {
  assert.match(ruleBody('body.has-breadcrumb'), /padding-top:\s*calc\(var\(--breadcrumb-height/);
});

test('the sticky stack sits directly below the breadcrumb', () => {
  assert.match(ruleBody('#sticky-scroll'), /top:\s*var\(--breadcrumb-height/);
});

test('both bars and the picker are hidden until their body classes are set', () => {
  assert.match(ruleBody('#breadcrumb'), /display:\s*none/);
  assert.match(ruleBody('#sticky-scroll'), /display:\s*none/);
  assert.match(ruleBody('#breadcrumb-dropdown'), /display:\s*none/);
  assert.match(ruleBody('body.has-breadcrumb #breadcrumb'), /display:\s*flex/);
  assert.match(ruleBody('body.has-sticky #sticky-scroll'), /display:\s*flex/);
  assert.match(ruleBody('body.breadcrumb-dropdown-open #breadcrumb-dropdown'), /display:\s*flex/);
});

test('the bars fill the content region via insets that clear the minimap and TOC rail', () => {
  assert.match(ruleBody('#breadcrumb'), /left:\s*var\(--bar-inset-left\)/);
  assert.match(ruleBody('#breadcrumb'), /right:\s*var\(--bar-inset-right\)/);
  assert.match(ruleBody('body.has-minimap:not(.minimap-left)'), /--bar-inset-right:\s*104px/);
  // The TOC-rail inset shares its selector with the existing rail-padding rule,
  // so assert the declaration exists in the sheet rather than via ruleBody.
  assert.match(CSS, /--bar-inset-left:\s*240px/);
  assert.match(CSS, /--bar-inset-right:\s*240px/);
});

test('the webview skeleton carries the breadcrumb, sticky-scroll and dropdown containers', () => {
  install();
  const views = loadFresh('src/views.js');
  views.setExtensionUri('EXT');
  const html = views.getWebviewHtml({
    cspSource: 'vscode-webview://host', asWebviewUri: (u) => 'https://webview/' + String(u)
  });
  assert.match(html, /id="breadcrumb"/);
  assert.match(html, /id="sticky-scroll"/);
  assert.match(html, /id="breadcrumb-dropdown"/);
  // tabindex -1 keeps the new controls out of the tab order (PR #45 decision).
  assert.match(html, /id="breadcrumb"[^>]*tabindex="-1"/);
});
