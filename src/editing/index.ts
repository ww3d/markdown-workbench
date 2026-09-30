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
} from './list-markers.ts';
import {
  contentColumn,
  enclosingListItem,
  propagateMarkerType,
} from './list-structure.ts';
import { setPropagating } from './edit-guard.ts';
import {
  FENCE_RE,
  fenceIsUnclosed,
  onEnterKey,
  onShiftEnterKey,
} from './enter.ts';
import { indentUnitFor, onTabKey, onShiftTabKey } from './tab.ts';
import {
  joinSeam,
  joinForwardOrFallback,
  joinBackwardOrFallback,
} from './join.ts';
import {
  escapeSnippet,
  toggleWrap,
  insertWebLink,
  insertFileLink,
} from './wrap-links.ts';
import { insertList, insertTable, insertLanguageIdentifier } from './insert.ts';
import { reflowTable, reflowTableCommand } from './table-reflow.ts';
import { registerTableFeatures } from '../tables/index.ts';
import { sortSelection } from './sort.ts';
import { authoringMenu } from './menu.ts';
import { registerFenceLanguageCompletion } from './fence-completion.ts';
import { registerMarkerTypePropagation } from './marker-propagation.ts';

// --- Registration ------------------------------------------------------------------------------

/**
 * Register every editing command and listener this module owns (keys, table
 * features, marker-type propagation, fence-language completion).
 * @param shikiLangs bundled language ids, for the language-identifier
 *   picker and fence completion
 */
function registerEditingCommands(
  context: vscode.ExtensionContext,
  shikiLangs: readonly string[],
): void {
  registerFenceLanguageCompletion(context, shikiLangs);
  registerTableFeatures(context);
  registerMarkerTypePropagation(context);
  const reg = (id: string, fn: () => unknown) =>
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
/** Internals exported for tests only. */
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
  setPropagatingForTest: (v: boolean): void => {
    setPropagating(v);
  },
};
