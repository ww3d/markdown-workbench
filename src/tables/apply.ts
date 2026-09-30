// Shared glue between the pure table model and the editor: render a grid per the
// settings, apply the minimal line edits as one undo step, place the cursor in a
// cell of the edited text.

import * as vscode from 'vscode';
import { autoFormat, formatGrid, lineEdits } from './format.ts';
import type { Grid, LineEdit } from './format.ts';
import { parseRow } from './row.ts';
import { findTable } from './detect.ts';
import { displayWidth, graphemes } from './width.ts';

/** Runs `cb` as an edit of `editor`; the callers pass `(e, cb) => e.edit(cb)` or a variant that keeps one undo step. */
export type EditFn = (
  editor: vscode.TextEditor,
  cb: (builder: vscode.TextEditorEdit) => void,
) => Thenable<boolean>;

/** The settings `renderGrid` reads. */
export interface RenderConfig {
  readonly autoAlign: boolean;
  readonly maxWidth: number;
  readonly ambiguousWide: boolean;
}

/**
 * Lines for a grid: aligned (autoFormat) with `autoAlign` or `force`; otherwise
 * only rows that are new or marked `dirty` are written (single spaces), all
 * others keep their document text.
 * @param oldText the document text of a line
 */
function renderGrid(
  grid: Grid,
  cfg: RenderConfig,
  oldText: (line: number) => string,
  force?: boolean,
): string[] {
  if (cfg.autoAlign || force) return autoFormat(grid, cfg).lines;
  const compact = formatGrid(grid, { mode: 'consolidate' }).lines;
  return grid.rows.map((r, i) =>
    r.line === undefined || r.dirty ? (compact[i] ?? '') : oldText(r.line),
  );
}

/**
 * The replace operations turning the document's table lines into `lines`.
 */
function gridOps(
  doc: vscode.TextDocument,
  grid: Grid,
  lines: readonly string[],
): LineEdit[] {
  return lineEdits((l) => doc.lineAt(l).text, grid, lines);
}

/**
 * Apply replace operations through `editFn` (one undo step). No operation, no
 * edit and no undo step.
 * @returns whether an edit was made
 */
async function applyOps(
  editor: vscode.TextEditor,
  ops: readonly LineEdit[],
  editFn: EditFn,
): Promise<boolean> {
  if (!ops.length) return false;
  await editFn(editor, (b) => {
    for (const o of ops)
      b.replace(new vscode.Range(o.line, o.start, o.line, o.end), o.text);
  });
  return true;
}

/** The same operations as a WorkspaceEdit (for the preview's sort message). */
function opsToWorkspaceEdit(
  uri: vscode.Uri,
  ops: readonly LineEdit[],
): vscode.WorkspaceEdit {
  const edit = new vscode.WorkspaceEdit();
  for (const o of ops)
    edit.replace(uri, new vscode.Range(o.line, o.start, o.line, o.end), o.text);
  return edit;
}

/**
 * Content range of cell `col` on document line `line`, with the cells the table
 * model reads there (a list marker can be a cell); an empty cell yields a caret
 * one space after its left pipe. Null when the row has no such cell.
 */
function cellRange(
  doc: vscode.TextDocument,
  line: number,
  col: number,
): { start: number; end: number } | null {
  const table = findTable(doc, line);
  const row = table
    ? table.rows[line - table.start]
    : parseRow(doc.lineAt(line).text);
  const cell = row?.cells[col];
  if (!cell) return null;
  if (cell.cStart < cell.cEnd) return { start: cell.cStart, end: cell.cEnd };
  const caret = Math.min(cell.start + 1, cell.end);
  return { start: caret, end: caret };
}

/**
 * Put the cursor into cell `col` of document line `line`: the content selected
 * (`select`), else the caret at its start (`at: 'start'`) or end. A missing cell
 * puts the caret at the end of the line.
 */
function placeInCell(
  editor: vscode.TextEditor,
  line: number,
  col: number,
  {
    select = false,
    at = 'start',
  }: { select?: boolean; at?: 'start' | 'end' } = {},
): void {
  const text = editor.document.lineAt(line).text;
  const r = cellRange(editor.document, line, col);
  const sel = (() => {
    if (!r) return new vscode.Selection(line, text.length, line, text.length);
    if (select) return new vscode.Selection(line, r.start, line, r.end);
    const c = at === 'end' ? r.end : r.start;
    return new vscode.Selection(line, c, line, c);
  })();
  editor.selection = sel;
  editor.selections = [sel];
  editor.revealRange?.(sel);
}

/**
 * The character in a cell's text reached after `width` display columns, for
 * keeping the caret's visual offset when moving between rows.
 * @param text cell content
 * @returns the offset into text (text.length when the cell is narrower)
 */
function offsetAtWidth(
  text: string,
  width: number,
  ambiguousWide: boolean,
): number {
  let w = 0;
  for (const { segment, index } of graphemes.segment(text)) {
    if (w >= width) return index;
    w += displayWidth(segment, ambiguousWide);
  }
  return text.length;
}

export {
  renderGrid,
  gridOps,
  applyOps,
  opsToWorkspaceEdit,
  cellRange,
  placeInCell,
  offsetAtWidth,
};
