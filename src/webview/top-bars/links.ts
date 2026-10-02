// The top bars' segments and rows: built once, then reconciled in place so a
// re-render only touches text and attributes (no innerHTML reparse).

import { foldedIds } from '../folding/sections.ts';
import { byId } from '../page/content.ts';
import type { Heading } from '../scroll-spy/spy.ts';
import { MAX_STICKY_ROWS } from './geometry.ts';

/**
 * A bar control (breadcrumb segment or sticky row) with the values last written
 * to it cached on the node, so an unchanged re-render skips the DOM write.
 */
export interface NavLink extends HTMLAnchorElement {
  _cls?: string;
  _id?: string;
  _text?: string;
  _label?: HTMLSpanElement;
  _twistie?: HTMLElement;
}

/** A bar element that keeps its live controls, in order. */
export interface LinkBar extends HTMLElement {
  _links?: NavLink[];
}

/** The breadcrumb bar. */
export const breadcrumb: LinkBar = byId('breadcrumb');
/** The sticky-scroll stack. */
export const stickyScroll: LinkBar = byId('sticky-scroll');

/**
 * Label for the root breadcrumb segment shown above the first heading: the
 * document's leading H1 (its de-facto title) when present, else a neutral
 * fallback. Pure; unit-tested.
 */
export function rootLabel(
  headings: readonly Pick<Heading, 'level' | 'text'>[],
): string {
  const first = headings[0];
  return first && first.level === 1 && first.text ? first.text : 'Document';
}

/**
 * Reconcile a bar's <a> children to exactly `count`, reusing existing nodes
 * (create/remove only the delta) and calling setup(link, i) for each. Keeps the
 * live nodes on the element so a same-count re-render only touches text/attrs,
 * not the node list - no innerHTML reparse, minimal layout churn. Separators are
 * pure CSS (.breadcrumb-seg::before), so there are no separator nodes to manage.
 */
export function reconcileLinks(
  barEl: LinkBar,
  count: number,
  setup: (link: NavLink, i: number) => void,
): void {
  barEl._links ??= [];
  const links = barEl._links;
  while (links.length < count) {
    const link = document.createElement('a');
    // A control, not a link: no href, so the VS Code webview cannot run its
    // native (instant) #id jump that would override the smooth navigateToHash
    // (#44 follow-up). role="button" keeps the semantics; the target id lives in
    // data-id.
    link.setAttribute('role', 'button');
    link.tabIndex = -1;
    barEl.appendChild(link);
    links.push(link);
  }
  while (links.length > count) {
    const link = links.pop();
    if (link?.remove) link.remove();
  }
  for (let i = 0; i < count; i++) {
    const link = links[i];
    if (link) setup(link, i);
  }
}

// Set a link's class/href/index/text, skipping DOM writes that would not change
// anything (cached on the node) so an in-place re-render is cheap.
function setLink(
  link: NavLink,
  className: string,
  id: string,
  idx: number,
  text: string,
): void {
  if (link._cls !== className) {
    link.className = className;
    link._cls = className;
  }
  if (link._id !== id) {
    link.dataset.id = id;
    link._id = id;
  }
  const idxStr = String(idx);
  if (link.dataset.idx !== idxStr) link.dataset.idx = idxStr;
  // Built once: a gutter holding the fold twistie (a native codicon chevron) + the
  // ellipsized label. The gutter click folds the section, the label click navigates
  // (#44 P2). Same structure as a TOC entry.
  let label = link._label;
  if (!label) {
    const gutter = document.createElement('span');
    gutter.className = 'sticky-gutter';
    const twistie = document.createElement('i');
    twistie.className = 'codicon codicon-chevron-right sticky-twistie';
    twistie.setAttribute('aria-hidden', 'true');
    gutter.appendChild(twistie);
    link.appendChild(gutter);
    label = document.createElement('span');
    label.className = 'sticky-label';
    link.appendChild(label);
    link._label = label;
    link._twistie = twistie;
  }
  if (link._text !== text) {
    label.textContent = text;
    link._text = text;
  }
  // Reflect the fold state (folded -> chevron points right) so a re-render keeps
  // the sticky twistie in sync with the document.
  if (link._twistie?.classList) {
    link._twistie.classList.toggle('mw-folded', foldedIds.has(id));
  }
}

// Set a breadcrumb segment: the label text lives in a child `.breadcrumb-label`
// span (built once) so the highlight/hover background is a pill around the text
// only, and the separator (a ::before on the segment, outside the label) sits
// between segments rather than inside a segment's highlight (#44). The
// segment itself is a fixed-height flex box, so every segment - highlighted or
// not, short label or long - has the same box height.
function setBreadcrumbSeg(
  link: NavLink,
  className: string,
  id: string,
  idx: number,
  text: string,
): void {
  if (link._cls !== className) {
    link.className = className;
    link._cls = className;
  }
  if (link._id !== id) {
    link.dataset.id = id;
    link._id = id;
  }
  const idxStr = String(idx);
  if (link.dataset.idx !== idxStr) link.dataset.idx = idxStr;
  let label = link._label;
  if (!label) {
    label = document.createElement('span');
    label.className = 'breadcrumb-label';
    link.appendChild(label);
    link._label = label;
  }
  if (link._text !== text) {
    label.textContent = text;
    link._text = text;
  }
}

/**
 * Render the breadcrumb: one segment per chain entry, or a single root segment
 * above the first heading (sentinel index -1: no picker, click scrolls to top).
 */
export function renderBreadcrumb(
  chain: readonly number[],
  headings: readonly Heading[],
): void {
  if (chain.length) {
    reconcileLinks(breadcrumb, chain.length, (link, i) => {
      const idx = chain[i] ?? -1;
      const heading = headings[idx];
      if (!heading) return;
      setBreadcrumbSeg(link, 'breadcrumb-seg', heading.id, idx, heading.text);
    });
  } else {
    reconcileLinks(breadcrumb, 1, (link) =>
      setBreadcrumbSeg(
        link,
        'breadcrumb-seg breadcrumb-root',
        '',
        -1,
        rootLabel(headings),
      ),
    );
  }
}

/**
 * Render the sticky-scroll stack: one pinned row per chain entry (root-first),
 * classed by heading level for the indent/size, capped at MAX_STICKY_ROWS (the
 * nearest ancestors kept; the full path stays in the breadcrumb). Returns the
 * number of rows rendered, for the computed height. No layout read.
 */
export function renderSticky(
  chain: readonly number[],
  headings: readonly Heading[],
): number {
  const start = Math.max(0, chain.length - MAX_STICKY_ROWS);
  const rows = chain.length - start;
  reconcileLinks(stickyScroll, rows, (link, i) => {
    const idx = chain[start + i] ?? -1;
    const heading = headings[idx];
    if (!heading) return;
    setLink(
      link,
      `sticky-row sticky-level-${heading.level}`,
      heading.id,
      idx,
      heading.text,
    );
  });
  return rows;
}
