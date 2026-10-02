// --- Fractional scroll sync (algorithms modeled on the built-in preview) ---
//
// The line map: the rendered [data-line] elements and their cached document tops,
// and the fractional source line at the viewport top read from them.

import { isInHiddenBlock } from '../folding/sections.ts';
import { content } from '../page/content.ts';

/** One entry of the line map: a [data-line] element and the source lines it covers. */
export interface LineEntry {
  readonly el: HTMLElement;
  readonly line: number;
  /** Last source line of a multi-line block (code fence), else undefined. */
  readonly endLine: number | undefined;
}

/**
 * Cached line-map entries and their document-coordinate tops. Tops change on
 * layout (render / reflow), never on scroll, so they are read once per rebuild -
 * sourceLineAtTop (the scroll hot path) then binary-searches the cached tops
 * instead of calling getBoundingClientRect on every [data-line] element each
 * frame (O(N) forced layout per frame on a large document). Entries are in
 * document order, which for normal-flow block content means non-decreasing tops.
 */
export const lineMetrics = (() => {
  let entries: LineEntry[] = [];
  let tops: number[] = []; // document-coordinate top of entries[i], ascending
  let heights: number[] = []; // its height (both read once per rebuild, never on scroll)
  function measure(el: Element): { top: number; height: number } {
    const rect = el.getBoundingClientRect();
    return { top: rect.top + window.scrollY, height: rect.height };
  }
  function collect(): void {
    // Skip folded-away blocks (#44 P2): a display:none element measures at top 0,
    // which would corrupt the monotonic line->pixel map the scroll sync binary-
    // searches. The mask comes from the fold state (isInHiddenBlock), not from
    // offsetParent: offsetParent is a layout read, so N of them right after the
    // fold's class writes forced a synchronous document layout per element batch.
    entries = [...content.querySelectorAll<HTMLElement>('[data-line]')]
      .filter((el) => !isInHiddenBlock(el))
      .map((el) => ({
        el,
        line: Number(el.dataset.line),
        endLine: el.dataset.lineEnd ? Number(el.dataset.lineEnd) : undefined,
      }));
    tops = [];
    heights = [];
    for (const e of entries) {
      const m = measure(e.el);
      tops.push(m.top);
      heights.push(m.height);
    }
  }
  function refresh(): void {
    for (let i = 0; i < entries.length; i++) {
      const e = entries[i];
      if (!e) continue;
      const m = measure(e.el);
      tops[i] = m.top;
      heights[i] = m.height;
    }
  }
  return {
    collect,
    refresh,
    get entries(): readonly LineEntry[] {
      return entries;
    },
    get tops(): readonly number[] {
      return tops;
    },
    get heights(): readonly number[] {
      return heights;
    },
  };
})();

/**
 * Largest index i with sorted[i] <= value, or -1. Allocation-free binary search
 * over the ascending line tops; equal tops resolve to the last (deepest) entry.
 */
export function lastIndexAtOrBelow(
  sorted: readonly number[],
  value: number,
): number {
  let lo = 0,
    hi = sorted.length - 1,
    ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if ((sorted[mid] ?? Number.POSITIVE_INFINITY) <= value) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/** Fractional source line currently at the viewport top; null without a line map. */
export function sourceLineAtTop(): number | null {
  const entries = lineMetrics.entries,
    tops = lineMetrics.tops,
    heights = lineMetrics.heights;
  if (!entries.length) return null;
  const offset = window.scrollY;
  // Fully cached: previous = last entry at or above the viewport top (binary
  // search, not an O(N) scan), and its top/height come from the cache - NO
  // getBoundingClientRect here: it would force a full-document layout every frame
  // (the minimap slider and top bars write styles earlier in the same frame), a
  // scroll stutter on large documents.
  const p = lastIndexAtOrBelow(tops, offset + 1);
  const previous = entries[p];
  if (p < 0 || !previous) return 0;
  const previousTop = tops[p] ?? 0;
  const height = heights[p] ?? 0;
  if (
    previous.endLine &&
    previous.endLine > previous.line &&
    height > 0 &&
    offset <= previousTop + height
  ) {
    // Inside a multi-line code block.
    const progress = (offset - previousTop) / height;
    return previous.line + progress * (previous.endLine - previous.line);
  }
  const next = entries[p + 1];
  if (next) {
    const nextTop = tops[p + 1] ?? previousTop;
    if (nextTop > previousTop) {
      const progress = (offset - previousTop) / (nextTop - previousTop);
      return (
        previous.line +
        Math.min(1, Math.max(0, progress)) * (next.line - previous.line)
      );
    }
  }
  if (height > 0) {
    return (
      previous.line + Math.min(1, Math.max(0, (offset - previousTop) / height))
    );
  }
  return previous.line;
}
