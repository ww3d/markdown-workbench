// Enter and Shift+Enter inside a table (D2, E1-E10): new rows, the delimiter row
// for a typed header, ending the table, and a line break inside a cell. Every
// branch aligns the table in the same edit - one undo step.

const vscode = require('vscode');
const { findTable, pipeHeaderAt } = require('./detect');
const { cellIndexAt } = require('./row');
const { toGrid } = require('./format');
const { freshCells, insertRow } = require('./grid-ops');
const { renderGrid, gridOps, applyOps, placeInCell } = require('./apply');
const { tablesConfig } = require('./config');

// True when the cursor sits in front of the first cell: in the prefix or on the
// leading pipe, or - in a borderless row - before the first cell's content.
function beforeFirstCell(row, ch) {
  if (row.lead || !row.cells.length) return cellIndexAt(row, ch) === -1;
  return ch <= row.cells[0].cStart;
}

// Insert a row at grid index `at`, align, and put the cursor into cell `col`.
async function insertAndPlace(
  editor,
  table,
  at,
  sourceCells,
  col,
  cfg,
  editFn,
) {
  const doc = editor.document;
  const grid = toGrid(table);
  const anchor = table.rows[Math.max(0, at - 1)];
  const cells = freshCells(
    sourceCells,
    table.columnCount,
    cfg.continueCheckboxes,
  );
  const next = insertRow(grid, at, { prefix: anchor.prefix, cells });
  const lines = renderGrid(next, cfg, (l) => doc.lineAt(l).text);
  await applyOps(editor, gridOps(doc, next, lines), editFn);
  placeInCell(editor, table.start + at, col);
  return true;
}

// E4: a typed header without a delimiter row gets one plus an empty body row.
async function completeHeader(editor, head, cfg, editFn) {
  const doc = editor.document;
  const n = head.cells.length;
  if (!n) return false;
  const grid = {
    start: head.line,
    aligns: Array(n).fill(''),
    lead: head.lead,
    trail: head.trail,
    rows: [
      {
        prefix: head.prefix,
        cells: head.cells.map((c) => c.text),
        line: head.line,
        dirty: true,
      },
      { prefix: head.prefix, cells: [], sep: true },
      { prefix: head.prefix, cells: Array(n).fill('') },
    ],
  };
  const lines = renderGrid(grid, cfg, (l) => doc.lineAt(l).text);
  await applyOps(editor, gridOps(doc, grid, lines), editFn);
  placeInCell(editor, head.line + 2, 0);
  return true;
}

// E6: the last, empty body row becomes a blank line (its prefix kept); the rest
// of the table is aligned in the same edit.
async function endTable(editor, table, cfg, editFn) {
  const doc = editor.document;
  const last = table.rows.at(-1);
  const grid = toGrid(table);
  grid.rows.pop();
  const ops = gridOps(
    doc,
    grid,
    renderGrid(grid, cfg, (l) => doc.lineAt(l).text),
  );
  ops.push({
    line: last.line,
    start: 0,
    end: last.text.length,
    text: last.prefix,
  });
  await applyOps(editor, ops, editFn);
  const caret = new vscode.Selection(
    last.line,
    last.prefix.length,
    last.line,
    last.prefix.length,
  );
  editor.selection = caret;
  editor.selections = [caret];
  return true;
}

/**
 * Enter in a table. Returns false when no table branch applies (the caller runs
 * its own Enter): several cursors or a selection (E9), code block or
 * frontmatter (E10), no table, `tables.enabled` off.
 * @param {vscode.TextEditor} editor
 * @param {Function} editFn edit runner (one undo step)
 * @returns {Promise<boolean>}
 */
async function tableEnter(editor, editFn) {
  const cfg = tablesConfig();
  if (!cfg.enabled) return false;
  if (editor.selections.length !== 1 || !editor.selection.isEmpty) return false;
  const doc = editor.document;
  const pos = editor.selection.active;
  const table = findTable(doc, pos.line);
  if (!table) {
    const head = pipeHeaderAt(doc, pos.line);
    if (!head || pos.character <= head.prefix.length) return false;
    return completeHeader(editor, head, cfg, editFn);
  }
  const r = pos.line - table.start;
  const row = table.rows[r];
  const lastRow = table.rows.length - 1;
  if (r === 0 && beforeFirstCell(row, pos.character)) return false;
  if (r <= 1) return insertAndPlace(editor, table, 2, null, 0, cfg, editFn); // E3, E5
  if (beforeFirstCell(row, pos.character))
    return insertAndPlace(editor, table, r, null, 0, cfg, editFn); // E2
  const empty = row.cells.every((c) => c.text === '');
  if (r === lastRow && empty) return endTable(editor, table, cfg, editFn); // E6
  const cells = row.cells.map((c) => c.text);
  if (cfg.enterBehavior === 'nextRowSameColumn') {
    const col = Math.max(0, cellIndexAt(row, pos.character));
    if (r < lastRow) {
      const grid = toGrid(table);
      const lines = renderGrid(grid, cfg, (l) => doc.lineAt(l).text);
      await applyOps(editor, gridOps(doc, grid, lines), editFn);
      placeInCell(editor, pos.line + 1, col);
      return true;
    }
    return insertAndPlace(editor, table, r + 1, cells, col, cfg, editFn);
  }
  return insertAndPlace(editor, table, r + 1, cells, 0, cfg, editFn); // E1, E7
}

/**
 * Shift+Enter in a table cell: insert `tables.cellLineBreak` (default `<br>`) at
 * the cursor and align. False when not in a body or header cell, or the setting
 * is empty - the caller then runs its own Shift+Enter.
 * @param {vscode.TextEditor} editor
 * @param {Function} editFn
 * @returns {Promise<boolean>}
 */
async function tableShiftEnter(editor, editFn) {
  const cfg = tablesConfig();
  if (!cfg.enabled || !cfg.cellLineBreak) return false;
  if (editor.selections.length !== 1 || !editor.selection.isEmpty) return false;
  const doc = editor.document;
  const pos = editor.selection.active;
  const table = findTable(doc, pos.line);
  if (!table) return false;
  const r = pos.line - table.start;
  const row = table.rows[r];
  const col = cellIndexAt(row, pos.character);
  if (r === 1 || col < 0 || col >= row.cells.length) return false;
  if (!cfg.autoAlign) {
    const br = cfg.cellLineBreak;
    await editFn(editor, (b) => b.insert(pos, br));
    const c = pos.character + br.length;
    const caret = new vscode.Selection(pos.line, c, pos.line, c);
    editor.selection = caret;
    editor.selections = [caret];
    return true;
  }
  const cell = row.cells[col];
  const at = Math.min(Math.max(pos.character, cell.cStart), cell.cEnd);
  const offset = at - cell.cStart + cfg.cellLineBreak.length;
  const grid = toGrid(table);
  const target = grid.rows[r];
  target.cells[col] =
    cell.text.slice(0, at - cell.cStart) +
    cfg.cellLineBreak +
    cell.text.slice(at - cell.cStart);
  target.dirty = true;
  const lines = renderGrid(grid, cfg, (l) => doc.lineAt(l).text);
  await applyOps(editor, gridOps(doc, grid, lines), editFn);
  placeInCell(editor, pos.line, col);
  const start = editor.selection.start.character;
  const caret = new vscode.Selection(
    pos.line,
    start + offset,
    pos.line,
    start + offset,
  );
  editor.selection = caret;
  editor.selections = [caret];
  return true;
}

module.exports = { tableEnter, tableShiftEnter };
