// Task toggles and the batch selection: which clicks may toggle, and the toggle
// messages posted to the host.

import './tasks.css';
import { vscodeApi } from '../host.ts';
import { content } from '../page/content.ts';

/** Source line numbers of the selected tasks (the batch selection). */
export const selection = new Set<number>();
let anchor: number | null = null; // last clicked task line (for shift-range)

function tasks(): HTMLElement[] {
  return [...content.querySelectorAll<HTMLElement>('li.task')];
}

/** Reflect the batch selection on the task rows (`.selected`). */
export function applySelection(): void {
  for (const li of tasks()) {
    li.classList.toggle('selected', selection.has(Number(li.dataset.line)));
  }
}

/**
 * A bare click (anywhere but directly on a checkbox input) may toggle a task
 * only when it produced no text selection and is not part of a multi-click -
 * so dragging out a selection or double-clicking to select a word reads as
 * text interaction, not a toggle. Pure function, unit-tested.
 */
export function canToggleFromBareClick(
  selectionText: string,
  detail: number,
): boolean {
  return selectionText === '' && detail === 1;
}

/**
 * Gate for bare (non-checkbox) clicks. With selection disabled there is no text
 * interaction to protect, so a bare click always toggles (pre-#25 behavior);
 * otherwise it defers to the selection/multi-click guard. Unit-tested.
 */
export function bareClickToggles(
  textSelectionEnabled: boolean,
  selectionText: string,
  detail: number,
): boolean {
  return !textSelectionEnabled
    ? true
    : canToggleFromBareClick(selectionText, detail);
}

/**
 * Ask the host to flip a table cell checkbox. At click time a clicked checkbox
 * input has already flipped its live .checked and preventDefault reverts it
 * afterwards - the rendered `checked` attribute is the reliable original state.
 */
export function postCellToggle(box: HTMLElement): void {
  vscodeApi().postMessage({
    type: 'toggleCell',
    line: Number(box.dataset.line),
    idx: Number(box.dataset.idx),
    checked: !box.hasAttribute('checked'),
  });
}

/**
 * Plain list toggle. If the clicked task is part of the selection, toggle the
 * whole selection in parallel to the clicked task's new state.
 */
export function toggleListTask(li: HTMLElement): void {
  const line = Number(li.dataset.line);
  anchor = line;
  const newState = li.dataset.checked !== 'true';
  const lines = selection.has(line) ? [...selection] : [line];
  vscodeApi().postMessage({ type: 'toggle', lines, checked: newState });
}

/**
 * Batch gestures live on the checkbox only (#15): Shift = range, Ctrl/Meta =
 * membership. Driving them from the label would collide with normal text
 * range-selection (Shift+click) once the body is selectable. Returns whether
 * the click was a batch gesture.
 */
export function batchSelectListTask(li: HTMLElement, e: MouseEvent): boolean {
  const line = Number(li.dataset.line);
  if (e.shiftKey && anchor !== null) {
    // Range select between anchor and clicked task (document order).
    const lines = tasks().map((t) => Number(t.dataset.line));
    const a = lines.indexOf(anchor),
      b = lines.indexOf(line);
    if (a !== -1 && b !== -1) {
      for (let i = Math.min(a, b); i <= Math.max(a, b); i++) {
        const l = lines[i];
        if (l !== undefined) selection.add(l);
      }
    }
    applySelection();
    return true;
  }
  if (e.ctrlKey || e.metaKey) {
    if (selection.has(line)) selection.delete(line);
    else selection.add(line);
    anchor = line;
    applySelection();
    return true;
  }
  return false;
}
