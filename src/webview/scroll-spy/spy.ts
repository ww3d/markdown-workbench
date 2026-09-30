// --- Scroll-spy: active heading + ancestor chain (shared base) ---------------
//
// Tracks which heading the reader is under (the last one scrolled past an activation line near the top)
// and that heading's ancestor chain (h1..h6), and notifies subscribers on change: the TOC (toc/) and the
// breadcrumb + sticky-scroll stack (top-bars/). No IntersectionObserver (docs/DECISIONS.md #35): the scroll
// rAF, render and resize call update(); the active index is decided by geometry (pure functions below), so it
// stays correct when several or no headings are on screen.

import { absTop, content } from '../page/content.ts';
import { ancestorChain } from './chain.ts';

const ACTIVATION_OFFSET = 8; // px below the viewport top where a heading counts as reached

/** One heading of the rendered document, in document order. */
export interface Heading {
  readonly el: HTMLElement;
  readonly id: string;
  readonly level: number;
  readonly text: string;
  /** Document-coordinate top, re-read on refreshMetrics. */
  top: number;
}

/** What the scroll-spy tells its subscribers on a change. */
export interface SpyInfo {
  /** Index of the active heading, -1 above the first one. */
  readonly active: number;
  /** The active heading's ancestor chain, root-first (heading indices). */
  readonly chain: readonly number[];
  readonly headings: readonly Heading[];
}

/**
 * Index of the active heading: the last one whose top edge has scrolled above
 * its activation line (scrollY + offset + its own inset). -1 when none has
 * (reader is above the first heading). Each heading docks below a bar stack of
 * its own depth, so its activation line is per-heading, not one global line -
 * this is what keeps the highlight on the heading a #id jump actually lands on,
 * whatever depth it is (#44). `insets` is optional: absent, every heading shares
 * the flat `offset` line (the pre-top-bars behaviour). `hidden` is optional: a
 * folded-away heading (#44 P2) is skipped so its stale/zero top never becomes
 * active nor breaks the monotonic scan. Pure; unit-tested.
 */
export function activeHeadingIndex(
  tops: readonly number[],
  scrollY: number,
  offset: number,
  insets?: readonly number[] | null,
  hidden?: readonly boolean[] | null,
): number {
  let active = -1;
  for (let i = 0; i < tops.length; i++) {
    if (hidden?.[i]) continue;
    const line = scrollY + offset + (insets ? (insets[i] ?? 0) : 0);
    if ((tops[i] ?? 0) <= line + 1) active = i;
    else break;
  }
  return active;
}

/**
 * The scroll-spy: collects the headings on render, re-picks the active one on
 * scroll/render/resize and notifies the subscribers (TOC, top bars) on a change.
 */
export const scrollSpy = (() => {
  let headings: Heading[] = []; // in document order
  // Flat caches of the tops and levels, rebuilt on collect and (tops) on
  // refreshMetrics only. update() runs in the scroll hot path, so it reads
  // these instead of allocating a fresh array every frame.
  let tops: number[] = [];
  let levels: number[] = [];
  let active = -1;
  // Height of fixed UI above the content (the #33 top bars). The activation line
  // sits below it, so a heading scrolled just under the bars counts as active -
  // which keeps the TOC/anchor highlight consistent with where navigateToHash
  // lands a target (it scrolls the target to just below the same bars). A
  // generic inset on the shared base, set by whichever consumer owns the bars.
  let topInset = 0;
  // Per-heading activation insets (px), one per heading in document order: the
  // bar-stack height under which THAT heading docks. When present (same length as
  // tops) they replace the flat topInset, so a deep heading is marked active only
  // once it clears its own taller stack - matching where a #id jump lands it.
  // Set by the bar owner on render/config; layout-stable, so scroll never rewrites it.
  let insets: readonly number[] = [];
  // Per-heading folded-away mask (#44 P2), same order as `headings`: a folded
  // heading's section is hidden so it must not become active. Set by applyFolds.
  let hidden: readonly boolean[] = [];
  const subscribers: ((info: SpyInfo) => void)[] = [];

  // (Re)read the headings from the rendered content. No IntersectionObserver:
  // the scroll rAF pumps update() every frame already, so an IO on every heading
  // would only fire redundant callbacks during a drag (and on a large document
  // it observes hundreds of nodes). update() is driven by scroll / render /
  // resize instead - the single trigger that is actually needed.
  function collect(): void {
    headings = [
      ...content.querySelectorAll<HTMLElement>('h1,h2,h3,h4,h5,h6'),
    ].map((el) => ({
      el,
      id: el.id,
      level: Number(el.tagName.slice(1)),
      text: (el.textContent || '').trim(),
      top: absTop(el),
    }));
    tops = headings.map((h) => h.top);
    levels = headings.map((h) => h.level);
    active = -1;
  }

  // Re-measure cached tops after a reflow (resize, image load) - tops are
  // document coordinates, so they only change on layout, not on scroll.
  function refreshMetrics(): void {
    for (const [i, h] of headings.entries()) {
      h.top = absTop(h.el);
      tops[i] = h.top;
    }
  }

  function emit(): void {
    const info = { active, chain: ancestorChain(levels, active), headings };
    for (const fn of subscribers) fn(info);
  }

  // Recompute the active heading; notify subscribers only when it changes.
  // Hot path (scroll rAF): reads the cached tops, allocates nothing. `force`
  // emits even when the index is unchanged - used once after a rebuild so the
  // initial state (including active = -1, above the first heading) is applied
  // deterministically instead of leaving the freshly rendered TOC in its
  // default-expanded DOM state.
  function update(force?: boolean): void {
    const perHeading = insets.length === tops.length;
    const idx = activeHeadingIndex(
      tops,
      window.scrollY,
      ACTIVATION_OFFSET + (perHeading ? 0 : topInset),
      perHeading ? insets : null,
      hidden.length === tops.length ? hidden : null,
    );
    if (idx === active && !force) return;
    active = idx;
    emit();
  }

  // Set the fixed top inset (px) used by the activation line. Stored only; the
  // next update() applies it, so setting it never re-enters the emit cycle. Falls
  // back to this flat line whenever no per-heading insets are set.
  function setTopInset(px: number): void {
    topInset = px || 0;
  }

  // Set the per-heading activation insets (see `insets` above). A length that no
  // longer matches the current headings (stale array after a rebuild) is ignored
  // by update() until the next matching set, which keeps the flat fallback safe.
  function setInsets(arr: readonly number[] | null): void {
    insets = arr || [];
  }

  // Set the folded-away mask (see `hidden` above). Length-guarded by update() like
  // insets, so a stale array after a rebuild is ignored until the next matching set.
  function setHidden(arr: readonly boolean[] | null): void {
    hidden = arr || [];
  }

  function onChange(fn: (info: SpyInfo) => void): void {
    subscribers.push(fn);
  }

  return {
    collect,
    refreshMetrics,
    update,
    onChange,
    setTopInset,
    setInsets,
    setHidden,
    get headings(): readonly Heading[] {
      return headings;
    },
    get active(): number {
      return active;
    },
  };
})();
