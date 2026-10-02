// Markdown table editing in the text editor (#86, docs/DECISIONS.md #49): a GFM
// table model that sees the preview's table, Enter/Tab/arrow handling, sorting,
// column commands, CSV/TSV paste, diagnostics and code actions. The Enter, Tab
// and Shift+Enter branches are called from src/editing (the keys are shared with
// list editing); everything else registers here.

import * as vscode from 'vscode';
import { tableEnter, tableShiftEnter } from './enter.ts';
import { tableTab } from './tab.ts';
import { registerArrows } from './arrows.ts';
import { COMMANDS, sortTableMessage } from './commands.ts';
import { registerPaste } from './paste.ts';
import { registerDiagnostics } from './diagnostics.ts';

/**
 * Register the table commands, the arrow keys' context key, the paste provider,
 * the diagnostics and the code actions.
 */
function registerTableFeatures(context: vscode.ExtensionContext): void {
  for (const [id, fn] of Object.entries(COMMANDS))
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  registerArrows(context);
  registerPaste(context);
  registerDiagnostics(context);
}

/** An entry of the authoring menu: label with codicon, and the command it runs. */
export interface MenuItem {
  readonly label: string;
  readonly cmd: string;
}

/** Authoring-menu entries (Alt+M) for the table commands. */
const MENU_ITEMS: readonly MenuItem[] = [
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
