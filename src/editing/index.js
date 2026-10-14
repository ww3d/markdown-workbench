// Markdown editing helpers for the text editor (not the workbench view):
// Enter list continuation, Tab/Shift+Tab nesting, formatting shortcuts,
// link/table insertion, table reflow, selection sorting. Modeled on the
// generic authoring features of Learn Markdown / Markdown All in One.
const vscode = require('vscode');
const {
  LIST_ITEM_RE,
  COMPOUND_TASK_RE,
  numericMarker,
  execListItem,
  advanceMarker,
  nextLetterSeq,
} = require('./list-markers');
const {
  contentColumn,
  enclosingListItem,
  propagateMarkerType,
} = require('./list-structure');
const { setPropagating } = require('./edit-guard');
const {
  FENCE_RE,
  fenceIsUnclosed,
  onEnterKey,
  onShiftEnterKey,
} = require('./enter');
const { indentUnitFor, onTabKey, onShiftTabKey } = require('./tab');
const {
  joinSeam,
  joinForwardOrFallback,
  joinBackwardOrFallback,
} = require('./join');
const {
  escapeSnippet,
  toggleWrap,
  insertWebLink,
  insertFileLink,
} = require('./wrap-links');
const {
  insertList,
  insertTable,
  insertLanguageIdentifier,
} = require('./insert');
const { reflowTable, reflowTableCommand } = require('./table-reflow');
const { registerTableFeatures } = require('../tables');
const { sortSelection } = require('./sort');
const { authoringMenu } = require('./menu');
const { registerFenceLanguageCompletion } = require('./fence-completion');
const { registerMarkerTypePropagation } = require('./marker-propagation');

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

module.exports = {
  registerEditingCommands,
  reflowTable,
  LIST_ITEM_RE,
  // Exported for tests only.
  _internal: {
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
  },
};
