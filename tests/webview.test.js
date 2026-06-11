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
