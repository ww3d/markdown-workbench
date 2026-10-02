// Viewport and content-box changes: re-measure what reflow moves and re-decide the
// TOC rail/fab split.

import { foldMetricsStale } from '../folding/refresh.ts';
import { rebuildMinimap } from '../minimap/minimap.ts';
import { scrollSpy } from '../scroll-spy/spy.ts';
import { lineMetrics } from '../scroll-sync/line-metrics.ts';
import {
  refreshScrollingHeads,
  updateStickyHeads,
} from '../tables/sticky-head.ts';
import { updateTocLayout } from '../toc/layout.ts';

// A viewport resize rebuilds the minimap (clone scale) and re-decides the TOC
// rail/fab split; heading positions shift with reflow, so refresh their cached
// tops and re-run the scroll-spy.
function onViewportResize(): void {
  rebuildMinimap();
  scrollSpy.refreshMetrics();
  lineMetrics.refresh(); // reflow shifts the cached line tops
  refreshScrollingHeads(); // reflow shifts the cached table tops too
  updateTocLayout();
  scrollSpy.update(); // bar heights are constant, so no rebuild is needed here
  updateStickyHeads();
}

/** Register the window resize handler. */
export function installViewportResize(): void {
  window.addEventListener('resize', onViewportResize, { passive: true });
}

/**
 * Observe the body's content box: image loads and the minimap padding shift
 * heading positions and can flip the rail/fab threshold without a window resize.
 */
export function installResizeObserver(): void {
  if (typeof ResizeObserver === 'function') {
    new ResizeObserver(() => {
      // A fold changes the body height too, so this fires on every toggle. Skip it
      // while a fold re-measure is pending: that pass measures the same tops again
      // (so the work would be done twice per toggle), and it is the only one that
      // re-filters the folded-away blocks first - measuring them here would put the
      // just-hidden entries at top 0 and break the monotonic line->pixel map the
      // scroll sync binary-searches.
      if (foldMetricsStale) return;
      scrollSpy.refreshMetrics();
      lineMetrics.refresh(); // image loads / reflow shift the cached line tops
      updateTocLayout();
      scrollSpy.update();
    }).observe(document.body);
  }
}
