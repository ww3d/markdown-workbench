// In-page navigation: "#slug" targets inside #content, reached from the content's
// own anchor links, the TOC, the breadcrumb and the sticky rows.

import { visibleFoldAnchor } from '../folding/sections.ts';
import { absTop, content } from '../page/content.ts';
import { topBarsOffset } from '../top-bars/geometry.ts';

/**
 * Scroll the window to a document-y position. Smooth for deliberate jumps
 * (TOC clicks); instant for the internal anchor links so the source editor
 * mirrors the final position immediately (as before the TOC existed).
 */
export function scrollWindowTo(top: number, smooth: boolean): void {
  if (smooth)
    window.scrollTo({ top, left: window.scrollX, behavior: 'smooth' });
  else window.scrollTo(window.scrollX, top);
}

/**
 * Resolve a "#slug" fragment to a heading inside #content and scroll to it.
 * Returns true when a target was found and scrolled to. Shared by the content
 * anchor links and the TOC entries. The lookup is scoped to #content (the
 * skeleton carries its own ids), guards the empty hash, and tolerates a
 * malformed percent-escape (a raw HTML anchor may carry one).
 */
export function navigateToHash(
  fragment: string | undefined,
  smooth: boolean,
): boolean {
  let hash = fragment ?? '';
  try {
    hash = decodeURIComponent(hash);
  } catch (_) {
    /* keep the literal hash */
  }
  if (!hash) return false;
  // A folded-away target heading is display:none (its rect is 0, so scrolling to
  // it walked the view upward on every click). Redirect to the section header it
  // collapsed into so the jump lands on the visible, collapsed heading (#44 P2).
  hash = visibleFoldAnchor(hash);
  const target = content.querySelector<HTMLElement>(`#${CSS.escape(hash)}`);
  if (!target) return false;
  // Land below the fixed top bars using the TARGET heading's own bars height (its
  // published scroll-margin-top), not the transient global topBarsOffset: on the
  // first navigation from the top the active chain - and thus the sticky stack -
  // is not built yet, so the global offset lands the heading a few px off and it
  // shifts once the stack appears (#44). Falls back to the global offset when the
  // heading carries no per-heading margin yet (bars off / before the first render).
  const perHeading = target.style
    ? Number.parseFloat(target.style.scrollMarginTop)
    : Number.NaN;
  const offset = Number.isNaN(perHeading) ? topBarsOffset : perHeading;
  scrollWindowTo(Math.max(0, absTop(target) - offset), smooth);
  return true;
}

/**
 * Convert in-page anchors ([..](#id)) to buttons so the webview performs NO native
 * #id fragment jump: strip the href (which triggers the jump), keep the id in
 * data-id, and tag them .mw-anchor for the click handler. External and cross-file
 * links (href not starting with '#', and the bare '#') are left untouched. Run once
 * per render, before the metrics are measured.
 */
export function convertInternalAnchors(root?: Element): void {
  const scope = root || content;
  const anchors = scope.querySelectorAll
    ? scope.querySelectorAll<HTMLElement>('a[href^="#"]')
    : [];
  for (const a of anchors) {
    const href = a.getAttribute ? a.getAttribute('href') : null;
    if (!href || href === '#') continue; // a bare "#" is not a navigable target
    a.dataset.id = href.slice(1);
    if (a.removeAttribute) a.removeAttribute('href');
    a.setAttribute('role', 'button');
    if (a.classList) a.classList.add('mw-anchor');
  }
}
