// The rendered-document container and the page-level helpers every part of the
// webview shares: element lookup in the skeleton, document coordinates, and the
// element an event targeted.

import './page.css';
import './codicon.css';
import './hint.css';

/**
 * The skeleton element with this id (getWebviewHtml writes all of them). A missing
 * one is a broken skeleton, so it fails at load, by name.
 */
export function byId(id: string): HTMLElement {
  const el = document.getElementById(id);
  if (!el) throw new Error(`webview skeleton lacks #${id}`);
  return el;
}

/** The container the rendered markdown lives in. */
export const content = byId('content');

/** An element's top edge in document coordinates (viewport top + scroll offset). */
export function absTop(el: Element): number {
  return el.getBoundingClientRect().top + window.scrollY;
}

/**
 * Whether a value is an element to query from. Duck-typed on `closest`, not
 * `instanceof Element`: an event target may be a text node or the document.
 */
export function isElement(value: unknown): value is Element {
  return (
    typeof value === 'object' &&
    value !== null &&
    'closest' in value &&
    typeof value.closest === 'function'
  );
}

/** The element an event targeted, or null for a non-element target. */
export function eventElement(e: Event): Element | null {
  return isElement(e.target) ? e.target : null;
}
