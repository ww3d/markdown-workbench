// Markdown editing helpers for the text editor (not the workbench view):
// Enter list continuation, Tab/Shift+Tab nesting, formatting shortcuts,
// link/table insertion, table reflow, selection sorting. Modeled on the
// generic authoring features of Learn Markdown / Markdown All in One.
import * as vscode from 'vscode';
import {
  LIST_ITEM_RE,
  COMPOUND_TASK_RE,
  numericMarker,
  execListItem,
  advanceMarker,
  nextLetterSeq,
} from './list-markers.js';
import {
  contentColumn,
  enclosingListItem,
  propagateMarkerType,
} from './list-structure.js';
import { setPropagating } from './edit-guard.js';
import {
  FENCE_RE,
  fenceIsUnclosed,
  onEnterKey,
  onShiftEnterKey,
} from './enter.js';
import { indentUnitFor, onTabKey, onShiftTabKey } from './tab.js';
import {
  joinSeam,
  joinForwardOrFallback,
  joinBackwardOrFallback,
} from './join.js';
import {
  escapeSnippet,
  toggleWrap,
  insertWebLink,
  insertFileLink,
} from './wrap-links.js';
import { insertList, insertTable, insertLanguageIdentifier } from './insert.js';
import { reflowTable, reflowTableCommand } from './table-reflow.js';
import { registerTableFeatures } from '../tables/index.js';
import { sortSelection } from './sort.js';
import { authoringMenu } from './menu.js';
import { registerFenceLanguageCompletion } from './fence-completion.js';
import { registerMarkerTypePropagation } from './marker-propagation.js';

// --- Registration ------------------------------------------------------------------------------

/**
 * Register every editing command and listener this module owns (keys, table
 * features, marker-type propagation, fence-language completion).
 * @param {vscode.ExtensionContext} context
 * @param {string[]} shikiLangs bundled language ids, for the language-identifier
 *   picker and fence completion
 */
function registerEditingCommands(context, shikiLangs) {
  registerFenceLanguageCompletion(context, shikiLangs);
  registerTableFeatures(context);
  registerMarkerTypePropagation(context);
  const reg = (id, fn) =>
    context.subscriptions.push(vscode.commands.registerCommand(id, fn));
  reg('markdownWorkbench.onEnterKey', onEnterKey);
  reg('markdownWorkbench.onShiftEnterKey', onShiftEnterKey);
  reg('markdownWorkbench.onTabKey', onTabKey);
  reg('markdownWorkbench.onShiftTabKey', onShiftTabKey);
  reg('markdownWorkbench.joinForwardOrFallback', joinForwardOrFallback);
  reg('markdownWorkbench.joinBackwardOrFallback', joinBackwardOrFallback);
  reg('markdownWorkbench.formatBold', () => toggleWrap('**'));
  reg('markdownWorkbench.formatItalic', () => toggleWrap('*'));
  reg('markdownWorkbench.formatCode', () => toggleWrap('`'));
  reg('markdownWorkbench.insertWebLink', insertWebLink);
  reg('markdownWorkbench.insertFileLink', insertFileLink);
  reg('markdownWorkbench.insertBulletedList', () => insertList('bulleted'));
  reg('markdownWorkbench.insertNumberedList', () => insertList('numbered'));
  reg('markdownWorkbench.insertTaskList', () => insertList('task'));
  reg('markdownWorkbench.insertTable', insertTable);
  reg('markdownWorkbench.distributeTable', () =>
    reflowTableCommand('distribute'),
  );
  reg('markdownWorkbench.consolidateTable', () =>
    reflowTableCommand('consolidate'),
  );
  reg('markdownWorkbench.sortAscending', () => sortSelection(false));
  reg('markdownWorkbench.sortDescending', () => sortSelection(true));
  reg('markdownWorkbench.insertLanguageIdentifier', () =>
    insertLanguageIdentifier(shikiLangs),
  );
  reg('markdownWorkbench.authoringMenu', authoringMenu);
}

export { registerEditingCommands, reflowTable, LIST_ITEM_RE };
// Exported for tests only.
export const _internal = {
  FENCE_RE,
  COMPOUND_TASK_RE,
  fenceIsUnclosed,
  indentUnitFor,
  escapeSnippet,
  numericMarker,
  contentColumn,
  enclosingListItem,
  onEnterKey,
  onShiftEnterKey,
  onTabKey,
  onShiftTabKey,
  joinForwardOrFallback,
  joinBackwardOrFallback,
  joinSeam,
  sortSelection,
  toggleWrap,
  execListItem,
  advanceMarker,
  nextLetterSeq,
  propagateMarkerType,
  setPropagatingForTest: (v) => {
    setPropagating(v);
  },
};
