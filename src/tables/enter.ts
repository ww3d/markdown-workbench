// Enter and Shift+Enter inside a table (D2, E1-E10): new rows, the delimiter row
// for a typed header, ending the table, and a line break inside a cell. Every
// branch aligns the table in the same edit - one undo step.

import * as vscode from 'vscode';
import { findTable, pipeHeaderAt, startsTableAt } from './detect.ts';
import type { Table, TableRow } from './detect.ts';
import { cellIndexAt, continuationPrefix, prefixLength } from './row.ts';
import { toGrid } from './format.ts';
import type { Grid } from './format.ts';
import type { Align } from './row.ts';
import { freshCells, insertRow } from './grid-ops.ts';
import { renderGrid, gridOps, applyOps, placeInCell } from './apply.ts';
import type { EditFn } from './apply.ts';
import { tablesConfig } from './config.ts';
import type { TablesConfig } from './config.ts';

// True when the cursor sits in front of the first cell: in the prefix or on the
// leading pipe, or - in a borderless row - before the first cell's content.
function beforeFirstCell(row: TableRow, ch: number): boolean {
  const first = row.cells[0];
  if (row.lead || !first) return cellIndexAt(row, ch) === -1;
  return ch <= first.cStart;
}

// Insert a row at grid index `at`, align, and put the cursor into cell `col`.
async function insertAndPlace(
  editor: vscode.TextEditor,
  table: Table,
  at: number,
  sourceCells: readonly string[] | null,
  col: number,
  cfg: TablesConfig,
  editFn: EditFn,
): Promise<boolean> {
  const doc = editor.document;
  const grid = toGrid(table);
  const anchor = table.rows[Math.max(0, at - 1)];
  if (!anchor) return false;
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

// The document's lines with line `at` replaced by `lines`.
function withLines(
  doc: vscode.TextDocument,
  at: number,
  lines: readonly string[],
): string[] {
  const out: string[] = [];
  for (let l = 0; l < doc.lineCount; l++)
    if (l === at) out.push(...lines.join('\n').split('\n'));
    else out.push(doc.lineAt(l).text);
  return out;
}

// E4: a typed header without a delimiter row gets one plus an empty body row -
// only where the preview then shows a table (a lazy paragraph line, say, would
// stay text); otherwise the normal Enter runs.
async function completeHeader(
  editor: vscode.TextEditor,
  head: TableRow,
  cfg: TablesConfig,
  editFn: EditFn,
): Promise<boolean> {
  const doc = editor.document;
  const n = head.cells.length;
  if (!n) return false;
  // Below a header on a list item's line the rows stay in the item.
  const cont = continuationPrefix(head.prefix);
  const grid: Grid = {
    start: head.line,
    aligns: Array<Align>(n).fill(''),
    lead: head.lead,
    trail: head.trail,
    rows: [
      {
        prefix: head.prefix,
        cells: head.cells.map((c) => c.text),
        line: head.line,
        dirty: true,
      },
      { prefix: cont, cells: [], sep: true },
      { prefix: cont, cells: Array<string>(n).fill('') },
    ],
  };
  const lines = renderGrid(grid, cfg, (l) => doc.lineAt(l).text);
  // Text right below would become a table row; a blank line ends the table.
  const next = head.line + 1;
  const below = next < doc.lineCount ? doc.lineAt(next).text : '';
  if (below.replace(/[\s>]/g, '') !== '')
    lines[2] = `${lines[2] ?? ''}\n${cont.trimEnd()}`;
  if (!startsTableAt(withLines(doc, head.line, lines), head.line)) return false;
  await applyOps(editor, gridOps(doc, grid, lines), editFn);
  placeInCell(editor, head.line + 2, 0);
  return true;
}

// E6: the last, empty body row becomes a blank line (its prefix kept); the rest
// of the table is aligned in the same edit.
async function endTable(
  editor: vscode.TextEditor,
  table: Table,
  cfg: TablesConfig,
  editFn: EditFn,
): Promise<boolean> {
  const doc = editor.document;
  const last = table.rows.at(-1);
  if (!last) return false;
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

// Enter inside the header's quote prefix: a plain split would move the header out
// of the quote; a prefixed blank line above keeps the table whole.
async function enterInHeaderPrefix(
  editor: vscode.TextEditor,
  row: TableRow,
  pos: vscode.Position,
  editFn: EditFn,
): Promise<boolean> {
  const quote = row.text.slice(0, prefixLength(row.text)).trimEnd();
  if (pos.character === 0 || !quote.includes('>')) return false;
  await editFn(editor, (b) =>
    b.insert(new vscode.Position(pos.line, 0), `${quote}\n`),
  );
  const caret = new vscode.Selection(
    pos.line + 1,
    pos.character,
    pos.line + 1,
    pos.character,
  );
  editor.selection = caret;
  editor.selections = [caret];
  return true;
}

/**
 * Enter in a table. Returns false when no table branch applies (the caller runs
 * its own Enter): several cursors or a selection (E9), code block or
 * frontmatter (E10), no table, `tables.enabled` off.
 * @param editFn edit runner (one undo step)
 */
async function tableEnter(
  editor: vscode.TextEditor,
  editFn: EditFn,
): Promise<boolean> {
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
  if (!row) return false;
  const lastRow = table.rows.length - 1;
  if (r === 0 && beforeFirstCell(row, pos.character))
    return enterInHeaderPrefix(editor, row, pos, editFn);
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
 * @param editFn edit runner (one undo step)
 */
async function tableShiftEnter(
  editor: vscode.TextEditor,
  editFn: EditFn,
): Promise<boolean> {
  const cfg = tablesConfig();
  if (!cfg.enabled || !cfg.cellLineBreak) return false;
  if (editor.selections.length !== 1 || !editor.selection.isEmpty) return false;
  const doc = editor.document;
  const pos = editor.selection.active;
  const table = findTable(doc, pos.line);
  if (!table) return false;
  const r = pos.line - table.start;
  const row = table.rows[r];
  if (!row) return false;
  const col = cellIndexAt(row, pos.character);
  const cell = row.cells[col];
  if (r === 1 || col < 0 || !cell) return false;
  if (!cfg.autoAlign) {
    const br = cfg.cellLineBreak;
    await editFn(editor, (b) => b.insert(pos, br));
    const c = pos.character + br.length;
    const caret = new vscode.Selection(pos.line, c, pos.line, c);
    editor.selection = caret;
    editor.selections = [caret];
    return true;
  }
  const at = Math.min(Math.max(pos.character, cell.cStart), cell.cEnd);
  const offset = at - cell.cStart + cfg.cellLineBreak.length;
  const grid = toGrid(table);
  const target = grid.rows[r];
  if (!target) return false;
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

export { tableEnter, tableShiftEnter };
