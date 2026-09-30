// --- Minimap: scaled clone, proportional panning, click/drag to navigate ---

import './minimap.css';
import { byId, content } from '../page/content.ts';
import {
  foldedIds,
  hiddenBlocks,
  setBlockHidden,
} from '../folding/sections.ts';
import { updateStickyHeads, updateTableScroll } from '../tables/sticky-head.ts';
import type { MinimapConfig } from '../protocol.ts';

/** The minimap rail. */
export const minimap = byId('minimap');
/** The scaled clone's container inside the rail. */
export const mapContent = byId('minimap-content');
/** The viewport slider on the rail. */
export const mapSlider = byId('minimap-slider');

/** The minimap settings in effect: the host's config merged over the defaults. */
export let minimapCfg: MinimapConfig = {
  enabled: true,
  size: 'proportional',
  showSlider: 'mouseover',
  side: 'right',
};
let mapKx = 0.1; // horizontal scale: rail width / content width
/** Vertical scale of the active size mode (rail px per document px). */
export let mapSy = 0.1;
/** translateY pan of the clone in rail px (proportional mode only). */
export let mapOffset = 0;

/** Apply the host's minimap config (merged over the defaults) and rebuild the rail. */
export function applyMinimapCfg(cfg: MinimapConfig | undefined): void {
  // Merge over defaults so a missing or partial config can never null
  // out minimapCfg or hide the rail via undefined.
  const merged = Object.assign(
    {
      enabled: true,
      size: 'proportional',
      showSlider: 'mouseover',
      side: 'right',
    },
    cfg || {},
  );
  if (merged.enabled === undefined) merged.enabled = true;
  minimapCfg = merged;
  document.body.classList.toggle('minimap-left', merged.side === 'left');
  minimap.classList.toggle(
    'slider-mouseover',
    merged.showSlider === 'mouseover',
  );
  rebuildMinimap();
}

/**
 * Whether the minimap rail is shown: enabled and the page actually overflows.
 * Stays shown while a section is folded (#44 P2): folding can shrink the page
 * below the viewport, and letting the minimap auto-hide then would drop its
 * reserved padding and slide the content sideways. This is the only fold-aware
 * bit; the minimap's rendering is untouched.
 */
export function minimapNeeded(): boolean {
  return (
    !!minimapCfg.enabled &&
    (document.documentElement.scrollHeight - window.innerHeight > 0 ||
      foldedIds.size > 0)
  );
}

// The clone's top-level blocks, index-parallel to #content's children (the clone
// is a deep copy, so its i-th child IS the i-th block). Cached on rebuild so a
// fold can mirror itself onto the existing clone (mirrorFoldsToMinimap) instead
// of re-cloning the document, which was the fold path's dominant cost.
let mapBlocks: Element[] = [];

// cloneNode is typed as returning a Node; the deep clone of #content is an element.
function isElementClone(node: Node): node is HTMLElement {
  return 'querySelectorAll' in node;
}

/** Re-clone the document into the rail and recompute the scales (render/config/resize). */
export function rebuildMinimap(): void {
  // Visibility first: while the rail is display:none its clientWidth is 0,
  // which would bake a scale of 0 into the clone on the very first render.
  const needed = minimapNeeded();
  document.body.classList.toggle('has-minimap', needed);
  // After the has-minimap toggle (the breakout cap depends on it) and before
  // measuring: wrapper scrollbars change content height. rebuildMinimap runs
  // on render, config and resize - exactly the moments the cap can change.
  updateTableScroll();
  updateStickyHeads();
  mapContent.innerHTML = '';
  mapBlocks = [];
  if (!needed) return;
  const clone = content.cloneNode(true);
  if (!isElementClone(clone)) return;
  for (const input of clone.querySelectorAll('input')) input.disabled = true;
  // cloneNode duplicates every heading id into the minimap - and #content's own id
  // onto the clone root; duplicate ids are invalid HTML, so strip both. (The anchor
  // lookup is separately scoped to #content, so the clone could never win it
  // either.)
  if (clone.removeAttribute) clone.removeAttribute('id');
  for (const el of clone.querySelectorAll('[id]')) el.removeAttribute('id');
  // The clone must not freeze the emulated sticky state: the minimap shows
  // the document, not the current header pin.
  for (const head of clone.querySelectorAll<HTMLElement>('thead'))
    head.style.transform = '';
  mapContent.appendChild(clone);
  mapBlocks = clone.children ? [...clone.children] : [];
  mapKx =
    content.clientWidth > 0 ? minimap.clientWidth / content.clientWidth : 0.1;
  mapContent.style.width = `${content.clientWidth}px`;
  updateMinimap();
}

/** Place the slider and pan/scale the clone for the current scroll position. */
export function updateMinimap(): void {
  const docH = document.documentElement.scrollHeight;
  const viewH = window.innerHeight;
  const scrollMax = docH - viewH;
  // Stay shown while a section is folded, even if the folded page now fits, so the
  // minimap does not auto-hide mid-fold and slide the content sideways (#44 P2).
  if (!minimapCfg.enabled || (scrollMax <= 0 && foldedIds.size === 0)) {
    document.body.classList.remove('has-minimap');
    return;
  }
  document.body.classList.add('has-minimap');
  const railH = minimap.clientHeight;
  if (minimapCfg.size === 'fill') {
    // Whole document maps linearly onto the full rail: the slider stays
    // aligned with the real scrollbar, nothing pans.
    mapSy = railH / docH;
    mapOffset = 0;
  } else if (minimapCfg.size === 'fit') {
    // Downscale until the document fits the rail, never stretch.
    mapSy = Math.min(mapKx, railH / docH);
    mapOffset = 0;
  } else {
    // proportional
    mapSy = mapKx;
    const overflow = Math.max(0, docH * mapKx - railH);
    mapOffset = scrollMax > 0 ? -(window.scrollY / scrollMax) * overflow : 0; // guard the folded-fits case
  }
  mapContent.style.transform = `translateY(${mapOffset}px) scale(${mapKx}, ${mapSy})`;
  mapSlider.style.top = `${window.scrollY * mapSy + mapOffset}px`;
  mapSlider.style.height = `${Math.max(12, viewH * mapSy)}px`;
}

/**
 * Mirror the fold state onto the EXISTING minimap clone: the clone's blocks are
 * index-parallel to #content's, so folding is a class write per block instead of a
 * fresh cloneNode of the whole document (which laid out and painted a second full
 * copy per toggle - measured as the fold path's dominant cost, bench/fold-bench.ts).
 * Returns false when the clone no longer matches the document (a render rebuilt
 * #content, or the rail is hidden), i.e. when a real rebuild is required.
 */
export function mirrorFoldsToMinimap(): boolean {
  const kids = content.children || [];
  if (!mapBlocks.length || mapBlocks.length !== kids.length) return false;
  for (const [i, block] of mapBlocks.entries()) {
    const kid = kids[i];
    setBlockHidden(block, kid !== undefined && hiddenBlocks.has(kid));
  }
  return true;
}
