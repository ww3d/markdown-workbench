// The TOC tree: built from the headings on every render, highlighted as a delta
// from the scroll-spy's active chain.

import './tree.css';
import { includesIndex } from '../scroll-spy/chain.ts';
import { type Heading, type SpyInfo, scrollSpy } from '../scroll-spy/spy.ts';
import { collectStickyTables } from '../tables/sticky-head.ts';
import { publishHeadingScrollMargins } from '../top-bars/bars.ts';
import { tocList, tocPanel, updateTocLayout } from './layout.ts';

/** Per heading index: its rail entry. */
export const tocLinks: HTMLAnchorElement[] = [];
/** Per heading index: its child list, or null for a leaf. */
export const tocBranches: (HTMLOListElement | null)[] = [];
let tocActiveIdx = -1; // last highlighted index (delta baseline)
const tocActivePath: number[] = []; // last in-path indices (delta baseline, reused)
// Sticky manual expand/collapse state (#48). Kept as small sets outside the
// scroll hot path; the automatic delta consults them (O(1) lookups) so it never
// re-expands a manually collapsed branch nor re-collapses a manually expanded
// one. Cleared on re-render (fresh tree).
/** Heading indices whose branch the reader expanded by hand (#48). */
export const tocManualExpanded = new Set<number>();
/** Heading indices whose branch the reader collapsed by hand (#48). */
export const tocManualCollapsed = new Set<number>();

/** One node of the heading tree. */
export interface TocNode {
  readonly idx: number;
  readonly level: number;
  readonly children: TocNode[];
}

/**
 * Nested tree of heading indices, honoring level jumps: a deeper heading nests
 * under the current node, a shallower/equal one pops back up. Pure; unit-tested.
 */
export function tocTree(levels: readonly number[]): TocNode[] {
  const root: TocNode = { idx: -1, level: 0, children: [] };
  const stack = [root];
  levels.forEach((level, idx) => {
    while (stack.length > 1 && level <= (stack.at(-1)?.level ?? 0)) stack.pop();
    const node: TocNode = { idx, level, children: [] };
    stack.at(-1)?.children.push(node);
    stack.push(node);
  });
  return root.children;
}

// Render the heading tree into a list element, recording each link and each
// branch's child list for the active-state updates. Uses textContent (never
// innerHTML) so heading text can never inject markup into the TOC.
function renderTocInto(
  listEl: HTMLElement,
  nodes: readonly TocNode[],
  headings: readonly Heading[],
): void {
  tocLinks.length = 0;
  tocBranches.length = 0;
  listEl.innerHTML = '';
  const build = (parentOl: HTMLElement, node: TocNode): void => {
    const heading = headings[node.idx];
    if (!heading) return;
    const li = document.createElement('li');
    li.className = 'toc-item';
    const a = document.createElement('a');
    a.className = 'toc-link';
    a.setAttribute('role', 'button'); // a control, not a native #id anchor (#44 follow-up)
    a.dataset.id = heading.id;
    a.dataset.idx = String(node.idx);
    a.tabIndex = -1;
    // A fixed gutter carries the native codicon chevron twistie for a parent, or
    // stays empty for a leaf so labels align at each depth; the label is a
    // separate ellipsized span. A click on the gutter toggles, on the label
    // navigates (isChevronClick).
    const gutter = document.createElement('span');
    gutter.className = 'toc-gutter';
    if (node.children.length) {
      const twistie = document.createElement('i');
      twistie.className = 'codicon codicon-chevron-right toc-twistie';
      twistie.setAttribute('aria-hidden', 'true');
      gutter.appendChild(twistie);
    }
    a.appendChild(gutter);
    const label = document.createElement('span');
    label.className = 'toc-label';
    label.textContent = heading.text;
    a.appendChild(label);
    li.appendChild(a);
    tocLinks[node.idx] = a;
    let childOl: HTMLOListElement | null = null;
    if (node.children.length) {
      // The sublist is wrapped so the expand/collapse can animate via the
      // wrapper's grid-template-rows (0fr<->1fr) without a magic height.
      const wrap = document.createElement('div');
      wrap.className = 'toc-sublist-wrap';
      childOl = document.createElement('ol');
      // Collapsed by default; applyTocActive only expands the active path. This
      // lets the highlight run as an O(path) delta instead of an O(headings)
      // sweep per active-heading change (the fresh tree starts fully collapsed).
      childOl.className = 'toc-sublist';
      childOl.classList.add('toc-collapsed');
      for (const c of node.children) build(childOl, c);
      wrap.appendChild(childOl);
      li.appendChild(wrap);
    }
    tocBranches[node.idx] = childOl;
    parentOl.appendChild(li);
  };
  for (const n of nodes) build(listEl, n);
  // A fresh tree resets the delta baseline (nothing highlighted, all collapsed)
  // and the sticky manual state (#48: a re-render starts clean, like VS Code).
  tocActiveIdx = -1;
  tocActivePath.length = 0;
  tocManualExpanded.clear();
  tocManualCollapsed.clear();
}

/**
 * Reflect the active heading + its ancestor chain as a delta from the previous
 * state: only the links whose active/in-path/collapsed status actually changed
 * are touched (O(path depth), not O(headings)), so a fast scroll that crosses
 * many headings does not re-sweep the whole tree each frame. The fresh tree is
 * built fully collapsed (renderTocInto), so the first apply only expands the
 * active path. Subscribed to the scroll-spy.
 */
export function applyTocActive(info: SpyInfo): void {
  const chain = info.chain;
  if (tocActiveIdx !== info.active) {
    const prev = tocLinks[tocActiveIdx];
    if (prev) prev.classList.toggle('toc-active', false);
    const next = tocLinks[info.active];
    if (next) next.classList.toggle('toc-active', true);
  }
  // Links that left the path: drop the marker, collapse their branch again -
  // unless the user manually expanded it (#48: sticky, stays open off the path).
  for (let k = 0; k < tocActivePath.length; k++) {
    const i = tocActivePath[k] ?? -1;
    if (!includesIndex(chain, i)) {
      const a = tocLinks[i];
      if (a) a.classList.toggle('toc-in-path', false);
      const branch = tocBranches[i];
      if (branch && !tocManualExpanded.has(i))
        branch.classList.toggle('toc-collapsed', true);
    }
  }
  // Links on the new path: mark ancestors, expand their branch - unless the user
  // manually collapsed it (#48: sticky, stays closed on the path).
  for (let k = 0; k < chain.length; k++) {
    const i = chain[k] ?? -1;
    const a = tocLinks[i];
    if (a) a.classList.toggle('toc-in-path', i !== info.active);
    const branch = tocBranches[i];
    if (branch && !tocManualCollapsed.has(i))
      branch.classList.toggle('toc-collapsed', false);
  }
  tocActiveIdx = info.active;
  tocActivePath.length = chain.length;
  for (let k = 0; k < chain.length; k++) tocActivePath[k] = chain[k] ?? -1;
  scheduleActiveReveal();
}

// Keep the active TOC entry visible without a forced reflow per active change.
// The old code called scrollIntoView synchronously on every change - during a
// fast drag that is a per-frame forced layout in the panel. This coalesces into
// a single rAF (separate from the class-toggle writes above, so no read follows
// a write), and scrolls only when the entry is actually outside the panel's
// viewport - a drag that keeps the active entry in view then costs no scroll.
let tocRevealPending = false;
function scheduleActiveReveal(): void {
  if (tocRevealPending) return;
  tocRevealPending = true;
  requestAnimationFrame(() => {
    tocRevealPending = false;
    const link = tocActiveIdx >= 0 ? tocLinks[tocActiveIdx] : null;
    if (!link?.getBoundingClientRect || !tocPanel.getBoundingClientRect) return;
    const panelRect = tocPanel.getBoundingClientRect();
    const linkRect = link.getBoundingClientRect();
    if (linkRect.top < panelRect.top || linkRect.bottom > panelRect.bottom) {
      if (link.scrollIntoView) link.scrollIntoView({ block: 'nearest' });
    }
  });
}

/** Rebuild the TOC from the freshly rendered content (called on every render). */
export function rebuildToc(): void {
  scrollSpy.collect();
  const headings = scrollSpy.headings;
  publishHeadingScrollMargins(); // per-heading scroll-margin so native #id jumps land right
  collectStickyTables();
  renderTocInto(tocList, tocTree(headings.map((h) => h.level)), headings);
  updateTocLayout();
  scrollSpy.update(true); // force-apply the initial state (incl. active = -1)
}
