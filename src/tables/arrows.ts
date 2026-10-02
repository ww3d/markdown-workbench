// Up/Down inside a table (T9) and the `markdownWorkbench.inTable` context key the
// arrow keybindings hang on (T10). The key is computed on selection changes and
// written only when it flips, so arrows outside tables never reach the extension.

import * as vscode from 'vscode';
import { findTable, inTableAt, needsParse, carrySpan } from './detect.ts';
import { cellIndexAt } from './row.ts';
import { displayWidth } from './width.ts';
import { offsetAtWidth } from './apply.ts';
import { tablesConfig } from './config.ts';

const CONTEXT_KEY = 'markdownWorkbench.inTable';

/**
 * Move the cursor to the same cell of the row above (`dir` -1) or below (+1),
 * at the same visual offset or the cell end, skipping the delimiter row. The
 * plain cursor move runs at the table edge, with a selection or several
 * cursors, with `editor.wordWrap` other than `off`, or outside a table.
 * @param dir -1 for up, +1 for down
 */
function tableArrow(dir: number): Thenable<unknown> | undefined {
  const plain = () =>
    vscode.commands.executeCommand(dir < 0 ? 'cursorUp' : 'cursorDown');
  const editor = vscode.window.activeTextEditor;
  const cfg = tablesConfig();
  if (!editor || !cfg.enabled || !cfg.arrowNavigation) return plain();
  if (editor.selections.length !== 1 || !editor.selection.isEmpty)
    return plain();
  const doc = editor.document;
  const wrap = vscode.workspace
    .getConfiguration('editor', doc)
    .get('wordWrap', 'off');
  if (wrap !== 'off') return plain();
  const pos = editor.selection.active;
  const table = findTable(doc, pos.line);
  if (!table) return plain();
  const r = pos.line - table.start;
  let t = r + dir;
  if (t === 1) t += dir;
  if (r === 1 || t < 0 || t >= table.rows.length) return plain();
  const row = table.rows[r];
  if (!row) return plain();
  const c = cellIndexAt(row, pos.character);
  const target = table.rows[t]?.cells[c];
  const cell = row.cells[c];
  if (c < 0 || !cell || !target) return plain();
  const before = doc
    .lineAt(pos.line)
    .text.slice(cell.cStart, Math.max(cell.cStart, pos.character));
  const width = displayWidth(before, cfg.ambiguousWide);
  const ch =
    target.cStart + offsetAtWidth(target.text, width, cfg.ambiguousWide);
  const line = table.start + t;
  const caret = new vscode.Selection(line, ch, line, ch);
  editor.selection = caret;
  editor.selections = [caret];
  editor.revealRange?.(caret);
  return undefined;
}

let lastInTable = false;

// Whether the (single) cursor of `editor` stands in a table row. Cheap exit
// first: a line without `|` is never a table row.
function computeInTable(editor: vscode.TextEditor | undefined): boolean {
  if (editor?.document.languageId !== 'markdown') return false;
  if (editor.selections.length !== 1) return false;
  const line = editor.selection.active.line;
  if (!editor.document.lineAt(line).text.includes('|')) return false;
  return inTableAt(editor.document, line);
}

/**
 * Recompute the context key for `editor` and set it only when it changed.
 */
function updateInTable(editor: vscode.TextEditor | undefined): void {
  const value = computeInTable(editor);
  if (value === lastInTable) return;
  lastInTable = value;
  vscode.commands.executeCommand('setContext', CONTEXT_KEY, value);
}

// After an edit the first query of a version costs a block parse of the whole
// document; while typing on a line with `|` outside a table, the key waits
// until the typing pauses - longer than the gap between two keys of normal
// typing. A stale key is harmless: the arrows fall back to the plain move.
const SETTLE_MS = 400;
let settle: ReturnType<typeof setTimeout> | undefined;

/**
 * Recompute the context key after a selection change: at once when that is
 * cheap, otherwise once the typing pauses.
 */
function onSelectionChange(editor: vscode.TextEditor | undefined): void {
  clearTimeout(settle);
  const doc = editor?.document;
  if (editor && doc && editor.selections.length === 1) {
    const line = editor.selection.active.line;
    if (doc.lineAt(line).text.includes('|') && needsParse(doc, line)) {
      settle = setTimeout(() => {
        if (vscode.window.activeTextEditor === editor) updateInTable(editor);
      }, SETTLE_MS);
      return;
    }
  }
  updateInTable(editor);
}

/** Register the arrow commands and the context-key listeners. */
function registerArrows(context: vscode.ExtensionContext): void {
  const reg = (id: string, fn: () => unknown) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  reg('markdownWorkbench.onUpKey', () => tableArrow(-1));
  reg('markdownWorkbench.onDownKey', () => tableArrow(1));
  context.subscriptions.push(
    vscode.window.onDidChangeTextEditorSelection((e) =>
      onSelectionChange(e.textEditor),
    ),
    vscode.window.onDidChangeActiveTextEditor((e) => {
      clearTimeout(settle);
      updateInTable(e);
    }),
    vscode.workspace.onDidChangeTextDocument((e) =>
      carrySpan(e.document, e.contentChanges),
    ),
    { dispose: () => clearTimeout(settle) },
  );
}

export { tableArrow, updateInTable, onSelectionChange, registerArrows };
/** Test hook: forget the last context-key value the module wrote. */
export const _resetForTest = (): void => {
  lastInTable = false;
};
