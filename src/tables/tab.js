// Tab / Shift+Tab inside a table (D3, T1-T8) and `|` + Tab to start one (K2).
// Tab moves to the next cell and selects its content, wrapping to the next row
// over the delimiter row and adding a row after the last cell; Shift+Tab moves
// back and never outdents. The table is aligned in the same edit.

const vscode = require('vscode');
const { findTable, pipeHeaderAt } = require('./detect');
const { cellIndexAt, contentEnd } = require('./row');
const { toGrid } = require('./format');
const { freshCells, insertRow } = require('./grid-ops');
const { renderGrid, gridOps, applyOps, placeInCell } = require('./apply');
const { tablesConfig } = require('./config');

// The next row index in direction `dir`, skipping the delimiter row; -1 past the edge.
function neighborRow(r, dir, last) {
  let t = r + dir;
  if (t === 1) t += dir;
  return t < 0 || t > last ? -1 : t;
}

// Where Tab (dir +1) or Shift+Tab (dir -1) goes from cell `c` of row `r`:
// { r, c } - `add` when a new row is needed - or null for "stay".
function tabTarget(r, c, n, last, dir) {
  if (dir > 0) {
    if (c < 0) return { r, c: 0 }; // T7
    if (c + 1 < n) return { r, c: c + 1 }; // T1
    const next = neighborRow(r, 1, last);
    return next < 0 ? { r: last + 1, c: 0, add: true } : { r: next, c: 0 }; // T3 / T2
  }
  if (c > 0) return { r, c: Math.min(c, n) - 1 };
  const prev = neighborRow(r, -1, last);
  return prev < 0 ? null : { r: prev, c: n - 1 }; // T4
}

// K2: `| Name` + Tab closes the cell and opens the next one.
async function extendPipeRow(editor, head, editFn) {
  const pos = editor.selection.active;
  const end = contentEnd(head.text);
  if (pos.character < end) return false;
  const closed = head.text[end - 1] === '|' && head.text[end - 2] !== '\\';
  const text = closed ? ' ' : ' | ';
  await editFn(editor, (b) =>
    b.replace(
      new vscode.Range(pos.line, end, pos.line, head.text.length),
      text,
    ),
  );
  const c = end + text.length;
  const caret = new vscode.Selection(pos.line, c, pos.line, c);
  editor.selection = caret;
  editor.selections = [caret];
  return true;
}

/**
 * Tab (`dir` +1) or Shift+Tab (-1) in a table. Returns false when no table
 * branch applies and the caller runs its list/indent Tab: several cursors, a
 * selection over several lines (T8), no table, `tables.enabled` off.
 * @param {vscode.TextEditor} editor
 * @param {number} dir
 * @param {Function} editFn edit runner (one undo step)
 * @returns {Promise<boolean>}
 */
async function tableTab(editor, dir, editFn) {
  const cfg = tablesConfig();
  if (!cfg.enabled || editor.selections.length !== 1) return false;
  const sel = editor.selection;
  if (sel.start.line !== sel.end.line) return false;
  const doc = editor.document;
  const table = findTable(doc, sel.start.line);
  if (!table) {
    if (dir < 0 || !cfg.createFromPipe || !sel.isEmpty) return false;
    const head = pipeHeaderAt(doc, sel.start.line);
    return head ? extendPipeRow(editor, head, editFn) : false;
  }
  const r0 = sel.start.line - table.start;
  const r = r0 === 1 ? 0 : r0; // the delimiter row navigates like the header
  const last = table.rows.length - 1;
  const c = cellIndexAt(table.rows[r0], sel.start.character);
  const target = tabTarget(r, c, table.columnCount, last, dir);
  if (!target) return true; // first header cell: Shift+Tab changes nothing
  let grid = toGrid(table);
  let dest = target;
  if (target.add && !cfg.tabAddsRow) dest = { r, c: Math.max(0, c) };
  else if (target.add) {
    const source = table.rows[last].cells.map((x) => x.text);
    const cells = freshCells(source, table.columnCount, cfg.continueCheckboxes);
    grid = insertRow(grid, last + 1, {
      prefix: table.rows[last].prefix,
      cells,
    });
  }
  const lines = renderGrid(grid, cfg, (l) => doc.lineAt(l).text);
  await applyOps(editor, gridOps(doc, grid, lines), editFn); // T5
  placeInCell(editor, table.start + dest.r, dest.c, {
    select: cfg.tabSelectsCell,
    at: 'end',
  });
  return true;
}

module.exports = { tableTab, tabTarget };
