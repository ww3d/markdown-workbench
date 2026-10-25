// Number recognition and body-row sorting of a table grid (K3, K4). Pure.

// Grouped thousands (1,234 / 1 234 / 1'234) with an optional dot decimal, or a
// plain number with a dot or comma decimal; optional sign and trailing percent.
const GROUPED_RE = /^([+\-−]?)(\d{1,3}(?:[,'   ]\d{3})+)(\.\d+)?\s?%?$/u;
const PLAIN_RE = /^([+\-−]?)(\d+)(?:[.,](\d+))?\s?%?$/u;

/**
 * The numeric value of a cell, or null when it is no number.
 * @param {string} text
 * @returns {number | null}
 */
function parseNumber(text) {
  const t = text.trim();
  let m = GROUPED_RE.exec(t);
  if (m) {
    const v = Number(m[2].replace(/[^\d]/g, '') + (m[3] || ''));
    return m[1] && m[1] !== '+' ? -v : v;
  }
  m = PLAIN_RE.exec(t);
  if (!m) return null;
  const v = Number(`${m[2]}.${m[3] || '0'}`);
  return m[1] && m[1] !== '+' ? -v : v;
}

const collator = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: 'base',
});

// Order two cells: numbers before text, numbers by value, text by a numeric-aware
// collation. Empty cells are handled by the caller (always last).
function compareCells(a, b) {
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
 * @param {import('./format.js').Grid} grid
 * @param {number} col
 * @param {boolean} descending
 */
function sortBody(grid, col, descending) {
  const head = grid.rows.slice(0, 2);
  const body = grid.rows.slice(2);
  const keyed = body.map((row, index) => ({
    row,
    index,
    key: (row.cells[col] ?? '').trim(),
  }));
  keyed.sort((x, y) => {
    if (!x.key || !y.key) return !x.key - !y.key || x.index - y.index;
    const c = compareCells(x.key, y.key);
    return (descending ? -c : c) || x.index - y.index;
  });
  if (keyed.every((k, i) => k.index === i)) return grid;
  const rows = head.concat(
    keyed.map((k, i) => ({
      ...k.row,
      prefix: body[i].prefix,
      line: body[i].line,
    })),
  );
  return { ...grid, rows };
}

module.exports = { parseNumber, sortBody };
