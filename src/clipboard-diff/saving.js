// The immediate save of every clipboard-diff page (docs/DECISIONS.md #48): a
// page never stays unsaved long enough for VS Code's backup tracker (~1 s).
// An extension's document.save() counts as an explicit save, so VS Code runs
// the user's save actions (trim trailing whitespace, final newline, format on
// save, code actions) on it - on every keystroke. Where the page is the
// focused primary editor, the save goes through "Save without Formatting",
// which skips them; elsewhere document.save() stays, and the edits made while
// that save runs - from the call on, since VS Code 1.100 runs the save actions
// before onWillSaveTextDocument - are marked as save actions so they never
// reach the real file. Save actions run before the write, so on did-save
// whatever the page holds beyond the written text is the user's and is passed
// on after all (sync.js reconcileSaved).

const vscode = require('vscode');
const { SCHEME } = require('./store');

const SAVE_WITHOUT_FORMATTING = 'workbench.action.files.saveWithoutFormatting';
/**
 * A save window opened by onWillSaveTextDocument (a save VS Code started, e.g.
 * Ctrl+S) closes on did-save or after this long, so a save that fails without
 * did-save cannot keep a page "saving" - unsaved - for good.
 */
const SAVE_WINDOW_MS = 3000;

class PageSaver {
  /**
   * `onMarkedSaved(doc)` runs on did-save of a save whose edits counted as save
   * actions, so a user edit that landed after its write is not lost.
   */
  constructor(onMarkedSaved = () => {}) {
    this.saving = new Map(); // uri string -> time the save window opened
    this.onMarkedSaved = onMarkedSaved;
  }

  /** Listeners that bracket a save's own edits; add them to the subscriptions. */
  register() {
    return [
      vscode.workspace.onWillSaveTextDocument((e) => {
        if (e.document.uri.scheme === SCHEME)
          this.saving.set(e.document.uri.toString(), Date.now());
      }),
      vscode.workspace.onDidSaveTextDocument((doc) => {
        const marked = this.isSaving(doc);
        this.saving.delete(doc.uri.toString());
        if (marked) this.onMarkedSaved(doc);
      }),
    ];
  }

  /** True while a save of `doc` runs: its edits now are save actions. */
  isSaving(doc) {
    const since = this.saving.get(doc.uri.toString());
    return since !== undefined && Date.now() - since < SAVE_WINDOW_MS;
  }

  /** Saves the page `doc` now; `onFailed` runs when it could not be saved. */
  save(doc, onFailed) {
    const key = doc.uri.toString();
    const version = doc.version;
    const finish = (failed) => {
      this.saving.delete(key);
      if (failed) onFailed();
      // An edit that arrived while this save ran saved nothing of its own;
      // save again rather than leave the page unsaved.
      else if (doc.isDirty) this.save(doc, onFailed);
    };
    const fail = () => finish(true);
    if (isFocusedPrimary(doc)) {
      // The command resolves to nothing, success or not: an unsaved page at
      // the same version means this save failed; a newer one means an edit came.
      vscode.commands
        .executeCommand(SAVE_WITHOUT_FORMATTING)
        .then(() => finish(doc.isDirty && doc.version === version), fail);
    } else {
      this.saving.set(key, Date.now());
      doc.save().then((ok) => finish(ok === false), fail);
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
  SAVE_WINDOW_MS,
  _internal: { isFocusedPrimary },
};
