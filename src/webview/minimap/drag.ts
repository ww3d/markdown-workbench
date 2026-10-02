// Minimap navigation: a click on the rail centers that position, a grabbed slider
// drags the view relative to the grab point (like the editor minimap).

import { mapOffset, mapSy, minimap } from './minimap.ts';

/** Scroll so the document position under rail `clientY` sits at the viewport center. */
export function minimapNavigate(clientY: number): void {
  const y = clientY - minimap.getBoundingClientRect().top;
  const docY = (y - mapOffset) / mapSy;
  window.scrollTo(window.scrollX, docY - window.innerHeight / 2);
}

// Geometric slider hit test from the live mapping (same math as
// updateMinimap), NOT from CSS: with showSlider 'mouseover' the slider is
// only visually hidden and must stay grabbable.
function sliderHit(railY: number): number | null {
  const top = window.scrollY * mapSy + mapOffset;
  const height = Math.max(12, window.innerHeight * mapSy);
  return railY >= top && railY <= top + height ? railY - top : null;
}

// Rail-px offset between the pointer and the slider top while the slider is
// grabbed; null while a rail (centering) drag is active.
let grabOffset: number | null = null;

/** Register the rail's pointer handlers (grab, drag, release). */
export function installMinimapDrag(): void {
  minimap.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    minimap.classList.add('dragging');
    minimap.setPointerCapture(e.pointerId);
    // Like the editor minimap: grabbing the slider itself must not jump - the
    // viewport moves only relative to the grab point. Clicks on the rail
    // outside the slider keep the centering jump (and keep centering while
    // held).
    grabOffset = sliderHit(e.clientY - minimap.getBoundingClientRect().top);
    if (grabOffset === null) minimapNavigate(e.clientY);
  });
  minimap.addEventListener('pointermove', (e) => {
    if (!minimap.classList.contains('dragging')) return;
    if (grabOffset === null) {
      minimapNavigate(e.clientY);
      return;
    }
    const sliderTop =
      e.clientY - minimap.getBoundingClientRect().top - grabOffset;
    window.scrollTo(window.scrollX, (sliderTop - mapOffset) / mapSy);
  });
  minimap.addEventListener('pointerup', (e) => {
    minimap.classList.remove('dragging');
    minimap.releasePointerCapture(e.pointerId);
    grabOffset = null;
  });
}
