// --- Breadcrumb + sticky-scroll stack (docs/DECISIONS.md #33) ----------------
//
// Two fixed bars pinned to the top of the content region, both consumers of the
// shared scroll-spy (no scroll-spy change): a single-line breadcrumb of the
// active heading's ancestor chain (each segment scrolls to its heading and
// opens a sibling picker), and, directly below it, a sticky-scroll stack of the
// same chain rendered as pinned heading rows (like VS Code's editor sticky
// scroll). The breadcrumb is a constant-height reserved bar; the stack overlays
// content without reserving space, so it swaps in place as the active section
// changes. At active = -1 (reader above the first heading) the breadcrumb is
// empty and the stack is hidden - deterministic via the rebuild's force-emit.

import './top-bars.css';
import { navigateToHash } from '../anchors/anchors.ts';
import { toggleFold } from '../folding/fold.ts';
import { eventElement } from '../page/content.ts';
import type { BarConfig } from '../protocol.ts';
import {
  ancestorChain,
  copyIndices,
  includesIndex,
  indexArraysDiffer,
} from '../scroll-spy/chain.ts';
import { type Heading, type SpyInfo, scrollSpy } from '../scroll-spy/spy.ts';
import { setStickyHeadInset } from '../tables/sticky-head.ts';
import {
  closeDropdown,
  dropdownIdx,
  positionDropdown,
  setDropdownHeadings,
} from './dropdown.ts';
import {
  MAX_STICKY_ROWS,
  setTopBarsOffset,
  topBarsHeight,
  topBarsOffset,
} from './geometry.ts';
import {
  breadcrumb,
  reconcileLinks,
  renderBreadcrumb,
  renderSticky,
  stickyScroll,
} from './links.ts';

let breadcrumbCfg: BarConfig = { enabled: true };
let stickyCfg: BarConfig = { enabled: true };

// Scroll-hot-path change detection. updateTopBars runs on every active-heading
// change; during a fast drag that is nearly every frame. It rebuilds the DOM
// only when something that affects the bars actually changed - a different
// chain, a different heading set (a re-render), or a structural bump (config /
// resize) - and then only incrementally. topBarsGen is the structural bump.
let topBarsGen = 0;
let renderedGen = -1;
let renderedHeadings: readonly Heading[] | null = null;
const renderedChain: number[] = [];

/**
 * Store the bar flags defensively (undefined must never disable a bar), like the
 * minimap/TOC config. Independent toggles: either bar can be off alone. A config
 * change is a structural bump so the next emit rebuilds even if the chain is
 * unchanged (e.g. a live enable/disable).
 */
export function applyTopBarsCfg(
  breadcrumbConfig: BarConfig | undefined,
  stickyConfig: BarConfig | undefined,
): void {
  const crumb = Object.assign({ enabled: true }, breadcrumbConfig || {});
  if (crumb.enabled === undefined) crumb.enabled = true;
  breadcrumbCfg = crumb;
  const sticky = Object.assign({ enabled: true }, stickyConfig || {});
  if (sticky.enabled === undefined) sticky.enabled = true;
  stickyCfg = sticky;
  topBarsGen++; // the next (forced) emit rebuilds the bars and re-docks the header
}

/**
 * Give each heading its OWN dock height (breadcrumb + its ancestor-chain depth in
 * sticky rows) and publish it two ways: as the heading's scroll-margin-top AND as
 * the scroll-spy's activation inset. A VS Code webview performs the native fragment
 * jump when a control link (#id) is clicked, and preventDefault does not stop it, so
 * that jump - not our navigateToHash - lands the final position, using the heading's
 * scroll-margin-top. Feeding the SAME value to the activation line makes the landed
 * heading the active one at every depth. (The earlier single-margin approach used the
 * document-*maximum* for the margin but a lagging global inset for the activation line,
 * so a #id jump from the top - stale inset 0 - marked the previous heading; and a
 * per-heading margin alone still mismatched the flat activation line by a few pixels.)
 * Both are layout-stable, written once per render/config, never on scroll.
 */
export function publishHeadingScrollMargins(): void {
  const headings = scrollSpy.headings;
  const levels = headings.map((h) => h.level);
  const breadcrumbShown = !!breadcrumbCfg.enabled && headings.length > 0;
  const insets = new Array<number>(headings.length);
  for (const [i, heading] of headings.entries()) {
    const rows = stickyCfg.enabled
      ? Math.min(ancestorChain(levels, i).length, MAX_STICKY_ROWS)
      : 0;
    const bars = topBarsHeight(breadcrumbShown, rows);
    insets[i] = bars;
    const el = heading.el;
    if (el?.style) el.style.scrollMarginTop = `${bars}px`;
  }
  // Same per-heading bars drive the activation line, so the heading a #id jump
  // lands (at its scroll-margin) is exactly the one the scroll-spy marks active.
  scrollSpy.setInsets(insets);
}

/**
 * Reflect the active chain in both bars. Subscribed to scroll-spy, so it runs on
 * the initial force-emit and on every active-heading change (the scroll hot
 * path). It rebuilds only when the chain, the heading set (a re-render) or a
 * structural bump (config / resize) changed - so a scroll that does not change
 * the active heading, or a force-emit with the same state, costs nothing.
 */
export function updateTopBars(info: SpyInfo): void {
  const chain = info.chain;
  if (
    info.headings === renderedHeadings &&
    topBarsGen === renderedGen &&
    !indexArraysDiffer(chain, renderedChain)
  )
    return;
  renderedHeadings = info.headings;
  renderedGen = topBarsGen;
  copyIndices(chain, renderedChain);
  setDropdownHeadings(info.headings);

  const breadcrumbShown = !!breadcrumbCfg.enabled && info.headings.length > 0;
  const stickyShown = !!stickyCfg.enabled && chain.length > 0;
  document.body.classList.toggle('has-breadcrumb', breadcrumbShown);
  document.body.classList.toggle('has-sticky', stickyShown);

  if (breadcrumbShown) renderBreadcrumb(chain, info.headings);
  else reconcileLinks(breadcrumb, 0, () => {});
  const stickyRows = stickyShown ? renderSticky(chain, info.headings) : 0;
  if (!stickyShown) reconcileLinks(stickyScroll, 0, () => {});

  // A rebuild changed the segments: keep an open dropdown only while its heading
  // is still on the chain, otherwise it has lost its anchor.
  if (dropdownIdx >= 0 && !includesIndex(chain, dropdownIdx)) closeDropdown();
  else if (dropdownIdx >= 0) positionDropdown(dropdownIdx);
  // Computed height only - no getBoundingClientRect. The table-header dock and the
  // scroll-spy inset both follow the current bars height; the dock write is
  // value-gated, so only a depth change (not every scroll frame) touches the var.
  setTopBarsOffset(topBarsHeight(breadcrumbShown, stickyRows));
  setStickyHeadInset(topBarsOffset);
  scrollSpy.setTopInset(topBarsOffset);
}

/**
 * Register the sticky-row click: a click on a row's twistie gutter folds the
 * section (synced with the document fold control), a click on the label scrolls
 * to the heading.
 */
export function installStickyClick(): void {
  stickyScroll.addEventListener('click', (e) => {
    const target = eventElement(e);
    const row = target?.closest<HTMLElement>('.sticky-row');
    if (!target || !row) return;
    e.preventDefault();
    if (target.closest('.sticky-gutter')) {
      toggleFold(row.dataset.id);
      return;
    }
    navigateToHash(row.dataset.id, true);
  });
}
