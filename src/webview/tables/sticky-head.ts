// Sticky table headers: the native `th` pin docked under the top bars, and the
// emulated pin for tables wide enough to scroll inside their own wrapper.

import './tables.css';
import { absTop, content } from '../page/content.ts';

/** Cached layout of one element-scrolling table (document coordinates). */
interface ScrollingHead {
  readonly head: HTMLElement;
  readonly table: Element;
  tableTop: number;
  tableHeight: number;
  headHeight: number;
}

// Top-level table wrappers (src/render/parser.ts) whose table is wider than the
// breakout cap (tables.css) get a horizontal scroll container of their own so the
// window never h-scrolls because of a table. Toggled here and not statically
// in CSS: an unconditional overflow-x would make every wrapper the th
// scrollport and silently disable the sticky table header.
// Toggle the .scrolls class on wide tables (runs on render / config / resize, not
// per scroll) and record whether any table needs the emulated header, so the
// scroll hot path can skip updateStickyHeads' DOM query entirely when none do.
// A table that just stopped scrolling gets its leftover thead transform cleared
// here, so the hot-path skip never leaves a stale pin.
// Cached geometry of the tables that need the emulated header: the document top,
// the table height and the header height are layout values, so they change on
// render/config/resize, never on scroll. Caching them here lets updateStickyHeads
// run from plain numbers on the scroll path - no getBoundingClientRect, which
// forced a synchronous layout every frame and froze scrolling on table-heavy
// documents.
let scrollingHeads: ScrollingHead[] = [];

/**
 * Classify the top-level table wrappers (`.scrolls` on the ones wider than their
 * wrapper) and cache the geometry of the scrolling ones. Runs on render, config
 * and resize - never on the scroll path.
 */
export function updateTableScroll(): void {
  scrollingHeads = [];
  for (const wrap of content.querySelectorAll(':scope > .table-wrap')) {
    const scrolls = wrap.scrollWidth > wrap.clientWidth;
    wrap.classList.toggle('scrolls', scrolls);
    const head = wrap.querySelector<HTMLElement>('thead');
    if (head) head.style.transform = ''; // clear before measuring (and clear a stopped-scrolling pin)
    if (!scrolls || !head) continue;
    const table = wrap.querySelector('table');
    if (!table) continue; // a wrapper always holds its table; nothing to pin without one
    scrollingHeads.push({
      head,
      table,
      tableTop: 0,
      tableHeight: 0,
      headHeight: 0,
    });
  }
  refreshScrollingHeads();
}

/**
 * Re-measure the cached table geometry after a reflow. The dock offset depends on
 * the table's document top, which the breadcrumb's body padding-top shifts - and
 * that padding is applied (has-breadcrumb) after updateTableScroll first runs, so
 * the render path re-measures here once the bars are up. Also on resize/image
 * reflow, mirroring scrollSpy.refreshMetrics.
 */
export function refreshScrollingHeads(): void {
  for (const t of scrollingHeads) {
    t.tableTop = absTop(t.table);
    t.tableHeight = t.table.getBoundingClientRect().height;
    t.headHeight = t.head.getBoundingClientRect().height;
  }
}

/**
 * Vertical header offset for an element-scrolling table: inside a scrolls
 * wrapper the wrapper is the th's scrollport, so native position: sticky is
 * inert against the window scroll - the pin is emulated by translating the
 * thead. topInset docks the pin below the top bars (the current stickyHeadInsetPx,
 * a plain JS number - no CSS-var write), mirroring the native path. Clamped to
 * [0, tableHeight - headHeight] so the header stops at the table's bottom edge
 * instead of ghosting below it. Document coordinates. Pure.
 */
export function stickyHeadOffset(
  scrollY: number,
  tableTop: number,
  tableHeight: number,
  headHeight: number,
  topInset: number,
): number {
  return Math.max(
    0,
    Math.min(scrollY + topInset - tableTop, tableHeight - headHeight),
  );
}

/**
 * Apply the emulated sticky header to every element-scrolling table, from the
 * cached geometry - no DOM query, no getBoundingClientRect, so the scroll hot
 * path forces no layout. The thead stays in-flow, so it keeps scrolling
 * horizontally with the wrapper - columns stay aligned.
 */
export function updateStickyHeads(): void {
  if (!scrollingHeads.length) return; // no element-scrolling table -> nothing to emulate
  const scrollY = window.scrollY;
  for (const t of scrollingHeads) {
    const offset = stickyHeadOffset(
      scrollY,
      t.tableTop,
      t.tableHeight,
      t.headHeight,
      stickyHeadInsetPx,
    );
    t.head.style.transform = offset > 0 ? `translateY(${offset}px)` : '';
  }
}

// Where the sticky table header docks: FLUSH under the *current* bars. The dock
// follows the live stack height (breadcrumb + the current chain's rows), so a
// shallow section docks the header directly under its shorter stack instead of
// under a document-wide maximum that left a visible gap. Set from updateTopBars,
// which recomputes it only when the chain changes; the write is value-gated, so a
// scroll that stays inside a section rewrites nothing. Every th consumes the var,
// so a *per-frame* write was the stutter - but a per-depth-crossing write is rare
// (a handful of tables on a real document) and measured smooth. Emulated
// wide-table headers read stickyHeadInsetPx.
let stickyHeadInsetPx = 0,
  lastStickyHeadVar = '';
let stickyTables: HTMLElement[] = []; // the document's tables, cached per render (the only --sticky-head-top consumers)

/** Dock the table headers `px` below the top edge (the current top-bar height). */
export function setStickyHeadInset(px: number): void {
  stickyHeadInsetPx = px;
  const v = `${px}px`;
  if (v === lastStickyHeadVar) return;
  lastStickyHeadVar = v;
  // Scope the write to the tables, not :root. --sticky-head-top is an inherited
  // custom property, so writing it on :root forces the WHOLE document tree to
  // re-resolve inheritance (measured: a 10x style-recalc blow-up on a large doc).
  // The tables are its only consumers, so each write invalidates just their small
  // thead subtrees.
  for (const t of stickyTables) t.style.setProperty('--sticky-head-top', v);
}

/**
 * Cache the freshly rendered document's table headers as the dock targets. The
 * fresh tables carry no inline var yet, so the next dock write is forced.
 */
export function collectStickyTables(): void {
  stickyTables = [...content.querySelectorAll<HTMLElement>('thead')]; // dock target for the table headers
  lastStickyHeadVar = ''; // fresh tables carry no inline var yet - force the next dock write
}
