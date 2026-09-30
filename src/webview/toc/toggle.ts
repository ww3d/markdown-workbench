// TOC clicks: a twistie toggles its branch by hand (#48), a label navigates.

import { navigateToHash } from '../anchors/anchors.ts';
import { eventElement } from '../page/content.ts';
import { setTocOpen, tocOpen, tocPanel } from './layout.ts';
import { tocBranches, tocManualCollapsed, tocManualExpanded } from './tree.ts';

// Whether a click landed on an entry's twistie gutter (vs. its label). The
// twistie is a real node, so the hit is an exact ancestor check - a click on the
// codicon or its gutter toggles, a click on the label navigates. Pure.
function isChevronClick(target: Element): boolean {
  return !!target.closest?.('.toc-gutter');
}

// Arm the sublist expand/collapse transition for a manual toggle only. The class
// enables the grid-template-rows transition (tree.css); a timer clears it so
// the scroll-driven auto expand/collapse (applyTocActive, hot path) stays instant
// - never a per-frame animation during a scroll.
let tocAnimateTimer: ReturnType<typeof setTimeout> | null = null;
function armTocAnimation(): void {
  document.body.classList.add('toc-animating');
  if (tocAnimateTimer !== null) clearTimeout(tocAnimateTimer);
  tocAnimateTimer = setTimeout(() => {
    document.body.classList.remove('toc-animating');
    tocAnimateTimer = null;
  }, 250);
}

// Manual expand/collapse of a TOC branch (#48), sticky against the scroll-spy
// automatic: what the user opened stays open, what they closed stays closed,
// until they toggle it again (a re-render resets it). Records the choice so
// applyTocActive skips this branch. Animated (armTocAnimation) because it is the
// manual path.
function toggleTocBranch(idx: number): void {
  const branch = tocBranches[idx];
  if (!branch) return;
  const collapsed = branch.classList.contains('toc-collapsed');
  armTocAnimation();
  branch.classList.toggle('toc-collapsed', !collapsed);
  if (collapsed) {
    tocManualExpanded.add(idx);
    tocManualCollapsed.delete(idx);
  } else {
    tocManualCollapsed.add(idx);
    tocManualExpanded.delete(idx);
  }
}

/**
 * Register the TOC click handler: a click on the twistie of an entry that has
 * children toggles it (manual, sticky); anything else - the label, or any click
 * on a leaf entry - jumps to the heading (smooth) and closes the overlay.
 */
export function installTocClick(): void {
  tocPanel.addEventListener('click', (e) => {
    const target = eventElement(e);
    const link = target?.closest<HTMLElement>('.toc-link');
    if (!target || !link) return;
    e.preventDefault();
    const idx = Number(link.dataset?.idx);
    if (tocBranches[idx] && isChevronClick(target)) {
      toggleTocBranch(idx);
      return;
    }
    navigateToHash(link.dataset.id, true);
    if (tocOpen) setTocOpen(false);
  });
}
