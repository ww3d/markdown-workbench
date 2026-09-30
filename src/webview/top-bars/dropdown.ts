// The breadcrumb's sibling picker: a segment click navigates and opens the picker
// with the headings at the same level under the same parent.

import { navigateToHash, scrollWindowTo } from '../anchors/anchors.ts';
import { byId, eventElement } from '../page/content.ts';
import type { Heading } from '../scroll-spy/spy.ts';
import { topBarsOffset } from './geometry.ts';
import { breadcrumb } from './links.ts';

const dropdown = byId('breadcrumb-dropdown');
/** Heading index the open sibling dropdown belongs to; -1 = closed. */
export let dropdownIdx = -1;
let lastHeadings: readonly Heading[] = []; // headings from the last scroll-spy emit (dropdown source)

/** Record the headings of the last top-bar rebuild, the picker's source. */
export function setDropdownHeadings(headings: readonly Heading[]): void {
  lastHeadings = headings;
}

/**
 * Sibling headings of `index`: the headings that share its parent and level, in
 * document order (index itself included). Walking outward, a strictly shallower
 * heading is the parent boundary and ends the run; deeper headings (children of
 * a sibling) are skipped; equal-level headings are siblings. Handles level jumps
 * (an h4 with no h2/h3 above bounds on the nearest shallower heading) and the
 * single-child case (returns just [index]). Pure; unit-tested.
 */
export function siblingHeadings(
  levels: readonly number[],
  index: number,
): number[] {
  const level = levels[index];
  if (index < 0 || level === undefined) return [];
  const out = [index];
  for (let i = index - 1; i >= 0; i--) {
    const l: number = levels[i] ?? level;
    if (l < level) break;
    if (l === level) out.unshift(i);
  }
  for (let i = index + 1; i < levels.length; i++) {
    const l: number = levels[i] ?? level;
    if (l < level) break;
    if (l === level) out.push(i);
  }
  return out;
}

// Build and open the sibling picker for a breadcrumb segment (its heading and
// the headings at the same level under the same parent). Selection navigates;
// Escape and an outside click close it.
function openDropdown(idx: number): void {
  dropdown.innerHTML = '';
  const siblings = siblingHeadings(
    lastHeadings.map((h) => h.level),
    idx,
  );
  for (const s of siblings) {
    const heading = lastHeadings[s];
    if (!heading) continue;
    const option = document.createElement('a');
    option.className = `breadcrumb-option${s === idx ? ' breadcrumb-option-current' : ''}`;
    option.setAttribute('role', 'button'); // a control, not a native #id anchor (#44 follow-up)
    option.dataset.id = heading.id;
    option.dataset.idx = String(s);
    option.textContent = heading.text;
    option.tabIndex = -1;
    dropdown.appendChild(option);
  }
  dropdownIdx = idx;
  document.body.classList.add('breadcrumb-dropdown-open');
  positionDropdown(idx);
}

/** Place the open picker under its breadcrumb segment. */
export function positionDropdown(idx: number): void {
  const seg = breadcrumb.querySelector
    ? breadcrumb.querySelector(`.breadcrumb-seg[data-idx="${idx}"]`)
    : null;
  if (!seg) return;
  const rect = seg.getBoundingClientRect();
  dropdown.style.left = `${rect.left || 0}px`;
  dropdown.style.top = `${rect.bottom || topBarsOffset || 0}px`;
}

/** Close the sibling picker (a no-op while it is closed). */
export function closeDropdown(): void {
  if (dropdownIdx < 0) return;
  dropdownIdx = -1;
  dropdown.innerHTML = '';
  document.body.classList.remove('breadcrumb-dropdown-open');
}

/**
 * Register the breadcrumb and picker clicks: a segment scrolls to its heading
 * (smooth) and opens the sibling picker (the VS Code breadcrumb gesture: navigate
 * + pick); a picker option navigates to its sibling and closes the picker.
 */
export function installBreadcrumbClicks(): void {
  breadcrumb.addEventListener('click', (e) => {
    const seg = eventElement(e)?.closest<HTMLElement>('.breadcrumb-seg');
    if (!seg) return;
    e.preventDefault();
    // The root segment (index -1, above the first heading) scrolls to the top and
    // has no sibling picker; a heading segment navigates and opens the picker.
    if (seg.dataset.idx === '-1') {
      scrollWindowTo(0, true);
      closeDropdown();
      return;
    }
    navigateToHash(seg.dataset.id, true);
    openDropdown(Number(seg.dataset.idx));
  });

  dropdown.addEventListener('click', (e) => {
    const option = eventElement(e)?.closest<HTMLElement>('.breadcrumb-option');
    if (!option) return;
    e.preventDefault();
    navigateToHash(option.dataset.id, true);
    closeDropdown();
  });
}

/** Register the outside click: a click outside the breadcrumb and its picker closes it. */
export function installOutsideClose(): void {
  document.addEventListener('click', (e) => {
    if (dropdownIdx < 0) return;
    const t = eventElement(e);
    if (
      t &&
      (t.closest('#breadcrumb-dropdown') || t.closest('.breadcrumb-seg'))
    )
      return;
    closeDropdown();
  });
}
