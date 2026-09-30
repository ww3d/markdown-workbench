// The table header sort button (docs/DECISIONS.md #49): a click asks the host to
// sort the table's source rows.

import { vscodeApi } from '../host.ts';

/**
 * Source document version of the last render: a sortTable message carries it so
 * the host can drop a click made on an outdated view (docs/DECISIONS.md #49).
 */
export let docVersion: number | undefined;

/** Record the document version a render came from. */
export function setDocVersion(version: number | undefined): void {
  docVersion = version;
}

// The last sort sent from a header button; a second click on the same column
// sorts it the other way round.
let lastSort: { line: number; col: number; dir: 'asc' | 'desc' } | null = null;

/** Ask the host to sort the table's source rows by the button's column. */
export function postSort(btn: HTMLElement): void {
  const line = Number(btn.closest<HTMLElement>('table')?.dataset.line);
  const col = Number(btn.dataset.col);
  const again = lastSort?.line === line && lastSort.col === col;
  const dir = again && lastSort?.dir === 'asc' ? 'desc' : 'asc';
  lastSort = { line, col, dir };
  vscodeApi().postMessage({
    type: 'sortTable',
    line,
    col,
    dir,
    version: docVersion,
  });
}
