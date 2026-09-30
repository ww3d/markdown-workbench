// --- Table of contents: sticky rail, FAB + overlay fallback ------------------
//
// Where the TOC shows: its side (opposite the minimap), rail or floating button
// (FAB) + overlay, and the config that decides it.

import './rail.css';
import './fab.css';
import { minimapCfg } from '../minimap/minimap.ts';
import { byId } from '../page/content.ts';
import type { TocConfig } from '../protocol.ts';
import { scrollSpy } from '../scroll-spy/spy.ts';

const TOC_RESERVE = 240; // body padding reserved on the TOC side in rail mode
const TOC_SIDE_MARGIN = 32; // the plain 2em gutter on the non-minimap side
const MINIMAP_RESERVE = 104; // matches body.has-minimap padding (88px rail + gap)

/** The TOC panel (rail, or the overlay card in FAB mode). */
export const tocPanel = byId('toc');
/** The TOC's root list. */
export const tocList = byId('toc-list');
const tocFab = byId('toc-fab');
const tocBackdrop = byId('toc-backdrop');
let tocCfg: TocConfig = { enabled: true, mode: 'auto' };
let tocMaxWidthPx = 980; // resolved content max-width, the rail-fit input
/** Whether the FAB overlay is open (fab mode only). */
export let tocOpen = false;

/** Set the resolved content max-width (px), the rail-fit threshold input. */
export function setTocMaxWidthPx(px: number): void {
  tocMaxWidthPx = px;
}

/**
 * The rail fits when the viewport can hold the centered content column plus the
 * TOC rail and the opposite-side rail/gutter, side by side. Pure; unit-tested.
 */
export function railFits(
  viewportWidth: number,
  contentWidth: number,
  tocReserve: number,
  sideReserve: number,
): boolean {
  return viewportWidth >= contentWidth + tocReserve + sideReserve;
}

/**
 * Resolve a CSS width value (the configured content max-width) to pixels. px is
 * parsed directly; a font-relative value (72ch) is measured with a hidden probe
 * and falls back to a ~8px/ch estimate if measurement is unavailable.
 */
export function resolveCssWidthPx(value: string): number {
  const parsed = Number.parseFloat(value);
  if (/px\s*$/.test(String(value))) return parsed;
  try {
    const probe = document.createElement('div');
    probe.style.cssText = `position:absolute;visibility:hidden;height:0;width:${value}`;
    document.body.appendChild(probe);
    const w = probe.getBoundingClientRect().width;
    probe.remove();
    if (w && Number.isFinite(w)) return w;
  } catch (_) {
    /* no layout available (headless) -> estimate below */
  }
  return parsed * 8;
}

/**
 * Store the TOC flags defensively (undefined must not disable it or force a
 * mode), mirroring the minimap config handling.
 */
export function applyTocCfg(cfg: TocConfig | undefined): void {
  const merged = Object.assign({ enabled: true, mode: 'auto' }, cfg || {});
  if (merged.enabled === undefined) merged.enabled = true;
  if (merged.mode !== 'rail' && merged.mode !== 'fab') merged.mode = 'auto';
  tocCfg = merged;
}

/**
 * Open/close the FAB overlay (fab mode only). Reflected as body.toc-open and on
 * the FAB's aria-expanded.
 */
export function setTocOpen(open: boolean): void {
  tocOpen = !!open && document.body.classList.contains('toc-fab');
  document.body.classList.toggle('toc-open', tocOpen);
  if (tocFab) tocFab.setAttribute('aria-expanded', tocOpen ? 'true' : 'false');
}

/**
 * Decide the TOC side (opposite the minimap) and the rail/fab presentation, and
 * hide everything when the TOC is disabled or the document has no headings.
 */
export function updateTocLayout(): void {
  const enabled = !!tocCfg.enabled && scrollSpy.headings.length > 0;
  document.body.classList.toggle('has-toc', enabled);
  document.body.classList.toggle('toc-left', minimapCfg.side !== 'left');
  if (!enabled) {
    document.body.classList.remove('toc-rail');
    document.body.classList.remove('toc-fab');
    setTocOpen(false);
    return;
  }
  let rail: boolean;
  if (tocCfg.mode === 'rail') rail = true;
  else if (tocCfg.mode === 'fab') rail = false;
  else
    rail = railFits(
      window.innerWidth,
      tocMaxWidthPx,
      TOC_RESERVE,
      minimapCfg.enabled ? MINIMAP_RESERVE : TOC_SIDE_MARGIN,
    );
  document.body.classList.toggle('toc-rail', rail);
  document.body.classList.toggle('toc-fab', !rail);
  if (rail) setTocOpen(false); // leaving fab mode closes any open overlay
}

/** Register the FAB (opens/closes the overlay) and the backdrop (closes it). */
export function installTocOverlay(): void {
  tocFab.addEventListener('click', () => setTocOpen(!tocOpen));
  tocBackdrop.addEventListener('click', () => setTocOpen(false));
}
