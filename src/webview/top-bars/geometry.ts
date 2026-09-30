// Fixed geometry of the top bars (docs/DECISIONS.md #36) and the offset every
// navigation subtracts to land a heading below them.

/**
 * Combined pixel height of the breadcrumb + sticky-scroll bars (#33). Anchor
 * jumps subtract it so a heading lands below the bars instead of behind them;
 * 0 while both bars are hidden. Computed (not measured) by topBarsHeight in
 * updateTopBars.
 */
export let topBarsOffset = 0;

/** Set the current combined top-bar height (px). */
export function setTopBarsOffset(px: number): void {
  topBarsOffset = px;
}

const SCROLL_MARGIN_GAP = 8; // px breathing room below the bars for anchor jumps
// Fixed bar geometry (docs/DECISIONS.md #36). The bars have fixed heights in the
// stylesheet, so the stack height is *computed* (rows x row height), never
// measured - no getBoundingClientRect in the scroll path. These px values must
// match the stylesheet (#breadcrumb / .sticky-row heights in top-bars.css);
// tests/webview/top-bars/geometry.test.ts asserts they stay in sync.
/** `#breadcrumb` height in px (box-sizing: border-box). */
export const BREADCRUMB_HEIGHT_PX = 28;
/** `.sticky-row` height in px (box-sizing: border-box). */
export const STICKY_ROW_HEIGHT_PX = 22;
/** Cap of the pinned sticky stack (VS Code bounds it too). */
export const MAX_STICKY_ROWS = 5;

/**
 * Combined top-bar height (px), computed from the fixed geometry - never
 * measured, so there is no getBoundingClientRect in the scroll path (the round-6
 * fix for the scroll freeze on large documents). Feeds topBarsOffset
 * (navigateToHash) and the scroll-spy inset. Pure; unit-tested.
 */
export function topBarsHeight(
  breadcrumbShown: boolean,
  stickyRows: number,
): number {
  return (
    (breadcrumbShown ? BREADCRUMB_HEIGHT_PX : 0) +
    stickyRows * STICKY_ROW_HEIGHT_PX
  );
}

/**
 * Publish the constant CSS vars once. --breadcrumb-height positions the stack and
 * reserves the body's top padding; --toc-scroll-margin is set once to the
 * *maximum* stack height (breadcrumb + MAX_STICKY_ROWS x row + gap) so a scroll
 * never rewrites it - and thus never invalidates every heading's scroll-margin
 * style, which was the document-wide recalc behind the freeze. Our own navigation
 * subtracts the exact offset itself; this var only coarsely catches native hash
 * jumps, so an over-estimate is fine.
 */
export function publishTopBarVars(): void {
  const root = document.documentElement.style;
  root.setProperty('--breadcrumb-height', `${BREADCRUMB_HEIGHT_PX}px`);
  root.setProperty(
    '--toc-scroll-margin',
    `${BREADCRUMB_HEIGHT_PX + MAX_STICKY_ROWS * STICKY_ROW_HEIGHT_PX + SCROLL_MARGIN_GAP}px`,
  );
}
