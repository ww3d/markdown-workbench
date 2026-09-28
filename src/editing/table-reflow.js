// --- Tables: reflow (distribute / consolidate) ------------------------------------
// Both commands run on the GFM table model (src/tables, docs/DECISIONS.md #48) and
// align unconditionally - tables.maxAlignedWidth only steers the automatic
// alignment of Enter/Tab.
const vscode = require('vscode');
const { findTable, linesDoc } = require('../tables/detect');
const { parseRow } = require('../tables/row');
const { toGrid, formatGrid } = require('../tables/format');
const { gridOps, applyOps } = require('../tables/apply');
const { tablesConfig } = require('../tables/config');

/**
 * Cell texts of one table row, split like the preview (an escaped `\|` stays
 * content).
 * @param {string} line
 * @returns {string[]}
 */
function splitRow(line) {
  return parseRow(line).cells.map((c) => c.text);
}

/**
 * Reflow table lines (the table starting at the first line; lines after it are
 * returned unchanged, and non-table input as is).
 * @param {string[]} lines
 * @param {'distribute' | 'consolidate'} mode
 * @returns {string[]}
 */
function reflowTable(lines, mode) {
  const table = findTable(linesDoc(lines), 0);
  if (!table) return lines.slice();
  const { ambiguousWide } = tablesConfig();
  const out = formatGrid(toGrid(table), { mode, ambiguousWide }).lines;
  return out.concat(lines.slice(table.end + 1));
}

async function reflowTableCommand(mode) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;
  const table = findTable(doc, editor.selection.start.line);
  if (!table) {
    vscode.window.showInformationMessage(
      'Place the cursor inside a markdown table.',
    );
    return;
  }
  const grid = toGrid(table);
  const { ambiguousWide } = tablesConfig();
  const lines = formatGrid(grid, { mode, ambiguousWide }).lines;
  await applyOps(editor, gridOps(doc, grid, lines), (e, cb) => e.edit(cb));
}

module.exports = {
  splitRow,
  reflowTable,
  reflowTableCommand,
};
