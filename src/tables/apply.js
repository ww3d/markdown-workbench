// Shared glue between the pure table model and the editor: render a grid per the
// settings, apply the minimal line edits as one undo step, place the cursor in a
// cell of the edited text.

const vscode = require('vscode');
const { autoFormat, formatGrid, lineEdits } = require('./format');
const { parseRow } = require('./row');
const { displayWidth } = require('./width');

const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' });

/**
 * Lines for a grid: aligned (autoFormat) with `autoAlign` or `force`; otherwise
 * only rows that are new or marked `dirty` are written (single spaces), all
 * others keep their document text.
 * @param {import('./format.js').Grid} grid
 * @param {{ autoAlign: boolean, maxWidth: number, ambiguousWide: boolean }} cfg
 * @param {(line: number) => string} oldText
 * @param {boolean} [force]
 * @returns {string[]}
 */
function renderGrid(grid, cfg, oldText, force) {
  if (cfg.autoAlign || force) return autoFormat(grid, cfg).lines;
  const compact = formatGrid(grid, { mode: 'consolidate' }).lines;
  return grid.rows.map((r, i) =>
    r.line === undefined || r.dirty ? compact[i] : oldText(r.line),
  );
}

/**
 * The replace operations turning the document's table lines into `lines`.
 * @param {vscode.TextDocument} doc
 */
function gridOps(doc, grid, lines) {
  return lineEdits((l) => doc.lineAt(l).text, grid, lines);
}

/**
 * Apply replace operations through `editFn` (one undo step). No operation, no
 * edit and no undo step.
 * @param {vscode.TextEditor} editor
 * @param {Array<{ line: number, start: number, end: number, text: string }>} ops
 * @param {(editor: vscode.TextEditor, cb: (b: vscode.TextEditorEdit) => void) => Thenable<boolean>} editFn
 * @returns {Promise<boolean>} whether an edit was made
 */
async function applyOps(editor, ops, editFn) {
  if (!ops.length) return false;
  await editFn(editor, (b) => {
    for (const o of ops)
      b.replace(new vscode.Range(o.line, o.start, o.line, o.end), o.text);
  });
  return true;
}

/** The same operations as a WorkspaceEdit (for the preview's sort message). */
function opsToWorkspaceEdit(uri, ops) {
  const edit = new vscode.WorkspaceEdit();
  for (const o of ops)
    edit.replace(uri, new vscode.Range(o.line, o.start, o.line, o.end), o.text);
  return edit;
}

/**
 * Content range of cell `col` on a line of text; an empty cell yields a caret
 * one space after its left pipe. Null when the row has no such cell.
 * @param {string} text
 * @param {number} col
 * @returns {{ start: number, end: number } | null}
 */
function cellRange(text, col) {
  const cell = parseRow(text).cells[col];
  if (!cell) return null;
  if (cell.cStart < cell.cEnd) return { start: cell.cStart, end: cell.cEnd };
  const caret = Math.min(cell.start + 1, cell.end);
  return { start: caret, end: caret };
}

/**
 * Put the cursor into cell `col` of document line `line`: the content selected
 * (`select`), else the caret at its start (`at: 'start'`) or end. A missing cell
 * puts the caret at the end of the line.
 * @param {vscode.TextEditor} editor
 */
function placeInCell(editor, line, col, { select = false, at = 'start' } = {}) {
  const text = editor.document.lineAt(line).text;
  const r = cellRange(text, col);
  let sel;
  if (!r) sel = new vscode.Selection(line, text.length, line, text.length);
  else if (select) sel = new vscode.Selection(line, r.start, line, r.end);
  else {
    const c = at === 'end' ? r.end : r.start;
    sel = new vscode.Selection(line, c, line, c);
  }
  editor.selection = sel;
  editor.selections = [sel];
  editor.revealRange?.(sel);
}

/**
 * The character in a cell's text reached after `width` display columns, for
 * keeping the caret's visual offset when moving between rows.
 * @param {string} text cell content
 * @param {number} width
 * @param {boolean} ambiguousWide
 * @returns {number} offset into text (text.length when the cell is narrower)
 */
function offsetAtWidth(text, width, ambiguousWide) {
  let w = 0;
  for (const { segment, index } of graphemes.segment(text)) {
    if (w >= width) return index;
    w += displayWidth(segment, ambiguousWide);
  }
  return text.length;
}

module.exports = {
  renderGrid,
  gridOps,
  applyOps,
  opsToWorkspaceEdit,
  cellRange,
  placeInCell,
  offsetAtWidth,
};
