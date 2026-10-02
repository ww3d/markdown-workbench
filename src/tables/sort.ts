// Number recognition and body-row sorting of a table grid (K3, K4). Pure.

import type { Grid } from './format.ts';

// Grouped thousands (1,234 / 1 234 / 1'234) with an optional dot decimal, or a
// plain number with a dot or comma decimal; optional sign and trailing percent.
const GROUPED_RE = /^([+\-−]?)(\d{1,3}(?:[,'   ]\d{3})+)(\.\d+)?\s?%?$/u;
const PLAIN_RE = /^([+\-−]?)(\d+)(?:[.,](\d+))?\s?%?$/u;

/**
 * The numeric value of a cell, or null when it is no number.
 */
function parseNumber(text: string): number | null {
  const t = text.trim();
  const grouped = GROUPED_RE.exec(t);
  if (grouped) {
    const v = Number(
      (grouped[2] ?? '').replace(/[^\d]/g, '') + (grouped[3] || ''),
    );
    return grouped[1] && grouped[1] !== '+' ? -v : v;
  }
  const plain = PLAIN_RE.exec(t);
  if (!plain) return null;
  const v = Number(`${plain[2]}.${plain[3] || '0'}`);
  return plain[1] && plain[1] !== '+' ? -v : v;
}

const collator = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: 'base',
});

// Order two cells: numbers before text, numbers by value, text by a numeric-aware
// collation. Empty cells are handled by the caller (always last).
function compareCells(a: string, b: string): number {
  const na = parseNumber(a),
    nb = parseNumber(b);
  if (na !== null && nb !== null) return na - nb;
  if (na !== null) return -1;
  if (nb !== null) return 1;
  return collator.compare(a, b);
}

/**
 * Sort the body rows of a grid by column `col`. Stable; empty cells last in both
 * directions. Rows keep their document positions: row `k` of the result replaces
 * the line body row `k` had, so the edit is a pure reorder. Returns the input
 * grid when the order does not change.
 */
function sortBody(grid: Grid, col: number, descending: boolean): Grid {
  const head = grid.rows.slice(0, 2);
  const body = grid.rows.slice(2);
  const keyed = body.map((row, index) => ({
    row,
    index,
    key: (row.cells[col] ?? '').trim(),
  }));
  keyed.sort((x, y) => {
    if (!x.key || !y.key)
      return Number(!x.key) - Number(!y.key) || x.index - y.index;
    const c = compareCells(x.key, y.key);
    return (descending ? -c : c) || x.index - y.index;
  });
  if (keyed.every((k, i) => k.index === i)) return grid;
  const rows = head.concat(
    keyed.map((k, i) => ({
      ...k.row,
      prefix: body[i]?.prefix ?? k.row.prefix,
      line: body[i]?.line,
    })),
  );
  return { ...grid, rows };
}

export { parseNumber, sortBody };
