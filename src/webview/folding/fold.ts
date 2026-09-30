// Applying the fold state to the DOM: hide the folded sections' blocks, reflect
// the chevrons, and toggle a heading's fold from either fold control.

import './folding.css';
import { content } from '../page/content.ts';
import { scrollSpy } from '../scroll-spy/spy.ts';
import { stickyScroll } from '../top-bars/links.ts';
import { scheduleFoldRefresh } from './refresh.ts';
import {
  computeFoldHidden,
  contentBlocks,
  foldedIds,
  hiddenBlocks,
  isInHiddenBlock,
  setBlockHidden,
} from './sections.ts';

// Reflect a heading's own fold control (chevron rotation) from the fold state.
function reflectFoldToggle(headingEl: Element, folded: boolean): void {
  const t = headingEl?.querySelector?.('.mw-fold-toggle');
  if (t?.classList) t.classList.toggle('mw-folded', folded);
}

// Per block index, the state applyFolds last wrote to the DOM - the baseline for
// the delta below. A render rebuilds the tree (morphdom syncs our injected classes
// away), so the render path re-applies everything via applyFolds(true).
const writtenHidden: boolean[] = [];
const writtenFolded: boolean[] = [];

/**
 * Hide/show the content blocks from the current fold set and reflect each
 * heading's chevron. Writes only what actually CHANGED - a toggle touches the one
 * section's blocks instead of re-writing all of them, and asks for the chevron
 * (a querySelector per heading) only for the heading that flipped. Reads no
 * layout. `full` re-writes every block: after a render the cached baseline no
 * longer describes the DOM. O(blocks); run on a toggle and after a render, never
 * in the scroll hot path.
 */
export function applyFolds(full?: boolean): void {
  const blocks = contentBlocks();
  const hidden = computeFoldHidden(blocks, foldedIds);
  const fresh = full || writtenHidden.length !== blocks.length;
  hiddenBlocks.clear();
  for (const [i, block] of blocks.entries()) {
    const isHidden = hidden[i] === true;
    if (isHidden) hiddenBlocks.add(block.el);
    if (fresh || writtenHidden[i] !== isHidden)
      setBlockHidden(block.el, isHidden);
    writtenHidden[i] = isHidden;
    const folded = block.level > 0 && foldedIds.has(block.id);
    if (block.level > 0 && (fresh || writtenFolded[i] !== folded)) {
      reflectFoldToggle(block.el, folded);
    }
    writtenFolded[i] = folded;
  }
  writtenHidden.length = blocks.length;
  writtenFolded.length = blocks.length;
  // Tell the scroll-spy which headings are folded away, keyed to the same query it
  // collects (so indices align even for a nested heading). Derived from the block
  // mask just built - never from offsetParent, whose layout read inside the click
  // handler was the fold path's forced reflow.
  const heads = content.querySelectorAll
    ? content.querySelectorAll('h1,h2,h3,h4,h5,h6')
    : [];
  scrollSpy.setHidden([...heads].map((el) => isInHiddenBlock(el)));
}

/**
 * Reflect the fold state on the current sticky rows (the twistie a re-render did
 * not rebuild), so a fold toggled anywhere stays in sync on both surfaces.
 */
export function reflectStickyFolds(): void {
  const links = stickyScroll._links;
  if (!links) return;
  for (const link of links) {
    if (link._twistie?.classList) {
      link._twistie.classList.toggle(
        'mw-folded',
        foldedIds.has(link.dataset.id ?? ''),
      );
    }
  }
}

/**
 * Toggle a heading's fold. Everything here is a DOM WRITE (hide the changed
 * blocks, set the mask, reflect both chevrons, re-pick the active heading on the
 * cached tops) - no layout read, so the browser lays the folded document out once,
 * asynchronously, instead of inside the click handler. The re-measure is batched
 * (scheduleFoldRefresh). Reachable from the document fold control and the
 * sticky-row twistie.
 */
export function toggleFold(id: string | undefined): void {
  if (!id) return;
  if (foldedIds.has(id)) foldedIds.delete(id);
  else foldedIds.add(id);
  applyFolds();
  reflectStickyFolds();
  scrollSpy.update(true);
  scheduleFoldRefresh();
}
