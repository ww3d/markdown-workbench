// Warnings for cells beyond the header width - GFM drops them silently (spec
// example 204) - with the quick fix "Add column to header" (X3), and the code
// action "Right-align column" for number columns (K3).

const vscode = require('vscode');
const { findTable, scanTables } = require('./detect');
const { cellIndexAt } = require('./row');
const { toGrid } = require('./format');
const { widenHeader } = require('./grid-ops');
const { parseNumber } = require('./sort');
const { renderGrid, gridOps, opsToWorkspaceEdit } = require('./apply');
const { tablesConfig } = require('./config');

const CODE = 'table-extra-cells';
const DEBOUNCE_MS = 250;

/**
 * Diagnostics for every row with more cells than its table's header.
 * @param {vscode.TextDocument} doc
 * @returns {vscode.Diagnostic[]}
 */
function extraCellDiagnostics(doc) {
  const out = [];
  for (const table of scanTables(doc)) {
    const n = table.columnCount;
    for (const row of table.rows.slice(2)) {
      if (row.cells.length <= n) continue;
      const range = new vscode.Range(
        row.line,
        row.cells[n].start,
        row.line,
        row.cells.at(-1).end,
      );
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
function numericAlignAction(doc, range) {
  const table = findTable(doc, range.start.line);
  if (!table) return null;
  const row = table.rows[range.start.line - table.start];
  const col = cellIndexAt(row, range.start.character);
  if (col < 0 || col >= table.columnCount || table.aligns[col]) return null;
  const values = table.rows
    .slice(2)
    .map((r) => r.cells[col]?.text ?? '')
    .filter(Boolean);
  if (!values.length || values.some((v) => parseNumber(v) === null))
    return null;
  const sep = table.rows[1].cells[col];
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
function widenHeaderAction(doc, diagnostic) {
  const table = findTable(doc, diagnostic.range.start.line);
  if (!table) return null;
  const grid = widenHeader(toGrid(table));
  grid.rows[0].dirty = true;
  grid.rows[1].dirty = true;
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
const codeActionProvider = {
  provideCodeActions(doc, range, context) {
    const cfg = tablesConfig();
    const actions = [];
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
function registerDiagnostics(context) {
  const collection = vscode.languages.createDiagnosticCollection(
    'markdownWorkbench.tables',
  );
  const timers = new Map();
  const refresh = (doc) => {
    if (doc.languageId !== 'markdown') return;
    if (!tablesConfig().validate) collection.delete(doc.uri);
    else collection.set(doc.uri, extraCellDiagnostics(doc));
  };
  const schedule = (doc) => {
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

module.exports = {
  registerDiagnostics,
  extraCellDiagnostics,
  codeActionProvider,
};
