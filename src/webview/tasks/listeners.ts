// The content's delegated click handler (fold controls, anchors, sort buttons,
// task and cell checkboxes) and the Escape key.

import { navigateToHash } from '../anchors/anchors.ts';
import { toggleFold } from '../folding/fold.ts';
import { content, eventElement } from '../page/content.ts';
import { postSort } from '../tables/sort.ts';
import { setTocOpen, tocOpen } from '../toc/layout.ts';
import { closeDropdown, dropdownIdx } from '../top-bars/dropdown.ts';
import { previewCfg } from './preview-config.ts';
import {
  applySelection,
  bareClickToggles,
  batchSelectListTask,
  postCellToggle,
  selection,
  toggleListTask,
} from './selection.ts';

/**
 * Register the Escape key: it closes an open breadcrumb dropdown or TOC overlay
 * first, otherwise it clears the task selection.
 */
export function installEscape(): void {
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    // An open breadcrumb dropdown or TOC overlay swallows Escape (close it
    // first); otherwise Escape clears the task selection as before.
    if (dropdownIdx >= 0) {
      closeDropdown();
      return;
    }
    if (tocOpen) {
      setTocOpen(false);
      return;
    }
    selection.clear();
    applySelection();
  });
}

// The text of the live selection a bare click would destroy ('' for none).
function selectionText(): string {
  return window.getSelection()?.toString() ?? '';
}

/** Register the delegated click handler: the innermost task row wins (nested tasks bubble). */
export function installContentClick(): void {
  content.addEventListener('click', (e) => {
    const target = eventElement(e);
    if (!target) return;
    // A click on a heading's fold control toggles that section (folds the rendered
    // content), synced with the sticky-row twistie (#44 P2). Handled before the
    // anchor/task logic so it never navigates or toggles a task.
    const foldToggle = target.closest<HTMLElement>('.mw-fold-toggle');
    if (foldToggle) {
      e.preventDefault();
      e.stopPropagation();
      toggleFold(foldToggle.dataset.foldId);
      return;
    }
    // Internal anchors are converted to buttons at render (convertInternalAnchors):
    // .mw-anchor with the id in data-id and no href. So navigateToHash - scoped to
    // #content, CSS.escaped, collision-safe - is the SOLE scroll. As real <a href>
    // they also triggered the webview's native #id jump, a second scroll to a
    // rounding-different spot that shifted the whole view 2-4px once the bars gave
    // headings a scroll-margin (#44). The scroll listener still reports the new
    // position so the source editor follows. Cross-file (./other.md#x) and external
    // (http[s]://) links keep their href and the browser default.
    const link = target.closest<HTMLElement>('.mw-anchor'); // not the task shift-range `anchor`
    if (link) {
      e.preventDefault();
      navigateToHash(link.dataset.id, false); // instant; a missing target is a no-op
      return;
    }
    if (target.closest('a')) return; // let links work normally

    // Sort button in a table header (src/render/parser.ts): sort the source rows
    // by this column, ascending first, descending on a repeated click.
    const sortBtn = target.closest<HTMLElement>('.mw-sort');
    if (sortBtn) {
      e.preventDefault();
      if (previewCfg.previewSort) postSort(sortBtn);
      return;
    }

    // Direct click on a table cell checkbox: toggles always, ungated.
    const cell = target.closest<HTMLElement>('input.cell-task');
    if (cell) {
      e.preventDefault();
      postCellToggle(cell);
      return;
    }

    // Direct click on a list task checkbox: toggles always, ungated, and carries
    // the batch gestures (Shift/Ctrl) - the only place batch is triggered.
    const checkbox = target.closest('.task-row input[type=checkbox]');
    if (checkbox) {
      e.preventDefault();
      const li = checkbox.closest<HTMLElement>('li.task');
      if (li && !batchSelectListTask(li, e)) toggleListTask(li);
      return;
    }

    // Bare click in a table cell with exactly one checkbox (not on the input):
    // toggles only when no fresh text selection / multi-click is in play (gate
    // collapses to "always" when text selection is disabled).
    const td = target.closest('td');
    if (td) {
      const boxes = td.querySelectorAll<HTMLElement>('input.cell-task');
      const box = boxes[0];
      if (
        boxes.length === 1 &&
        box &&
        bareClickToggles(previewCfg.textSelection, selectionText(), e.detail)
      ) {
        e.preventDefault();
        postCellToggle(box);
      }
      return;
    }

    // Bare click in the task row label area (not the checkbox).
    const row = target.closest('.task-row');
    if (!row) return;
    const li = row.closest<HTMLElement>('li.task');
    if (!li) return;
    // In 'row' batch mode the label carries the batch gesture too (the price:
    // Shift in the label no longer extends a text selection). In 'checkbox' mode
    // the label only plain-toggles, gated so a text selection / multi-click wins.
    if (
      previewCfg.taskBatchSelect === 'row' &&
      (e.shiftKey || e.ctrlKey || e.metaKey)
    ) {
      e.preventDefault();
      if (!batchSelectListTask(li, e)) toggleListTask(li);
      return;
    }
    if (!bareClickToggles(previewCfg.textSelection, selectionText(), e.detail))
      return;
    e.preventDefault();
    toggleListTask(li);
  });
}
