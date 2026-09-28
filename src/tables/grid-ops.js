// Structural grid edits: new rows (Enter/Tab), column insert/delete/move and the
// delimiter row a typed header gets. Each returns a new grid; pure, no vscode.

const CHECKBOX_CELL_RE = /^\[( |x|X)\]$/;

/**
 * Cells of a fresh row: empty, except `[ ]` in every column whose cell in the
 * source row is only a checkbox (K5, with `continueCheckboxes`).
 * @param {string[] | undefined} source the row the new one continues
 * @param {number} count column count
 * @param {boolean} continueCheckboxes
 * @returns {string[]}
 */
function freshCells(source, count, continueCheckboxes) {
  return Array.from({ length: count }, (_, i) =>
    continueCheckboxes && source && CHECKBOX_CELL_RE.test(source[i] ?? '')
      ? '[ ]'
      : '',
  );
}

/**
 * Insert a row at grid index `at` (it lands before the row now there).
 * @param {import('./format.js').Grid} grid
 * @param {number} at
 * @param {{ prefix: string, cells: string[] }} row
 */
function insertRow(grid, at, row) {
  const rows = grid.rows.slice();
  rows.splice(at, 0, { prefix: row.prefix, cells: row.cells });
  return { ...grid, rows };
}

/** Apply `fn(cells, row)` to every row's cells (delimiter row included). */
function mapCells(grid, fn) {
  return {
    ...grid,
    rows: grid.rows.map((r) => ({ ...r, cells: fn(r.cells.slice(), r) })),
  };
}

// Pad a cell list to at least `n` cells.
function padded(cells, n) {
  while (cells.length < n) cells.push('');
  return cells;
}

/**
 * Insert an empty column at index `at` (0..columnCount).
 * @param {import('./format.js').Grid} grid
 * @param {number} at
 */
function insertColumn(grid, at) {
  const n = grid.aligns.length;
  const aligns = grid.aligns.slice();
  aligns.splice(at, 0, '');
  return {
    ...mapCells(grid, (cells, r) => {
      padded(cells, n).splice(at, 0, r.sep ? '---' : '');
      return cells;
    }),
    aligns,
  };
}

/**
 * Delete column `at`; null when it is the only one (a table needs a column).
 * @param {import('./format.js').Grid} grid
 * @param {number} at
 */
function deleteColumn(grid, at) {
  const n = grid.aligns.length;
  if (n < 2) return null;
  const aligns = grid.aligns.filter((_, i) => i !== at);
  return {
    ...mapCells(grid, (cells) => {
      padded(cells, n).splice(at, 1);
      return cells;
    }),
    aligns,
  };
}

/**
 * Swap column `at` with its neighbor in direction `dir` (-1 left, +1 right);
 * null at the table edge.
 * @param {import('./format.js').Grid} grid
 * @param {number} at
 * @param {number} dir
 */
function moveColumn(grid, at, dir) {
  const n = grid.aligns.length;
  const to = at + dir;
  if (to < 0 || to >= n) return null;
  const swap = (arr) => {
    [arr[at], arr[to]] = [arr[to], arr[at]];
    return arr;
  };
  return {
    ...mapCells(grid, (cells) => swap(padded(cells, n))),
    aligns: swap(grid.aligns.slice()),
  };
}

/**
 * Widen the header (and delimiter row) to the widest row, so cells beyond the
 * header become visible (X3 quick fix).
 * @param {import('./format.js').Grid} grid
 */
function widenHeader(grid) {
  const width = Math.max(...grid.rows.map((r) => r.cells.length));
  let g = grid;
  while (g.aligns.length < width) {
    const n = g.aligns.length;
    g = {
      ...g,
      aligns: [...g.aligns, ''],
      rows: g.rows.map((r, i) =>
        i < 2
          ? {
              ...r,
              cells: padded(r.cells.slice(), n).concat(i === 1 ? '---' : ''),
            }
          : r,
      ),
    };
  }
  return g;
}

module.exports = {
  freshCells,
  insertRow,
  insertColumn,
  deleteColumn,
  moveColumn,
  widenHeader,
};
