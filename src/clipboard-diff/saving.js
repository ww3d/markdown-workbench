// The immediate save of every clipboard-diff page (docs/DECISIONS.md #48): a
// page never stays unsaved long enough for VS Code's backup tracker (~1 s).
// An extension's document.save() counts as an explicit save, so VS Code runs
// the user's save actions (trim trailing whitespace, final newline, format on
// save, code actions) on it - on every keystroke. Where the page is the
// focused primary editor, the save goes through "Save without Formatting",
// which skips them; elsewhere document.save() stays, and the edits made while
// that save runs - from the call on, since VS Code 1.100 runs the save actions
// before onWillSaveTextDocument - are marked as save actions so they never
// reach the real file.

const vscode = require('vscode');
const { SCHEME } = require('./store');

const SAVE_WITHOUT_FORMATTING = 'workbench.action.files.saveWithoutFormatting';

class PageSaver {
  constructor() {
    this.saving = new Set(); // uri strings of pages inside a document.save()
  }

  /** Listeners that bracket a save's own edits; add them to the subscriptions. */
  register() {
    return [
      vscode.workspace.onWillSaveTextDocument((e) => {
        if (e.document.uri.scheme === SCHEME)
          this.saving.add(e.document.uri.toString());
      }),
      vscode.workspace.onDidSaveTextDocument((doc) =>
        this.saving.delete(doc.uri.toString()),
      ),
    ];
  }

  /** True while a save of `doc` runs: its edits now are save actions. */
  isSaving(doc) {
    return this.saving.has(doc.uri.toString());
  }

  /** Saves the page `doc` now; `onFailed` runs when it could not be saved. */
  save(doc, onFailed) {
    const key = doc.uri.toString();
    const done = (ok) => {
      this.saving.delete(key);
      if (ok === false) onFailed();
      // An edit that arrived while this save ran counts as the save's own and
      // saved nothing; save again rather than leave the page unsaved.
      else if (doc.isDirty) this.save(doc, onFailed);
    };
    const fail = () => {
      this.saving.delete(key);
      onFailed();
    };
    if (isFocusedPrimary(doc)) {
      vscode.commands.executeCommand(SAVE_WITHOUT_FORMATTING).then(done, fail);
    } else {
      this.saving.add(key);
      doc.save().then(done, fail);
    }
  }
}

// "Save without Formatting" saves the active editor - for a diff, its right
// (modified) side. So it only saves `doc` when the focused editor shows it
// and the active tab has it on the right or on its own.
function isFocusedPrimary(doc) {
  const key = doc.uri.toString();
  if (vscode.window.activeTextEditor?.document.uri.toString() !== key)
    return false;
  const input = vscode.window.tabGroups.activeTabGroup?.activeTab?.input;
  if (input instanceof vscode.TabInputTextDiff)
    return input.modified.toString() === key;
  return input instanceof vscode.TabInputText && input.uri.toString() === key;
}

module.exports = {
  PageSaver,
  SAVE_WITHOUT_FORMATTING,
  _internal: { isFocusedPrimary },
};
