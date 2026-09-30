// A minimal DOM mock to run the webview modules headlessly, and the test entry
// that starts a fresh webview on it. The mock exposes the registered window/document
// event listeners and tracks body classes, element styles and posted messages.
//
// The webview modules read `window`, `document` and a few browser globals as globals,
// so startWebview installs the mock on globalThis and imports src/webview/main.ts in a
// fresh module generation (`?gen=N`, tests/helpers/vscode-hooks.ts): every test gets
// its own module state, and `load()` reaches the very instances main.ts started.

import { nextGeneration } from './vscode-hooks.ts';
import type {
  HostToWebview,
  WebviewState,
  WebviewToHost,
} from '../../src/webview/protocol.ts';

/** An event as the mock hands it to a listener: whatever the test puts in. */
export type MockEvent = Record<string, unknown>;
/** A listener the webview registered on the mock. */
export type MockListener = (event: MockEvent) => void;

/** A class list over a plain record. */
export interface MockClassList {
  add(c: string): void;
  remove(c: string): void;
  toggle(c: string, force?: boolean): void;
  contains(c: string): boolean;
}

/**
 * A mock element. Tests replace members (querySelectorAll, cloneNode, children,
 * getBoundingClientRect ...) to shape what the webview sees; the index signature
 * admits the extra fields the webview writes (`_links`, `_label`, `tabIndex` ...).
 */
export interface MockEl {
  [key: string]: unknown;
  id: string;
  innerHTML: string;
  style: Record<string, unknown>;
  dataset: Record<string, string | undefined>;
  _classes: Record<string, boolean>;
  _attrs?: Record<string, unknown>;
  _listeners?: Record<string, MockListener>;
  _links?: MockEl[];
  classList: MockClassList;
  readonly clientWidth: number;
  clientHeight: number;
  children?: readonly unknown[];
  addEventListener(type: string, fn: MockListener): void;
  querySelector: (selector: string) => unknown;
  querySelectorAll: (selector: string) => readonly unknown[];
  appendChild(child: unknown): void;
  cloneNode: (deep?: boolean) => unknown;
  getBoundingClientRect: () => Record<string, number>;
  setPointerCapture(id: unknown): void;
  releasePointerCapture(id: unknown): void;
  setAttribute(name: string, value: unknown): void;
  removeAttribute(name: string): void;
  remove(): void;
  closest: (selector: string) => unknown;
  scrollIntoView: (options?: unknown) => void;
}

/** What a test reads back from a started webview. */
export interface DomState {
  bodyClasses: Record<string, boolean>;
  posted: WebviewToHost[];
  scrolledTo: number | null;
  scrolledSmooth?: boolean;
  listeners: {
    window: Record<string, MockListener>;
    document: Record<string, MockListener>;
  };
  els: Record<string, MockEl>;
  cssVars?: Record<string, string>;
  savedState?: WebviewState;
  /** How often the webview called setState. */
  stateWrites: number;
  /** The callback the webview handed to `new ResizeObserver`. */
  resizeObserver?: () => void;
  /** Every element the webview created, in order. */
  created: MockEl[];
}

/** The mock document. */
export interface MockDocument {
  getElementById(id: string): MockEl;
  addEventListener(type: string, fn: MockListener): void;
  documentElement: {
    scrollHeight: number;
    style: { setProperty: (name: string, value: string) => void };
  };
  body: { classList: MockClassList };
  querySelectorAll(selector: string): readonly unknown[];
  createElement(tag: string): MockEl;
}

/** The mock window. */
export interface MockWindow {
  scrollY: number;
  scrollX: number;
  innerHeight: number;
  innerWidth: number;
  scrollTo(x: number | { top: number; behavior?: string }, y?: number): void;
  addEventListener(type: string, fn: MockListener): void;
  /** Selection text the click handler reads; set it to simulate a text selection. */
  __selection: string;
  getSelection(): { toString(): string };
}

/** Geometry and viewport of a mock DOM (all optional, with the historic defaults). */
export interface DomOptions {
  railWidth?: number;
  contentWidth?: number;
  railHeight?: number;
  docHeight?: number;
  viewHeight?: number;
  viewWidth?: number;
  scrollY?: number;
  /** 'manual' queues requestAnimationFrame callbacks until flushFrames(); default runs them at once. */
  raf?: 'sync' | 'manual';
  /** The state getState returns at start: a stand persisted before a restart. */
  savedState?: WebviewState;
  /** Shapes the mock before the webview loads (what a restore at load reads). */
  prepare?: (dom: ReturnType<typeof createDom>) => void;
}

/** Build the mock document, window and state (no globals touched). */
export function createDom(opts: DomOptions = {}): {
  document: MockDocument;
  window: MockWindow;
  state: DomState;
} {
  const state: DomState = {
    bodyClasses: {},
    posted: [],
    scrolledTo: null,
    listeners: { window: {}, document: {} },
    els: {},
    created: [],
    stateWrites: 0,
    ...(opts.savedState === undefined ? {} : { savedState: opts.savedState }),
  };
  const railWidth = opts.railWidth === undefined ? 88 : opts.railWidth;
  const contentWidth =
    opts.contentWidth === undefined ? 700 : opts.contentWidth;

  const mkEl = (id: string): MockEl => {
    const classes: Record<string, boolean> = {};
    const el: MockEl = {
      id,
      innerHTML: '',
      style: {},
      dataset: {},
      _classes: classes,
      classList: {
        add(c) {
          classes[c] = true;
        },
        remove(c) {
          classes[c] = false;
        },
        toggle(c, v) {
          classes[c] = v === undefined ? !classes[c] : v;
        },
        contains(c) {
          return !!classes[c];
        },
      },
      get clientWidth() {
        if (id === 'minimap')
          return state.bodyClasses['has-minimap'] ? railWidth : 0;
        return contentWidth;
      },
      clientHeight: opts.railHeight === undefined ? 800 : opts.railHeight,
      addEventListener(type, fn) {
        el._listeners ??= {};
        el._listeners[type] = fn;
      },
      querySelector: () => null,
      querySelectorAll: () => [],
      appendChild: () => {},
      cloneNode: () => ({ querySelectorAll: () => [] }),
      getBoundingClientRect: () => ({ top: 0 }),
      setPointerCapture: () => {},
      releasePointerCapture: () => {},
      setAttribute: (k, v) => {
        el._attrs ??= {};
        el._attrs[k] = v;
      },
      removeAttribute: (k) => {
        if (el._attrs) delete el._attrs[k];
      },
      remove: () => {},
      closest: () => null,
      scrollIntoView: () => {},
    };
    return el;
  };

  const document: MockDocument = {
    getElementById: (id) => {
      let el = state.els[id];
      if (!el) {
        el = mkEl(id);
        state.els[id] = el;
      }
      return el;
    },
    addEventListener: (t, f) => {
      state.listeners.document[t] = f;
    },
    documentElement: {
      scrollHeight: opts.docHeight === undefined ? 8000 : opts.docHeight,
      style: {
        setProperty: (k, v) => {
          state.cssVars = state.cssVars || {};
          state.cssVars[k] = v;
        },
      },
    },
    body: {
      classList: {
        toggle: (c, v) => {
          state.bodyClasses[c] = v === undefined ? !state.bodyClasses[c] : v;
        },
        add: (c) => {
          state.bodyClasses[c] = true;
        },
        remove: (c) => {
          state.bodyClasses[c] = false;
        },
        contains: (c) => !!state.bodyClasses[c],
      },
    },
    querySelectorAll: () => [],
    createElement: (tag) => {
      const el = mkEl('dynamic');
      el.tagName = tag.toUpperCase();
      state.created.push(el);
      return el;
    },
  };

  const window: MockWindow = {
    scrollY: opts.scrollY === undefined ? 0 : opts.scrollY,
    scrollX: 0,
    innerHeight: opts.viewHeight === undefined ? 800 : opts.viewHeight,
    innerWidth: opts.viewWidth === undefined ? 1600 : opts.viewWidth,
    // Accepts both scrollTo(x, y) and scrollTo({ top, behavior }) (the object
    // form is the smooth variant). scrolledSmooth records which was used.
    scrollTo: (x, y) => {
      const top = typeof x === 'object' ? x.top : (y ?? 0);
      state.scrolledSmooth = typeof x === 'object' && x.behavior === 'smooth';
      state.scrolledTo = top;
      window.scrollY = top;
    },
    addEventListener: (t, f) => {
      state.listeners.window[t] = f;
    },
    __selection: '',
    getSelection: () => ({ toString: () => window.__selection }),
  };

  return { document, window, state };
}

/** Every webview module a test loads, by its path under src/webview/. */
export interface WebviewModules {
  'anchors/anchors.ts': typeof import('../../src/webview/anchors/anchors.ts');
  'folding/fold.ts': typeof import('../../src/webview/folding/fold.ts');
  'folding/refresh.ts': typeof import('../../src/webview/folding/refresh.ts');
  'folding/sections.ts': typeof import('../../src/webview/folding/sections.ts');
  'minimap/drag.ts': typeof import('../../src/webview/minimap/drag.ts');
  'minimap/minimap.ts': typeof import('../../src/webview/minimap/minimap.ts');
  'page/focus.ts': typeof import('../../src/webview/page/focus.ts');
  'restore/state.ts': typeof import('../../src/webview/restore/state.ts');
  'scroll-spy/chain.ts': typeof import('../../src/webview/scroll-spy/chain.ts');
  'scroll-spy/spy.ts': typeof import('../../src/webview/scroll-spy/spy.ts');
  'scroll-sync/line-metrics.ts': typeof import('../../src/webview/scroll-sync/line-metrics.ts');
  'scroll-sync/report.ts': typeof import('../../src/webview/scroll-sync/report.ts');
  'tables/sticky-head.ts': typeof import('../../src/webview/tables/sticky-head.ts');
  'tasks/selection.ts': typeof import('../../src/webview/tasks/selection.ts');
  'toc/layout.ts': typeof import('../../src/webview/toc/layout.ts');
  'toc/tree.ts': typeof import('../../src/webview/toc/tree.ts');
  'top-bars/dropdown.ts': typeof import('../../src/webview/top-bars/dropdown.ts');
  'top-bars/geometry.ts': typeof import('../../src/webview/top-bars/geometry.ts');
  'top-bars/links.ts': typeof import('../../src/webview/top-bars/links.ts');
}

/** A started webview: its mock DOM, the message channel and its modules. */
export interface Webview {
  state: DomState;
  window: MockWindow;
  document: MockDocument;
  /** Deliver a host -> webview message to the registered message listener. */
  send(data: HostToWebview): void;
  /** The module at `rel` (under src/webview/) of this webview's module generation. */
  load<K extends keyof WebviewModules>(rel: K): Promise<WebviewModules[K]>;
  /** Run the queued animation frames (only with `raf: 'manual'`); returns how many ran. */
  flushFrames(): number;
}

const WEBVIEW_URL = new URL('../../src/webview/', import.meta.url).href;
const realSetTimeout = globalThis.setTimeout;
const realClearTimeout = globalThis.clearTimeout;
// Timers started since the last startWebview. A webview's modules are globals-bound, so a
// timer of an earlier instance (trailing scroll post, TOC animation, idle fallback) would
// otherwise fire against the next test's mock; startWebview cancels them first.
const pendingTimers = new Set<ReturnType<typeof setTimeout>>();
let timersWrapped = false;

function trackTimers(): void {
  if (timersWrapped) return;
  timersWrapped = true;
  Object.assign(globalThis, {
    setTimeout: (
      fn: (...a: unknown[]) => void,
      ms?: number,
      ...args: unknown[]
    ) => {
      const handle = realSetTimeout(() => {
        pendingTimers.delete(handle);
        fn(...args);
      }, ms);
      pendingTimers.add(handle);
      return handle;
    },
    clearTimeout: (handle: ReturnType<typeof setTimeout> | undefined) => {
      if (handle !== undefined) pendingTimers.delete(handle);
      realClearTimeout(handle);
    },
  });
}

function cancelPendingTimers(): void {
  for (const handle of pendingTimers) realClearTimeout(handle);
  pendingTimers.clear();
}

// The stand-in for morphdom the hook routes to (the npm package needs a real DOM): it
// reflects the incoming markup onto the target - enough to drive the render path. A test
// may replace globalThis.morphdom to spy on the call.
function morphdomStandIn(
  fromEl: { innerHTML?: unknown },
  toEl: { innerHTML?: unknown } | undefined,
): unknown {
  if (toEl && typeof toEl.innerHTML === 'string')
    fromEl.innerHTML = toEl.innerHTML;
  return fromEl;
}

/**
 * Start a fresh webview on a new mock DOM: install the mock and the browser globals the
 * modules read, then import main.ts in a new module generation (main runs its setup on
 * import, like the bundle does on load).
 */
export async function startWebview(opts: DomOptions = {}): Promise<Webview> {
  trackTimers();
  cancelPendingTimers();
  const dom = createDom(opts);
  const frames: FrameRequestCallback[] = [];
  const requestAnimationFrame =
    opts.raf === 'manual'
      ? (f: FrameRequestCallback) => frames.push(f)
      : (f: FrameRequestCallback) => f(0);
  Object.assign(globalThis, {
    window: dom.window,
    document: dom.document,
    requestAnimationFrame,
    // Records the callback on this run's state so a test can fire the observer
    // (the webview keeps no reference to it).
    ResizeObserver: class {
      constructor(cb: () => void) {
        dom.state.resizeObserver = cb;
      }
      observe() {}
      unobserve() {}
      disconnect() {}
    },
    // Browser global the anchor lookup uses; the shim leaves identifier chars
    // (letters incl. non-ASCII, digits, '-', '_') as-is and backslash-escapes the
    // rest - enough for the selectors the tests build.
    CSS: {
      escape: (s: unknown) =>
        String(s).replace(/[^a-zA-Z0-9_ -￿-]/g, (ch) => `\\${ch}`),
    },
    acquireVsCodeApi: () => ({
      postMessage: (m: WebviewToHost) => dom.state.posted.push(m),
      // Webview state persistence (the preview-panel restore path): record the
      // last setState and count the calls.
      setState: (s: WebviewState) => {
        dom.state.savedState = s;
        dom.state.stateWrites++;
      },
      getState: () => dom.state.savedState,
    }),
  });
  if (typeof Reflect.get(globalThis, 'morphdom') !== 'function')
    Object.assign(globalThis, { morphdom: morphdomStandIn });
  opts.prepare?.(dom);
  const gen = nextGeneration();
  const url = (rel: string) => `${WEBVIEW_URL}${rel}?gen=${gen}`;
  await import(url('main.ts'));
  return {
    state: dom.state,
    window: dom.window,
    document: dom.document,
    send: (data) => {
      const listener = dom.state.listeners.window.message;
      if (!listener)
        throw new Error('the webview registered no message listener');
      listener({ data });
    },
    load: (rel) => import(url(rel)),
    flushFrames: () => {
      const queued = frames.splice(0);
      for (const f of queued) f(0);
      return queued.length;
    },
  };
}
