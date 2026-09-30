// Warnings for cells beyond the header width - GFM drops them silently (spec
// example 204) - with the quick fix "Add column to header" (X3), and the code
// action "Right-align column" for number columns (K3).

import * as vscode from 'vscode';
import { findTable, scanTables } from './detect.ts';
import { cellIndexAt } from './row.ts';
import { toGrid } from './format.ts';
import { widenHeader } from './grid-ops.ts';
import { parseNumber } from './sort.ts';
import { renderGrid, gridOps, opsToWorkspaceEdit } from './apply.ts';
import { tablesConfig } from './config.ts';

const CODE = 'table-extra-cells';
const DEBOUNCE_MS = 250;

/**
 * Diagnostics for every row with more cells than its table's header.
 */
function extraCellDiagnostics(doc: vscode.TextDocument): vscode.Diagnostic[] {
  const out: vscode.Diagnostic[] = [];
  for (const table of scanTables(doc)) {
    const n = table.columnCount;
    for (const row of table.rows.slice(2)) {
      const first = row.cells[n];
      const last = row.cells.at(-1);
      if (!first || !last) continue;
      const range = new vscode.Range(row.line, first.start, row.line, last.end);
      const d = new vscode.Diagnostic(
        range,
        `${row.cells.length - n} cell(s) beyond the ${n} header column(s) are not rendered.`,
        vscode.DiagnosticSeverity.Warning,
      );
      d.code = CODE;
      d.source = 'Markdown Workbench';
      out.push(d);
    }
  }
  return out;
}

// Right-align action for the column at `range.start`, or null when the column
// has an alignment already or holds anything but numbers.
function numericAlignAction(
  doc: vscode.TextDocument,
  range: vscode.Range,
): vscode.CodeAction | null {
  const table = findTable(doc, range.start.line);
  if (!table) return null;
  const row = table.rows[range.start.line - table.start];
  if (!row) return null;
  const col = cellIndexAt(row, range.start.character);
  if (col < 0 || col >= table.columnCount || table.aligns[col]) return null;
  const values = table.rows
    .slice(2)
    .map((r) => r.cells[col]?.text ?? '')
    .filter(Boolean);
  if (!values.length || values.some((v) => parseNumber(v) === null))
    return null;
  const sep = table.rows[1].cells[col];
  if (!sep) return null;
  const action = new vscode.CodeAction(
    'Right-align column',
    vscode.CodeActionKind.RefactorRewrite,
  );
  action.edit = new vscode.WorkspaceEdit();
  // `---` becomes `--:`; a lone `-` gets the colon appended (`-:`).
  const from = sep.cEnd - sep.cStart < 2 ? sep.cEnd : sep.cEnd - 1;
  action.edit.replace(
    doc.uri,
    new vscode.Range(table.start + 1, from, table.start + 1, sep.cEnd),
    ':',
  );
  return action;
}

// Quick fix for one extra-cells diagnostic: widen header and delimiter row.
function widenHeaderAction(
  doc: vscode.TextDocument,
  diagnostic: vscode.Diagnostic,
): vscode.CodeAction | null {
  const table = findTable(doc, diagnostic.range.start.line);
  if (!table) return null;
  const grid = widenHeader(toGrid(table));
  for (const row of grid.rows.slice(0, 2)) row.dirty = true;
  const lines = renderGrid(grid, tablesConfig(), (l) => doc.lineAt(l).text);
  const action = new vscode.CodeAction(
    'Add column to header',
    vscode.CodeActionKind.QuickFix,
  );
  action.diagnostics = [diagnostic];
  action.isPreferred = true;
  action.edit = opsToWorkspaceEdit(doc.uri, gridOps(doc, grid, lines));
  return action;
}

/** The code action provider for both actions. */
const codeActionProvider: vscode.CodeActionProvider = {
  provideCodeActions(doc, range, context) {
    const cfg = tablesConfig();
    const actions: vscode.CodeAction[] = [];
    for (const d of context.diagnostics ?? []) {
      if (d.code !== CODE) continue;
      const a = widenHeaderAction(doc, d);
      if (a) actions.push(a);
    }
    if (cfg.suggestNumericAlign) {
      const a = numericAlignAction(doc, range);
      if (a) actions.push(a);
    }
    return actions;
  },
};

/** Register the diagnostics (debounced per change) and the code actions. */
function registerDiagnostics(context: vscode.ExtensionContext): void {
  const collection = vscode.languages.createDiagnosticCollection(
    'markdownWorkbench.tables',
  );
  const timers = new Map<string, ReturnType<typeof setTimeout>>();
  const refresh = (doc: vscode.TextDocument) => {
    if (doc.languageId !== 'markdown') return;
    if (!tablesConfig().validate) collection.delete(doc.uri);
    else collection.set(doc.uri, extraCellDiagnostics(doc));
  };
  const schedule = (doc: vscode.TextDocument) => {
    const key = doc.uri.toString();
    clearTimeout(timers.get(key));
    timers.set(
      key,
      setTimeout(() => {
        timers.delete(key);
        refresh(doc);
      }, DEBOUNCE_MS),
    );
  };
  context.subscriptions.push(
    collection,
    vscode.workspace.onDidOpenTextDocument(refresh),
    vscode.workspace.onDidChangeTextDocument((e) => schedule(e.document)),
    vscode.workspace.onDidCloseTextDocument((doc) =>
      collection.delete(doc.uri),
    ),
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('markdownWorkbench.tables'))
        for (const doc of vscode.workspace.textDocuments ?? []) refresh(doc);
    }),
    vscode.languages.registerCodeActionsProvider(
      { language: 'markdown' },
      codeActionProvider,
      {
        providedCodeActionKinds: [
          vscode.CodeActionKind.QuickFix,
          vscode.CodeActionKind.RefactorRewrite,
        ],
      },
    ),
    {
      dispose: () => {
        for (const t of timers.values()) clearTimeout(t);
      },
    },
  );
  for (const doc of vscode.workspace.textDocuments ?? []) refresh(doc);
}

export { registerDiagnostics, extraCellDiagnostics, codeActionProvider };
