// Shared fixtures of the webview tests: config messages, click targets, heading and
// line-map mocks, and the prepared documents several test files drive. The targets
// answer exactly the selectors the webview's handlers probe via closest().

import type {
  ConfigMessage,
  MinimapConfig,
  TocConfig,
} from '../../src/webview/protocol.ts';
import type {
  MockEl,
  MockEvent,
  MockListener,
  Webview,
} from './webview-dom.ts';
import { startWebview } from './webview-dom.ts';

/** Minimap config with the test defaults (slider always shown), overridable. */
export const MM = (over?: MinimapConfig): MinimapConfig =>
  Object.assign(
    {
      enabled: true,
      size: 'proportional',
      showSlider: 'always',
      side: 'right',
    } satisfies MinimapConfig,
    over,
  );

/** TOC config with the defaults, overridable. */
export const tocCfg = (over?: TocConfig): TocConfig =>
  Object.assign({ enabled: true, mode: 'auto' } satisfies TocConfig, over);

/** A config message that turns both top bars on (with the minimap/TOC defaults). */
export function topConfig(over?: Partial<ConfigMessage>): ConfigMessage {
  return Object.assign(
    {
      type: 'config',
      maxWidth: '980px',
      minimap: MM(),
      toc: tocCfg(),
      breadcrumb: { enabled: true },
      stickyScroll: { enabled: true },
    } satisfies ConfigMessage,
    over,
  );
}

/** Send a config message with the minimap defaults plus `over`. */
export const sendCfg = (r: Webview, over: Partial<ConfigMessage>): void =>
  r.send(
    Object.assign(
      {
        type: 'config',
        maxWidth: '980px',
        minimap: MM(),
      } satisfies ConfigMessage,
      over,
    ),
  );

/** The listener of `type` an element registered; a missing one fails the test by name. */
export function listenerOf(el: MockEl, type: string): MockListener {
  const fn = el._listeners?.[type];
  if (!fn) throw new Error(`#${el.id} has no ${type} listener`);
  return fn;
}

/** The window/document listener of `type`; a missing one fails the test by name. */
export function globalListener(
  r: Webview,
  on: 'window' | 'document',
  type: string,
): MockListener {
  const fn = r.state.listeners[on][type];
  if (!fn) throw new Error(`no ${on} ${type} listener`);
  return fn;
}

/** Fire the window scroll listener (its rAF runs at once in the default mock). */
export function scroll(r: Webview): void {
  globalListener(r, 'window', 'scroll')({});
}

/** Press a key on the document. */
export function keydown(r: Webview, key: string): void {
  globalListener(r, 'document', 'keydown')({ key });
}

/** The skeleton element with this id. */
export const byId = (r: Webview, id: string): MockEl =>
  r.document.getElementById(id);

/** A numeric CSS value as parseFloat reads it (NaN for a missing one). */
export const px = (value: unknown): number => Number.parseFloat(String(value));

/**
 * Fire the content's delegated click handler with `target` and a plain event
 * (single click, no modifier) overridden by `over`.
 */
export function fireClick(
  r: Webview,
  target: unknown,
  over: MockEvent = {},
): void {
  const e = Object.assign(
    {
      target,
      detail: 1,
      shiftKey: false,
      ctrlKey: false,
      metaKey: false,
      preventDefault() {},
    },
    over,
  );
  listenerOf(byId(r, 'content'), 'click')(e);
}

/** A target that answers `closest(selector)` from a map (anything else: null). */
export interface Target {
  dataset: Record<string, string>;
  closest(selector: string): unknown;
  [key: string]: unknown;
}

/** A list task's checkbox input. */
export function listCheckboxTarget(line: number, checked: boolean): Target {
  const li: Target = {
    dataset: { line: String(line), checked: checked ? 'true' : 'false' },
    closest: (s) => (s === 'li.task' ? li : null),
  };
  const input: Target = {
    dataset: {},
    hasAttribute: () => checked,
    closest: (s) => {
      if (s === '.task-row input[type=checkbox]') return input;
      if (s === 'li.task') return li;
      return null;
    },
  };
  return input;
}

/** The label area of a list task row (not its checkbox). */
export function labelTarget(line: number, checked: boolean): Target {
  const li: Target = {
    dataset: { line: String(line), checked: checked ? 'true' : 'false' },
    closest: (s) => (s === 'li.task' ? li : null),
  };
  const row = { closest: (s: string) => (s === 'li.task' ? li : null) };
  return { dataset: {}, closest: (s) => (s === '.task-row' ? row : null) };
}

/** A table cell checkbox input (`checked` is its rendered attribute). */
export function cellCheckboxTarget(
  line: number,
  idx: number,
  checked: boolean,
): Target {
  const input: Target = {
    hasAttribute: () => checked,
    dataset: { line: String(line), idx: String(idx) },
    closest: (s) => (s === 'input.cell-task' ? input : null),
  };
  return input;
}

/** A click on a cell's text (not its checkbox) holding exactly `box`. */
export function cellBodyTarget(box: Target): Target {
  const td: Target = {
    dataset: {},
    querySelectorAll: (s: string) => (s === 'input.cell-task' ? [box] : []),
    closest: (s) => (s === 'td' ? td : null),
  };
  return { dataset: {}, closest: (s) => (s === 'td' ? td : null) };
}

/**
 * A rendered link. An internal anchor is converted to a .mw-anchor button (id in
 * data-id, no href); external/cross-file and the bare '#' stay plain <a href>.
 */
export function anchorTarget(href: string): Target {
  const internal = href.startsWith('#') && href !== '#';
  const a: Target = {
    dataset: internal ? { id: href.slice(1) } : {},
    getAttribute: (n: string) => (n === 'href' ? href : null),
    closest: (s) => {
      if (s === '.mw-anchor') return internal ? a : null;
      if (s === 'a') return a;
      return null;
    },
  };
  return a;
}

/** Make content.querySelector answer `selector` with a heading at viewport `top`. */
export function seedHeading(
  r: Webview,
  selector: string,
  top: number,
): unknown {
  const el = { getBoundingClientRect: () => ({ top }) };
  byId(r, 'content').querySelector = (s) => (s === selector ? el : null);
  return el;
}

/** A heading mock for the scroll-spy (content.querySelectorAll of h1..h6). */
export interface HeadingMock {
  tagName: string;
  id: string;
  textContent: string;
  style: Record<string, string>;
  getBoundingClientRect: () => { top: number };
  [key: string]: unknown;
}

/** A heading at viewport `top`. */
export function headingEl(
  tag: string,
  id: string,
  text: string,
  top: number,
): HeadingMock {
  return {
    tagName: tag.toUpperCase(),
    id,
    textContent: text,
    style: {},
    getBoundingClientRect: () => ({ top }),
  };
}

/** Feed headings to the scroll-spy through content.querySelectorAll. */
export function withHeadings(
  r: Webview,
  headings: readonly HeadingMock[],
): void {
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === 'h1,h2,h3,h4,h5,h6' ? headings : [];
}

/**
 * A toc/sticky/breadcrumb click target: the controls carry the target id in data-id
 * (not an href) - they are buttons, not native #id anchors, so the smooth
 * navigateToHash is not overridden (#44).
 */
export function segTarget(idx: number, href: string, cls: string): Target {
  const el: Target = {
    dataset: { idx: String(idx), id: href.slice(1) },
    getBoundingClientRect: () => ({ left: 10, bottom: 30 }),
    closest: (s) => (s === cls ? el : null),
  };
  return el;
}

/** Fire the TOC panel's click listener on entry `idx`, on its twistie gutter or its label. */
export function fireTocClick(r: Webview, idx: number, chevron: boolean): void {
  // chevron=true simulates a click on the twistie gutter (toggles the branch);
  // chevron=false a click on the label (navigates).
  const link: Target = {
    dataset: { idx: String(idx), id: `h${idx}` },
    closest: (s) => {
      if (s === '.toc-link') return link;
      if (s === '.toc-gutter')
        return chevron ? { className: 'toc-gutter' } : null;
      return null;
    },
  };
  listenerOf(byId(r, 'toc'), 'click')({ target: link, preventDefault() {} });
}

/** a, b (child of a), c: tocBranches[0] holds b (a parent), [1]/[2] are null (leaves). */
export async function tocFixture(): Promise<Webview> {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, [
    headingEl('h1', 'a', 'A', 0),
    headingEl('h2', 'b', 'B', 1000),
    headingEl('h1', 'c', 'C', 2000),
  ]);
  r.send(topConfig({ toc: tocCfg({ mode: 'rail' }) }));
  r.send({ type: 'render', html: 'x' });
  return r;
}

/**
 * Drive the top bars into an active chain, then return the webview so the
 * breadcrumb/dropdown click handlers can be exercised.
 */
export async function withActiveChain(
  headings: readonly HeadingMock[],
): Promise<Webview> {
  const r = await startWebview({
    viewWidth: 1600,
    docHeight: 8000,
    viewHeight: 800,
  });
  withHeadings(r, headings);
  r.send(topConfig());
  r.send({ type: 'render', html: 'x' });
  r.window.scrollY = 700;
  scroll(r);
  r.window.scrollY = 0; // chain is established; reset so absTop == the heading's rect top
  return r;
}

/** The current combined top-bar height, read live from the geometry module. */
export async function topBarsOffsetOf(r: Webview): Promise<number> {
  return (await r.load('top-bars/geometry.ts')).topBarsOffset;
}

/** A line-map element for seedLineEntries: source line(s), document top, height. */
export interface LineSeed {
  line: number;
  top: number;
  height?: number;
  /** Last source line of a multi-line block (a fence's data-line-end). */
  endLine?: number;
}

/** [data-line] elements at the seeded tops; `scrollY` reads the current scroll offset. */
export function lineEls(entries: readonly LineSeed[], scrollY: () => number) {
  return entries.map((e) => ({
    dataset:
      e.endLine === undefined
        ? { line: String(e.line) }
        : { line: String(e.line), lineEnd: String(e.endLine) },
    getBoundingClientRect: () => ({
      top: e.top - scrollY(),
      height: e.height || 20,
    }),
  }));
}

/** Seed the [data-line] elements and cache their tops (as a render would). */
export async function seedLineEntries(
  r: Webview,
  entries: readonly LineSeed[],
): Promise<void> {
  const els = lineEls(entries, () => r.window.scrollY);
  byId(r, 'content').querySelectorAll = (sel) =>
    sel === '[data-line]' ? els : [];
  (await r.load('scroll-sync/line-metrics.ts')).lineMetrics.collect();
}

/** The header sort button of column `col` in the table whose header sits on `line`. */
export function sortButton(line: number, col: number): Target {
  const table = { dataset: { line: String(line) } };
  const btn: Target = {
    dataset: { col: String(col) },
    closest: (s) => (s === '.mw-sort' ? btn : s === 'table' ? table : null),
  };
  return btn;
}

/**
 * A wrapper mock whose table counts getBoundingClientRect calls, so a test can
 * assert the scroll path never measures (it reads cached geometry instead).
 */
export function mkScrollWrap(scrolls: boolean, viewportTop: number) {
  const head = {
    style: { transform: 'translateY(99px)' },
    getBoundingClientRect: () => ({ height: 40 }),
  };
  const table = {
    gbcr: 0,
    getBoundingClientRect: (): { top: number; height: number } => {
      table.gbcr++;
      return { top: viewportTop, height: 400 };
    },
  };
  const classes: Record<string, boolean | undefined> = {};
  return {
    head,
    table,
    scrollWidth: scrolls ? 200 : 100,
    clientWidth: 100, // scrollWidth > clientWidth -> element-scrolling
    classList: {
      toggle: (c: string, v?: boolean) => {
        classes[c] = v;
      },
      contains: (c: string) => !!classes[c],
    },
    querySelector: (sel: string) => (sel === 'thead' ? head : table),
  };
}

/**
 * Slider grab setup (like the editor minimap). Fixed geometry for the grab tests:
 * fill mode, doc 8000, view 800, rail 800 -> mapSy = 0.1, mapOffset = 0; scrollY
 * 3600 -> slider rect [360, 440] (top 360, height 80).
 */
export async function sliderSetup(): Promise<{
  r: Webview;
  fire: (type: string, clientY: number) => void;
}> {
  const r = await startWebview({
    docHeight: 8000,
    viewHeight: 800,
    railHeight: 800,
  });
  r.window.scrollY = 3600;
  r.send({ type: 'config', maxWidth: '980px', minimap: MM({ size: 'fill' }) });
  r.send({ type: 'render', html: '<p>x</p>' });
  const minimap = byId(r, 'minimap');
  const fire = (type: string, clientY: number) =>
    listenerOf(minimap, type)({ clientY, pointerId: 1, preventDefault() {} });
  return { r, fire };
}

/** One top-level block of the fold fixture, counting its writes and layout reads. */
export interface FoldBlock {
  tagName: string;
  id: string;
  textContent: string;
  style: Record<string, string>;
  dataset: Record<string, string>;
  writes: number;
  rects: number;
  offsetParentReads: number;
  _classes: Record<string, boolean | undefined>;
  classList: {
    toggle(c: string, v?: boolean): void;
    contains(c: string): boolean;
  };
  readonly offsetParent: null;
  querySelector(s: string): unknown;
  getBoundingClientRect(): { top: number; height: number };
  chevron: { classList: { toggle(c: string, v?: boolean): void } };
  chevronFolded?: boolean;
  parentElement: unknown;
}

/** The minimap clone of the fold fixture (children index-parallel to the blocks). */
export interface FoldClone {
  children: FoldBlock[];
  removed: string[];
  removeAttribute(a: string): void;
  querySelectorAll(): unknown[];
}

/**
 * A #content mock rich enough for the whole fold pipeline: top-level blocks that
 * count their class writes, layout reads and rect measurements, the [data-line]
 * map and the heading list the scroll-spy collects, plus a minimap clone whose
 * children are index-parallel to the blocks (what the fold mirror relies on).
 * `spec` is [tag, id] per block; a non-heading tag ('p') carries no id.
 */
export function foldDom(
  r: Webview,
  spec: readonly (readonly [string, string])[],
) {
  const content = byId(r, 'content');
  const mk = ([tag, id]: readonly [string, string], i: number): FoldBlock => {
    const el: FoldBlock = {
      tagName: tag.toUpperCase(),
      id,
      textContent: id || `block${i}`,
      style: {},
      dataset: { line: String(i + 1) },
      writes: 0,
      rects: 0,
      offsetParentReads: 0,
      _classes: {},
      classList: {
        toggle(c, v) {
          el.writes++;
          el._classes[c] = v === undefined ? !el._classes[c] : v;
        },
        contains: (c) => !!el._classes[c],
      },
      // Reading offsetParent forces a synchronous layout - the fold path must not
      // touch it, so every read is counted.
      get offsetParent() {
        el.offsetParentReads++;
        return null;
      },
      querySelector: (s) => (s === '.mw-fold-toggle' ? el.chevron : null),
      getBoundingClientRect() {
        el.rects++;
        return { top: (i + 1) * 100, height: 20 };
      },
      chevron: {
        classList: {
          toggle: (_c, v) => {
            el.chevronFolded = v;
          },
        },
      },
      parentElement: content,
    };
    return el;
  };
  const blocks = spec.map(mk);
  const headings = blocks.filter((b) => /^H[1-6]$/.test(b.tagName));
  content.children = blocks;
  content.querySelectorAll = (sel) => {
    if (sel === 'h1,h2,h3,h4,h5,h6') return headings;
    if (sel === '[data-line]') return blocks;
    return [];
  };
  const clone: FoldClone = {
    children: spec.map(mk),
    removed: [],
    removeAttribute(a) {
      clone.removed.push(a);
    },
    querySelectorAll: () => [],
  };
  const clones = { count: 0 };
  content.cloneNode = () => {
    clones.count++;
    return clone;
  };
  return { content, blocks, headings, clone, clones };
}

/** The document used by the fold-perf tests: two sections, the second one nested. */
export const FOLD_SPEC: readonly (readonly [string, string])[] = [
  ['h1', 'a'],
  ['p', ''], // 0 h1 a, 1 p
  ['h2', 'b'],
  ['p', ''],
  ['p', ''], // 2 h2 b (under a), 3 p, 4 p
  ['h1', 'c'],
  ['p', ''], // 5 h1 c, 6 p
];

/** Render the fold fixture; clone counting starts after the render's own clones. */
export function renderFoldDom(r: Webview): ReturnType<typeof foldDom> {
  const dom = foldDom(r, FOLD_SPEC);
  r.send(topConfig({ minimap: MM() }));
  r.send({ type: 'render', html: '<h1 id="a">A</h1>' });
  dom.clones.count = 0; // count clones from here: config and render each build one
  return dom;
}

// Outlasts both idle slots after a toggle: fold re-measure, then minimap mirror (runWhenIdle, DECISIONS.md #47).
// Each slot is a zero-delay timer the one before queues; timers of one delay run in the order they
// were queued, so three zero-delay turns in a row come after both, however late the timers fire.
export async function settleFold(): Promise<void> {
  for (let turn = 0; turn < 3; turn++)
    await new Promise((resolve) => setTimeout(resolve, 0));
}
