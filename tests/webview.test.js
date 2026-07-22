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
  // Table top (300) still below the scroll position (100): no pin.
  assert.strictEqual(fns.stickyHeadOffset(100, 300, 400, 40), 0);
  // Window scrolled 200px past the table top: header follows exactly.
  assert.strictEqual(fns.stickyHeadOffset(500, 300, 400, 40), 200);
  // Clamped at the table end: never beyond tableHeight - headHeight = 360.
  assert.strictEqual(fns.stickyHeadOffset(900, 300, 400, 40), 360);
});

test('updateStickyHeads pins only scrolls wrappers and clears the rest', () => {
  const { fns, document, window } = runWebviewScript({ expose: ['updateStickyHeads'] });
  const mkWrap = (scrolls, viewportTop) => {
    const head = { style: { transform: 'translateY(99px)' }, getBoundingClientRect: () => ({ height: 40 }) };
    const table = { getBoundingClientRect: () => ({ top: viewportTop, height: 400 }) };
    return {
      head,
      classList: { contains: (c) => c === 'scrolls' && scrolls },
      querySelector: (sel) => sel === 'thead' ? head : table
    };
  };
  window.scrollY = 1000;
  const pinned = mkWrap(true, -200); // table top 200px above the viewport top
  const plain = mkWrap(false, -200); // native sticky: leftover transform cleared
  const below = mkWrap(true, 100);   // table top still below the viewport top
  const content = document.getElementById('content');
  content.querySelectorAll = (sel) => sel === ':scope > .table-wrap' ? [pinned, plain, below] : [];
  fns.updateStickyHeads();
  assert.strictEqual(pinned.head.style.transform, 'translateY(200px)');
  assert.strictEqual(plain.head.style.transform, '');
  assert.strictEqual(below.head.style.transform, '');
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
  const a = { getAttribute: (n) => (n === 'href' ? href : null) };
  a.closest = (s) => {
    if (s === 'a[href^="#"]') return href.startsWith('#') ? a : null;
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
