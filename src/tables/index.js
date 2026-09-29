// Markdown table editing in the text editor (#86, docs/DECISIONS.md #49): a GFM
// table model that sees the preview's table, Enter/Tab/arrow handling, sorting,
// column commands, CSV/TSV paste, diagnostics and code actions. The Enter, Tab
// and Shift+Enter branches are called from src/editing (the keys are shared with
// list editing); everything else registers here.

import * as vscode from 'vscode';
import { tableEnter, tableShiftEnter } from './enter.js';
import { tableTab } from './tab.js';
import { registerArrows } from './arrows.js';
import { COMMANDS, sortTableMessage } from './commands.js';
import { registerPaste } from './paste.js';
import { registerDiagnostics } from './diagnostics.js';

/**
 * Register the table commands, the arrow keys' context key, the paste provider,
 * the diagnostics and the code actions.
 * @param {vscode.ExtensionContext} context
 */
function registerTableFeatures(context) {
  for (const [id, fn] of Object.entries(COMMANDS))
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  registerArrows(context);
  registerPaste(context);
  registerDiagnostics(context);
}

/** Authoring-menu entries (Alt+M) for the table commands. */
const MENU_ITEMS = [
  {
    label: '$(sort-precedence) Sort table by column ascending',
    cmd: 'markdownWorkbench.sortTableAscending',
  },
  {
    label: '$(sort-precedence) Sort table by column descending',
    cmd: 'markdownWorkbench.sortTableDescending',
  },
  {
    label: '$(insert) Insert column left',
    cmd: 'markdownWorkbench.insertColumnLeft',
  },
  {
    label: '$(insert) Insert column right',
    cmd: 'markdownWorkbench.insertColumnRight',
  },
  { label: '$(trash) Delete column', cmd: 'markdownWorkbench.deleteColumn' },
  {
    label: '$(arrow-left) Move column left',
    cmd: 'markdownWorkbench.moveColumnLeft',
  },
  {
    label: '$(arrow-right) Move column right',
    cmd: 'markdownWorkbench.moveColumnRight',
  },
];

export {
  registerTableFeatures,
  tableEnter,
  tableShiftEnter,
  tableTab,
  sortTableMessage,
  MENU_ITEMS,
};
