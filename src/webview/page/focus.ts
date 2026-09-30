// Central click-focus suppression (docs/DECISIONS.md #40): a mouse click on any
// focusable element must not focus it. A newly focused element is scrolled into
// view by the browser/webview (measured: focusing an off-screen link scrolls the
// page), so every click on a link, a checkbox, or a navigation control jumped the
// page - "one level up" as the target slid under the fixed top bars. It also let
// Chromium re-class the focus as :focus-visible and re-show the ring. One
// delegated mousedown listener over every focusable target - content links and
// task/table checkboxes (`a`, `input`), the FAB (`button`) and the nav controls -
// calls preventDefault, which stops the focus (and its scroll) without touching
// the click: links still navigate, checkboxes still toggle. Keyboard focus is
// untouched (mousedown is pointer-only; :focus-visible still rings on Tab), and
// plain text (headings, paragraphs, table-cell prose) is not matched, so text
// selection stays normal.

import { eventElement } from './content.ts';

/** Every control a mouse click must not focus (one delegated selector). */
export const CLICK_FOCUS_TARGETS =
  'a, input, button, .breadcrumb-seg, .breadcrumb-option, .toc-link, .sticky-row, .mw-fold-toggle';

/** Register the delegated mousedown that suppresses the click focus. */
export function installFocusSuppression(): void {
  document.addEventListener('mousedown', (e) => {
    if (eventElement(e)?.closest?.(CLICK_FOCUS_TARGETS)) e.preventDefault();
  });
}
