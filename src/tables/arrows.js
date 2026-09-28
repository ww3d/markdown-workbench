// Up/Down inside a table (T9) and the `markdownWorkbench.inTable` context key the
// arrow keybindings hang on (T10). The key is computed on selection changes and
// written only when it flips, so arrows outside tables never reach the extension.

const vscode = require('vscode');
const { findTable } = require('./detect');
const { cellIndexAt } = require('./row');
const { displayWidth } = require('./width');
const { offsetAtWidth } = require('./apply');
const { tablesConfig } = require('./config');

const CONTEXT_KEY = 'markdownWorkbench.inTable';

/**
 * Move the cursor to the same cell of the row above (`dir` -1) or below (+1),
 * at the same visual offset or the cell end, skipping the delimiter row. The
 * plain cursor move runs at the table edge, with a selection or several
 * cursors, with `editor.wordWrap` other than `off`, or outside a table.
 * @param {number} dir
 */
function tableArrow(dir) {
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
  const c = cellIndexAt(row, pos.character);
  const target = table.rows[t].cells[c];
  if (c < 0 || c >= row.cells.length || !target) return plain();
  const cell = row.cells[c];
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
}

let lastInTable = false;

// Whether the (single) cursor of `editor` stands in a table row. Cheap exit
// first: a line without `|` is never a table row.
function computeInTable(editor) {
  if (editor?.document.languageId !== 'markdown') return false;
  if (editor.selections.length !== 1) return false;
  const line = editor.selection.active.line;
  if (!editor.document.lineAt(line).text.includes('|')) return false;
  return findTable(editor.document, line) !== null;
}

/**
 * Recompute the context key for `editor` and set it only when it changed.
 * @param {vscode.TextEditor | undefined} editor
 */
function updateInTable(editor) {
  const value = computeInTable(editor);
  if (value === lastInTable) return;
  lastInTable = value;
  vscode.commands.executeCommand('setContext', CONTEXT_KEY, value);
}

/** Register the arrow commands and the context-key listeners. */
function registerArrows(context) {
  const reg = (id, fn) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  reg('markdownWorkbench.onUpKey', () => tableArrow(-1));
  reg('markdownWorkbench.onDownKey', () => tableArrow(1));
  context.subscriptions.push(
    vscode.window.onDidChangeTextEditorSelection((e) =>
      updateInTable(e.textEditor),
    ),
    vscode.window.onDidChangeActiveTextEditor((e) => updateInTable(e)),
  );
}

module.exports = {
  tableArrow,
  updateInTable,
  registerArrows,
  _resetForTest: () => {
    lastInTable = false;
  },
};
