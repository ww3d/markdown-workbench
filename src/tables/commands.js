// Table commands on the column at the cursor: sort (K4, editor and preview) and
// insert/delete/move a column (X2). Each is one edit, one undo step.

const vscode = require('vscode');
const { findTable } = require('./detect');
const { cellIndexAt } = require('./row');
const { toGrid } = require('./format');
const { sortBody } = require('./sort');
const { insertColumn, deleteColumn, moveColumn } = require('./grid-ops');
const {
  renderGrid,
  gridOps,
  applyOps,
  opsToWorkspaceEdit,
  placeInCell,
} = require('./apply');
const { tablesConfig } = require('./config');

const NO_TABLE = 'Place the cursor inside a markdown table.';

/**
 * Edits sorting the body rows of the table starting at `start` by column `col`;
 * empty when the order does not change or there is no such table.
 * @param {vscode.TextDocument} doc
 */
function sortOps(doc, start, col, descending) {
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
  const lines = cfg.autoAlign
    ? renderGrid(sorted, cfg, (l) => doc.lineAt(l).text)
    : sorted.rows.map((row, i) => {
        const src = table.rows[row.origin];
        return i < 2
          ? src.text
          : row.prefix + src.text.slice(src.prefix.length);
      });
  return gridOps(doc, sorted, lines);
}

/** Editor command: sort the table at the cursor by the cursor's column. */
async function sortTableCommand(descending) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const pos = editor.selection.active;
  const table = findTable(editor.document, pos.line);
  if (!table) {
    vscode.window.showInformationMessage(NO_TABLE);
    return;
  }
  const col = Math.max(
    0,
    cellIndexAt(table.rows[pos.line - table.start], pos.character),
  );
  const ops = sortOps(editor.document, table.start, col, descending);
  await applyOps(editor, ops, (e, cb) => e.edit(cb));
}

/**
 * Host side of the preview's `sortTable` message: sort the source table, one
 * WorkspaceEdit (one undo step). A message for another document version is
 * stale - the preview showed an older text - and is ignored.
 * @param {vscode.TextDocument} doc
 * @param {{ line: number, col: number, dir: string, version: number }} msg
 * @returns {boolean} whether an edit was applied
 */
function sortTableMessage(doc, msg) {
  if (msg.version !== doc.version) return false;
  if (!tablesConfig().previewSort) return false;
  const ops = sortOps(
    doc,
    Number(msg.line),
    Number(msg.col),
    msg.dir === 'desc',
  );
  if (!ops.length) return false;
  vscode.workspace.applyEdit(opsToWorkspaceEdit(doc.uri, ops));
  return true;
}

// Run a column transform on the table at the cursor and keep the cursor in
// column `targetCol(c)`.
async function columnCommand(transform, targetCol) {
  const editor = vscode.window.activeTextEditor;
  if (!editor) return;
  const doc = editor.document;
  const pos = editor.selection.active;
  const table = findTable(doc, pos.line);
  if (!table) {
    vscode.window.showInformationMessage(NO_TABLE);
    return;
  }
  const r = pos.line - table.start;
  const c = Math.max(0, cellIndexAt(table.rows[r], pos.character));
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
const COMMANDS = {
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

module.exports = { COMMANDS, sortOps, sortTableMessage };
