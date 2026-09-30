// Restore after a restart (REQ-043, REQ-070): show the persisted stand before the host's
// first render, through the same render path as a `render` message (fold controls,
// minimap, TOC), at the persisted scroll position, and name it for `ready` so the host
// can skip its render when the stand is still current.

import type { ReadyMessage } from '../protocol.ts';
import { onRender } from '../render/render.ts';
import { scrollToSourceLine } from '../scroll-sync/follow.ts';
import { lineMetrics } from '../scroll-sync/line-metrics.ts';
import {
  readerScrolled,
  suppressScrollEventsUntil,
} from '../scroll-sync/report.ts';
import { takeSavedStand } from './state.ts';

// The restored line until the host's first config: its width and bars move the layout, so the
// line is scrolled to again then - unless the reader or a host scrollTo has moved the view.
let pendingScrollLine: number | undefined;

/** What `ready` reports about the restored stand; empty when nothing was restored. */
export type RestoredStand = Pick<
  ReadyMessage,
  'buildId' | 'key' | 'restoredInMs'
>;

/** Show the persisted stand of this build, if there is one; returns it for `ready`. */
export function restoreSavedStand(): RestoredStand {
  const stand = takeSavedStand();
  if (!stand) return {};
  onRender({ type: 'render', html: stand.html, key: stand.key });
  if (stand.scrollLine !== undefined) {
    // Not a reader's scroll: the editor is not moved to it (as for a host scrollTo).
    suppressScrollEventsUntil(Date.now() + 200);
    scrollToSourceLine(stand.scrollLine);
    pendingScrollLine = stand.scrollLine;
  }
  return {
    buildId: stand.buildId,
    key: stand.key,
    restoredInMs: performance.now(),
  };
}

/** After the host's first config: scroll to the restored line again in the new layout. */
export function reassertRestoredScroll(): void {
  const line = pendingScrollLine;
  pendingScrollLine = undefined;
  if (line === undefined || readerScrolled) return;
  lineMetrics.refresh(); // the config moved the cached tops the next state save reads
  suppressScrollEventsUntil(Date.now() + 200);
  scrollToSourceLine(line);
}

/** A host scrollTo takes over from the restored line. */
export function dropRestoredScroll(): void {
  pendingScrollLine = undefined;
}
