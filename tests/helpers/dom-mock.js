// Minimal DOM mock to execute the webview <script> headlessly. Exposes the
// registered window/document event listeners and tracks body classes,
// element styles and posted messages.

function createDom(opts = {}) {
  const state = {
    bodyClasses: {},
    posted: [],
    scrolledTo: null,
    listeners: { window: {}, document: {} },
    els: {}
  };
  const railWidth = opts.railWidth === undefined ? 88 : opts.railWidth;
  const contentWidth = opts.contentWidth === undefined ? 700 : opts.contentWidth;

  const mkEl = (id) => {
    const el = {
      id, innerHTML: '', style: {}, dataset: {},
      _classes: {},
      classList: {
        add(c) { el._classes[c] = true; },
        remove(c) { el._classes[c] = false; },
        toggle(c, v) { el._classes[c] = v === undefined ? !el._classes[c] : v; },
        contains(c) { return !!el._classes[c]; }
      },
      get clientWidth() {
        if (id === 'minimap') return state.bodyClasses['has-minimap'] ? railWidth : 0;
        return contentWidth;
      },
      clientHeight: opts.railHeight === undefined ? 800 : opts.railHeight,
      addEventListener(type, fn) { (el._listeners = el._listeners || {})[type] = fn; },
      querySelector: () => null,
      querySelectorAll: () => [],
      appendChild: () => {},
      cloneNode: () => ({ querySelectorAll: () => [] }),
      getBoundingClientRect: () => ({ top: 0 }),
      setPointerCapture: () => {},
      releasePointerCapture: () => {},
      setAttribute: () => {},
      removeAttribute: () => {},
      remove: () => {},
      closest: () => null,
      scrollIntoView: () => {}
    };
    return el;
  };

  const document = {
    getElementById: (id) => state.els[id] || (state.els[id] = mkEl(id)),
    addEventListener: (t, f) => { state.listeners.document[t] = f; },
    documentElement: {
      scrollHeight: opts.docHeight === undefined ? 8000 : opts.docHeight,
      style: { setProperty: (k, v) => { state.cssVars = state.cssVars || {}; state.cssVars[k] = v; } }
    },
    body: {
      classList: {
        toggle: (c, v) => { state.bodyClasses[c] = v === undefined ? !state.bodyClasses[c] : v; },
        add: (c) => { state.bodyClasses[c] = true; },
        remove: (c) => { state.bodyClasses[c] = false; },
        contains: (c) => !!state.bodyClasses[c]
      }
    },
    querySelectorAll: () => [],
    createElement: () => mkEl('dynamic')
  };

  const window = {
    scrollY: opts.scrollY === undefined ? 0 : opts.scrollY,
    scrollX: 0,
    innerHeight: opts.viewHeight === undefined ? 800 : opts.viewHeight,
    innerWidth: opts.viewWidth === undefined ? 1600 : opts.viewWidth,
    // Accepts both scrollTo(x, y) and scrollTo({ top, behavior }) (the smooth
    // TOC navigation uses the object form).
    scrollTo: (x, y) => {
      const top = (x && typeof x === 'object') ? x.top : y;
      state.scrolledTo = top; window.scrollY = top;
    },
    addEventListener: (t, f) => { state.listeners.window[t] = f; },
    // Selection text the click handler reads to gate bare-click toggles;
    // tests set window.__selection to simulate an active text selection.
    __selection: '',
    getSelection: () => ({ toString: () => window.__selection })
  };

  return { document, window, state };
}

// Run the webview script (media/webview.js, loaded directly) against a DOM
// mock. getWebviewHtml only embeds it via <script src>, so the test loads the
// real asset instead of extracting it from the HTML.
// Returns { state, send } where send(data) delivers a host->webview message.
const fs = require('fs');
const path = require('path');
const WEBVIEW_SCRIPT = path.resolve(__dirname, '..', '..', 'media', 'webview.js');

function runWebviewScript(opts = {}) {
  const script = fs.readFileSync(WEBVIEW_SCRIPT, 'utf8');
  const dom = createDom(opts);
  global.requestAnimationFrame = (f) => f();
  // Observer shims: the webview guards on typeof, so these only need to exist
  // and record the callback/observed nodes; no layout callbacks are simulated.
  global.IntersectionObserver = global.IntersectionObserver || class {
    constructor(cb) { this.cb = cb; this.observed = []; }
    observe(el) { this.observed.push(el); }
    unobserve() {}
    disconnect() { this.observed = []; }
  };
  global.ResizeObserver = global.ResizeObserver || class {
    constructor(cb) { this.cb = cb; }
    observe() {} unobserve() {} disconnect() {}
  };
  // Browser global the anchor lookup uses; the shim leaves identifier chars
  // (letters incl. non-ASCII, digits, '-', '_') as-is and backslash-escapes the
  // rest - enough for the selectors the tests build.
  global.CSS = global.CSS || { escape: (s) => String(s).replace(/[^a-zA-Z0-9_\u00A0-\uFFFF-]/g, (ch) => '\\' + ch) };
  const vscodeApi = {
    postMessage: (m) => dom.state.posted.push(m),
    // Webview state persistence (used by the preview-panel restore path): record
    // the last setState so tests can assert the persisted document URI.
    setState: (s) => { dom.state.savedState = s; },
    getState: () => dom.state.savedState
  };
  const exposed = opts.expose || [];
  const tail = exposed.length ? '\nreturn { ' + exposed.join(', ') + ' };' : '';
  const result = new Function(
    'vscodeApi', 'window', 'document',
    script.replace('const vscode = acquireVsCodeApi();', 'const vscode = vscodeApi;') + tail
  )(vscodeApi, dom.window, dom.document);
  const send = (data) => dom.state.listeners.window['message']({ data });
  return { state: dom.state, send, fns: result || {}, window: dom.window, document: dom.document };
}

module.exports = { createDom, runWebviewScript };
