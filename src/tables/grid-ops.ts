// Structural grid edits: new rows (Enter/Tab), column insert/delete/move and the
// delimiter row a typed header gets. Each returns a new grid; pure, no vscode.

import type { Grid, GridRow } from './format.ts';

const CHECKBOX_CELL_RE = /^\[( |x|X)\]$/;

/**
 * Cells of a fresh row: empty, except `[ ]` in every column whose cell in the
 * source row is only a checkbox (K5, with `continueCheckboxes`).
 * @param source the row the new one continues
 * @param count column count
 */
function freshCells(
  source: readonly string[] | null | undefined,
  count: number,
  continueCheckboxes: boolean,
): string[] {
  return Array.from({ length: count }, (_, i) =>
    continueCheckboxes && source && CHECKBOX_CELL_RE.test(source[i] ?? '')
      ? '[ ]'
      : '',
  );
}

/**
 * Insert a row at grid index `at` (it lands before the row now there).
 */
function insertRow(
  grid: Grid,
  at: number,
  row: { prefix: string; cells: string[] },
): Grid {
  const rows = grid.rows.slice();
  rows.splice(at, 0, { prefix: row.prefix, cells: row.cells });
  return { ...grid, rows };
}

/** Apply `fn(cells, row)` to every row's cells (delimiter row included). */
function mapCells(
  grid: Grid,
  fn: (cells: string[], row: GridRow) => string[],
): Grid {
  return {
    ...grid,
    rows: grid.rows.map((r) => ({ ...r, cells: fn(r.cells.slice(), r) })),
  };
}

// Pad a cell list to at least `n` cells.
function padded(cells: string[], n: number): string[] {
  while (cells.length < n) cells.push('');
  return cells;
}

/**
 * Insert an empty column at index `at` (0..columnCount).
 */
function insertColumn(grid: Grid, at: number): Grid {
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
 */
function deleteColumn(grid: Grid, at: number): Grid | null {
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
 */
function moveColumn(grid: Grid, at: number, dir: number): Grid | null {
  const n = grid.aligns.length;
  const to = at + dir;
  if (to < 0 || to >= n) return null;
  const swap = <T>(arr: T[]): T[] => {
    const a = arr[at];
    const b = arr[to];
    if (a === undefined || b === undefined) return arr;
    arr[at] = b;
    arr[to] = a;
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
 */
function widenHeader(grid: Grid): Grid {
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

export {
  freshCells,
  insertRow,
  insertColumn,
  deleteColumn,
  moveColumn,
  widenHeader,
};
