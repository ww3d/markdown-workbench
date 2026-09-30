// Batched re-measure after a fold (#44 P2, high-perf). Folding changes the
// rendered height, so the cached line tops, heading tops and table tops are stale
// and have to be re-read - once, after the last toggle of a burst, never per
// click.
//
// STRICTLY read-then-write, and the order matters more than it looks: when this
// runs, the fold's own layout is long done and clean, so every measurement below
// is a free read. A write dirties layout again, so anything written before the
// reads makes the first read force that layout back *synchronously inside this
// pass*. Mirroring the minimap first did exactly that - the clone is a second full
// document, and its relayout landed on top of our own measurements (measured: two
// consecutive ~30 ms frames per toggle). Now the reads go first and the minimap
// mirror goes last, into an idle slot, so the clone's relayout happens in the
// browser's own time and never blocks the interaction.
// The re-measure is scheduled into IDLE time instead of onto a fixed timer: a fold
// makes the cached tops stale, but nothing needs them until the reader scrolls or
// navigates. Handing the pass to the browser's idle period is what keeps the
// interaction free of it - the work lands in a frame the browser has nothing else
// to do in, rather than in a fixed frame 120 ms later that may well be a scroll
// frame. Anything that DOES need fresh metrics flushes the pass synchronously
// first (flushFoldMetrics), so nothing ever reads a stale top.

import {
  mirrorFoldsToMinimap,
  minimapNeeded,
  rebuildMinimap,
  updateMinimap,
} from '../minimap/minimap.ts';
import { scrollSpy } from '../scroll-spy/spy.ts';
import { lineMetrics } from '../scroll-sync/line-metrics.ts';
import {
  refreshScrollingHeads,
  updateStickyHeads,
} from '../tables/sticky-head.ts';

// Deadline for the batched re-measure: it runs in the browser's idle time, and this
// is the latest it may be deferred to. Long enough that a burst (clicking through
// several sections) collapses into one pass, short enough that nothing waits on it
// for long - and whoever needs the metrics sooner flushes them (flushFoldMetrics).
const FOLD_REFRESH_DEADLINE_MS = 250;

// Run a job in the browser's idle time, with the deadline as a starvation guard.
// requestIdleCallback where available (Chromium has it), a timeout otherwise.
const runWhenIdle: (fn: () => void) => unknown =
  typeof requestIdleCallback === 'function'
    ? (fn) => requestIdleCallback(fn, { timeout: FOLD_REFRESH_DEADLINE_MS })
    : (fn) => setTimeout(fn, 0);

/** Whether a fold left the cached tops stale; the pending pass clears it. */
export let foldMetricsStale = false;
let foldRefreshHandle: unknown = null;

/** The batched fold re-measure itself: reads first, then the derived writes. */
export function refreshAfterFold(): void {
  // Reads first - no write above this line.
  lineMetrics.collect(); // re-filter the folded-away blocks out of the sync map
  scrollSpy.refreshMetrics(); // the visible heading tops shifted with the height
  refreshScrollingHeads(); // so did the cached table tops
  // Writes: only the small derived positions.
  updateStickyHeads();
  updateMinimap(); // the document height changed: slider + scale
  scrollSpy.update(true); // re-pick the active heading on the fresh tops
  scheduleMinimapFoldMirror();
}

/** Mark the metrics stale and schedule one idle re-measure (a burst shares it). */
export function scheduleFoldRefresh(): void {
  foldMetricsStale = true;
  if (foldRefreshHandle !== null) return; // one pending pass; a burst collapses into it
  foldRefreshHandle = runWhenIdle(() => {
    foldRefreshHandle = null;
    if (foldMetricsStale) {
      foldMetricsStale = false;
      refreshAfterFold();
    }
  });
}

/**
 * Re-measure NOW if a fold left the cached tops stale. Everything that reads a
 * position calls this first - the scroll sync before it reports a source line, the
 * navigation before it computes a target - so deferring the pass into idle time can
 * never surface a stale position. A no-op when nothing is pending, which is the
 * normal case, so the scroll hot path pays one boolean test.
 */
export function flushFoldMetrics(): void {
  if (!foldMetricsStale) return;
  foldMetricsStale = false;
  refreshAfterFold();
}

// Bring the minimap in line with the fold state, off the interaction path: the rail
// is a scaled overview, so being a few frames behind is imperceptible, while the
// clone's relayout is the single most expensive thing a fold triggers. A full rebuild
// is needed only when the rail itself appears or disappears (that changes the content
// width) or when the clone no longer matches the document.
let minimapMirrorPending = false;
function scheduleMinimapFoldMirror(): void {
  if (minimapMirrorPending) return; // a burst of folds collapses into one mirror
  minimapMirrorPending = true;
  runWhenIdle(() => {
    minimapMirrorPending = false;
    const needed = minimapNeeded(),
      shown = document.body.classList.contains('has-minimap');
    if (needed !== shown) rebuildMinimap();
    else if (needed && !mirrorFoldsToMinimap()) rebuildMinimap();
  });
}
