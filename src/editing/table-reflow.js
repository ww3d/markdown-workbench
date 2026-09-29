// --- Tables: reflow (distribute / consolidate) ------------------------------------
// Both commands run on the GFM table model (src/tables, docs/DECISIONS.md #49) and
// align unconditionally - tables.maxAlignedWidth only steers the automatic
// alignment of Enter/Tab.
import * as vscode from 'vscode';
import { findTable } from '../tables/detect.js';
import { toGrid, formatGrid, reflowTable as reflow } from '../tables/format.js';
import { gridOps, applyOps } from '../tables/apply.js';
import { tablesConfig } from '../tables/config.js';

/**
 * Reflow table lines (the table starting at the first line; lines after it are
 * returned unchanged, and non-table input as is).
 * @param {string[]} lines
 * @param {'distribute' | 'consolidate'} mode
 * @returns {string[]}
 */
function reflowTable(lines, mode) {
  return reflow(lines, mode, tablesConfig().ambiguousWide);
}

// The tables a selection touches (a selection ending at column 0 stops on the
// line above), or the table at the cursor.
function tablesInSelection(doc, sel) {
  let last = sel.end.line;
  if (last > sel.start.line && sel.end.character === 0) last--;
  const tables = [];
  for (let l = sel.start.line; l <= last; l++) {
    const table = findTable(doc, l);
    if (!table) continue;
    tables.push(table);
    l = table.end;
  }
  return tables;
}

/**
 * Distribute or consolidate every table the selection touches (the one at the
 * cursor without a selection), in one undo step.
 * @param {'distribute' | 'consolidate'} mode
 */
async function reflowTableCommand(mode) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;
  const tables = tablesInSelection(doc, editor.selection);
  if (!tables.length) {
    vscode.window.showInformationMessage(
      'Place the cursor inside a markdown table.',
    );
    return;
  }
  const { ambiguousWide } = tablesConfig();
  const ops = tables.flatMap((table) => {
    const grid = toGrid(table);
    const lines = formatGrid(grid, { mode, ambiguousWide }).lines;
    return gridOps(doc, grid, lines);
  });
  await applyOps(editor, ops, (e, cb) => e.edit(cb));
}

export { reflowTable, reflowTableCommand };
