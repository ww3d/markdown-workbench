// Table commands on the column at the cursor: sort (K4, editor and preview) and
// insert/delete/move a column (X2). Each is one edit, one undo step.

import * as vscode from 'vscode';
import { findTable } from './detect.ts';
import { cellIndexAt } from './row.ts';
import { toGrid } from './format.ts';
import type { Grid, LineEdit } from './format.ts';
import { sortBody } from './sort.ts';
import { insertColumn, deleteColumn, moveColumn } from './grid-ops.ts';
import {
  renderGrid,
  gridOps,
  applyOps,
  opsToWorkspaceEdit,
  placeInCell,
} from './apply.ts';
import { tablesConfig } from './config.ts';
import type { SortTableMessage } from '../webview/protocol.ts';

const NO_TABLE = 'Place the cursor inside a markdown table.';

/**
 * Edits sorting the body rows of the table starting at `start` by column `col`;
 * empty when the order does not change or there is no such table.
 */
function sortOps(
  doc: vscode.TextDocument,
  start: number,
  col: number,
  descending: boolean,
): LineEdit[] {
  const table = findTable(doc, start);
  if (!table || table.start !== start || col < 0 || col >= table.columnCount)
    return [];
  const grid = toGrid(table);
  grid.rows.forEach((r, i) => {
    r.origin = i;
  });
  const sorted = sortBody(grid, col, descending);
  if (sorted === grid) return [];
  const cfg = tablesConfig();
  if (cfg.autoAlign)
    return gridOps(
      doc,
      sorted,
      renderGrid(sorted, cfg, (l) => doc.lineAt(l).text),
    );
  // Without auto-align every row keeps its source text, only moved.
  const lines: string[] = [];
  for (const [i, row] of sorted.rows.entries()) {
    const src = row.origin === undefined ? undefined : table.rows[row.origin];
    if (!src) return [];
    lines.push(
      i < 2 ? src.text : row.prefix + src.text.slice(src.prefix.length),
    );
  }
  return gridOps(doc, sorted, lines);
}

/** Editor command: sort the table at the cursor by the cursor's column. */
async function sortTableCommand(descending: boolean): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const pos = editor.selection.active;
  const table = findTable(editor.document, pos.line);
  const row = table?.rows[pos.line - table.start];
  if (!table || !row) {
    vscode.window.showInformationMessage(NO_TABLE);
    return;
  }
  const col = Math.max(0, cellIndexAt(row, pos.character));
  const ops = sortOps(editor.document, table.start, col, descending);
  await applyOps(editor, ops, (e, cb) => e.edit(cb));
}

/**
 * Host side of the preview's `sortTable` message (src/webview/protocol.ts): sort
 * the source table, one WorkspaceEdit (one undo step). A message for another
 * document version is stale - the preview showed an older text - and is ignored.
 * The message crosses from the webview untyped at runtime, so line and column are
 * checked again before they address the source.
 * @returns whether an edit was applied
 */
function sortTableMessage(
  doc: vscode.TextDocument,
  msg: SortTableMessage,
): boolean {
  if (msg.version !== doc.version) return false;
  const { line, col } = msg;
  if (typeof line !== 'number' || !Number.isInteger(line)) return false;
  if (typeof col !== 'number' || !Number.isInteger(col)) return false;
  if (!tablesConfig().previewSort) return false;
  const ops = sortOps(doc, line, col, msg.dir === 'desc');
  if (!ops.length) return false;
  vscode.workspace.applyEdit(opsToWorkspaceEdit(doc.uri, ops));
  return true;
}

// Run a column transform on the table at the cursor and keep the cursor in
// column `targetCol(c)`.
async function columnCommand(
  transform: (grid: Grid, c: number) => Grid | null,
  targetCol: (c: number, next: Grid) => number,
): Promise<void> {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;
  const pos = editor.selection.active;
  const table = findTable(doc, pos.line);
  const row = table?.rows[pos.line - table.start];
  if (!table || !row) {
    vscode.window.showInformationMessage(NO_TABLE);
    return;
  }
  const c = Math.max(0, cellIndexAt(row, pos.character));
  // A cell beyond the header is no column of the table (X3); acting on the
  // last header column instead would edit a column the cursor is not in.
  if (c >= table.columnCount) {
    vscode.window.showInformationMessage(
      'Place the cursor in a column of the table header.',
    );
    return;
  }
  const next = transform(toGrid(table), c);
  if (!next) return;
  const lines = renderGrid(
    next,
    tablesConfig(),
    (l) => doc.lineAt(l).text,
    true,
  );
  await applyOps(editor, gridOps(doc, next, lines), (e, cb) => e.edit(cb));
  placeInCell(editor, pos.line, targetCol(c, next));
}

/** The command ids and handlers of this module, for registration. */
const COMMANDS: Readonly<Record<string, () => Promise<void>>> = {
  'markdownWorkbench.sortTableAscending': () => sortTableCommand(false),
  'markdownWorkbench.sortTableDescending': () => sortTableCommand(true),
  'markdownWorkbench.insertColumnLeft': () =>
    columnCommand(
      (g, c) => insertColumn(g, c),
      (c) => c,
    ),
  'markdownWorkbench.insertColumnRight': () =>
    columnCommand(
      (g, c) => insertColumn(g, c + 1),
      (c) => c + 1,
    ),
  'markdownWorkbench.deleteColumn': () =>
    columnCommand(deleteColumn, (c, g) => Math.min(c, g.aligns.length - 1)),
  'markdownWorkbench.moveColumnLeft': () =>
    columnCommand(
      (g, c) => moveColumn(g, c, -1),
      (c) => c - 1,
    ),
  'markdownWorkbench.moveColumnRight': () =>
    columnCommand(
      (g, c) => moveColumn(g, c, 1),
      (c) => c + 1,
    ),
};

export { COMMANDS, sortOps, sortTableMessage };
