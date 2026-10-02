// Webview scrolled by the user -> tell the extension which source line is
// at the top so it can reveal it in the text editor.

import { flushFoldMetrics } from '../folding/refresh.ts';
import { vscodeApi } from '../host.ts';
import { updateMinimap } from '../minimap/minimap.ts';
import { scrollSpy } from '../scroll-spy/spy.ts';
import { scheduleStateSave } from '../restore/state.ts';
import { updateStickyHeads } from '../tables/sticky-head.ts';
import { sourceLineAtTop } from './line-metrics.ts';

// Until this time (ms since the epoch) scroll events are our own echo of a host
// scrollTo and are not reported back.
let suppressScrollEvents = 0;
let scrollPending = false;

/** Whether the reader has scrolled the view since it loaded (a scroll that was no echo). */
export let readerScrolled = false;

/** Treat scroll events until `until` (ms since the epoch) as the echo of a host scrollTo. */
export function suppressScrollEventsUntil(until: number): void {
  suppressScrollEvents = until;
}

/**
 * Register the window scroll handler: one rAF per burst updates the minimap, the
 * scroll-spy and the emulated table headers, then reports the source line.
 */
export function installScrollReport(): void {
  window.addEventListener(
    'scroll',
    () => {
      if (scrollPending) return;
      scrollPending = true;
      requestAnimationFrame(() => {
        scrollPending = false;
        updateMinimap(); // always - also for editor-driven (suppressed) scrolls
        scrollSpy.update(); // active heading tracks the scroll; refreshes the header inset first
        updateStickyHeads(); // emulated wide-table pin - uses the inset just refreshed above
        scheduleStateSave(); // the scroll line is persisted once the view is quiet
        if (Date.now() < suppressScrollEvents) return;
        readerScrolled = true;
        maybePostScrolled();
      });
    },
    { passive: true },
  );
}

// The 'scrolled' message drives a revealRange on the host (IPC + host work) - at
// ~60Hz in both directions a big source file lags. It is coalesced to ~30Hz with
// a delta gate: skip a sub-line change, post immediately once the window has
// elapsed, else defer a single trailing post so the final rest position always
// syncs (last value wins).
const SCROLL_POST_MIN_INTERVAL = 33; // ms, ~30Hz
const SCROLL_LINE_EPSILON = 0.01; // fractional-line delta below which a post is pointless
let lastPostedLine = -1;
let lastPostTime = 0;
let scrollTrailingTimer: ReturnType<typeof setTimeout> | null = null;

/**
 * Pure decision: 'skip' (no meaningful move), 'post' (window elapsed), or
 * 'defer' (within the window -> trailing post). Unit-tested.
 */
export function scrollPostDecision(
  line: number,
  lastLine: number,
  now: number,
  lastTime: number,
  minIntervalMs: number,
  epsilon: number,
): 'skip' | 'post' | 'defer' {
  if (lastLine >= 0 && Math.abs(line - lastLine) < epsilon) return 'skip';
  return now - lastTime >= minIntervalMs ? 'post' : 'defer';
}

function sendScrolled(line: number): void {
  lastPostedLine = line;
  lastPostTime = Date.now();
  vscodeApi().postMessage({ type: 'scrolled', line: Math.max(0, line) });
}

function maybePostScrolled(): void {
  flushFoldMetrics(); // a fold may have left the tops stale; never report from those
  const line = sourceLineAtTop();
  if (line === null) return;
  const decision = scrollPostDecision(
    line,
    lastPostedLine,
    Date.now(),
    lastPostTime,
    SCROLL_POST_MIN_INTERVAL,
    SCROLL_LINE_EPSILON,
  );
  if (decision === 'skip') return;
  if (decision === 'post') {
    if (scrollTrailingTimer) {
      clearTimeout(scrollTrailingTimer);
      scrollTrailingTimer = null;
    }
    sendScrolled(line);
    return;
  }
  if (!scrollTrailingTimer) {
    // defer: one trailing post with the latest position
    scrollTrailingTimer = setTimeout(() => {
      scrollTrailingTimer = null;
      if (Date.now() < suppressScrollEvents) return;
      const latest = sourceLineAtTop();
      if (latest === null) return;
      if (
        lastPostedLine >= 0 &&
        Math.abs(latest - lastPostedLine) < SCROLL_LINE_EPSILON
      )
        return;
      sendScrolled(latest);
    }, SCROLL_POST_MIN_INTERVAL);
  }
}
