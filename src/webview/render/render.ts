// The render message: morph the host's HTML into #content and re-measure
// everything that depends on the rendered document.

import './document.css';
import './lists.css';
import './frontmatter.css';
import morphdom from 'morphdom';
import { convertInternalAnchors } from '../anchors/anchors.ts';
import { applyFolds } from '../folding/fold.ts';
import { injectFoldToggles } from '../folding/sections.ts';
import { rebuildMinimap } from '../minimap/minimap.ts';
import { content } from '../page/content.ts';
import type { RenderMessage } from '../protocol.ts';
import { persistRender } from '../restore/state.ts';
import { lineMetrics } from '../scroll-sync/line-metrics.ts';
import { setDocVersion } from '../tables/sort.ts';
import {
  refreshScrollingHeads,
  updateStickyHeads,
} from '../tables/sticky-head.ts';
import { applySelection } from '../tasks/selection.ts';
import { rebuildToc } from '../toc/tree.ts';

// Last HTML pushed into #content. The render path is fully unconditional (it
// replaces innerHTML, re-clones the minimap, rebuilds the TOC and re-runs the
// scroll-spy), so a redundant render - a theme/config re-post that produced the
// same HTML, or a host that re-pushes on a view-state change - would thrash the
// DOM and reset scroll + fold state. Guarding on the exact HTML makes an
// identical render a no-op: the already-built DOM (and its live scroll/fold
// state) is kept, so switching back to the preview tab never rebuilds (#44 P2).
let lastRenderedHtml: string | null = null;

/** Apply a render message: morph #content to the new HTML unless it is identical. */
export function onRender(msg: RenderMessage): void {
  setDocVersion(msg.version);
  if (msg.html !== lastRenderedHtml) {
    // A throw below leaves #content half-built: the next render must run, and the broken one
    // counts neither as shown nor as a stand to restore.
    lastRenderedHtml = null;
    // Build the incoming tree off-DOM and bring it to our post-processed shape
    // (in-page anchors -> buttons, a fold control on each foldable heading) BEFORE
    // diffing, so morphdom matches like-for-like and preserves the unchanged nodes.
    // A content edit then patches only what changed - scroll position and text
    // selection survive - instead of the innerHTML replace that rebuilt (and
    // reset) the whole view. This is how the built-in preview updates too (it
    // morphdom's its DOM). Fold state is re-asserted on the live tree by applyFolds.
    const incoming = document.createElement('div');
    incoming.innerHTML = msg.html;
    convertInternalAnchors(incoming); // in-page [..](#id) links -> buttons, so no native #id jump (#44)
    injectFoldToggles(incoming); // a fold control on each foldable heading (#44 P2)
    morphdom(content, incoming, { childrenOnly: true }); // patch #content's children in place
    applyFolds(true); // re-apply persisted folds in full (morphdom synced our classes away)
    lineMetrics.collect(); // cache the new [data-line] tops for the scroll-sync hot path
    applySelection();
    rebuildMinimap();
    rebuildToc(); // new headings -> rebuild the TOC and re-run the scroll-spy
    refreshScrollingHeads(); // re-measure now the breadcrumb padding (has-breadcrumb) is applied
    updateStickyHeads();
    lastRenderedHtml = msg.html;
  }
  persistRender(msg.html, msg.key); // an identical HTML may carry a new key
}
