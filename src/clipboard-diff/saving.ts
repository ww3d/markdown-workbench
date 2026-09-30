// The immediate save of every clipboard-diff page (docs/DECISIONS.md #48): a
// page never stays unsaved long enough for VS Code's backup tracker (~1 s).
// An extension's document.save() counts as an explicit save, so VS Code runs
// the user's save actions (trim trailing whitespace, final newline, format on
// save, code actions) on it - on every keystroke. Where the page is the
// focused editor (either side of a diff), the save goes through "Save without
// Formatting", which skips them; elsewhere document.save() stays, and the
// edits made while that save runs - from the call on, since VS Code 1.100 runs
// the save actions before onWillSaveTextDocument - are marked as save actions
// so they never reach the real file. Save actions run before the write, so on did-save
// whatever the page holds beyond the written text is the user's and is passed
// on after all (sync.ts reconcileSaved).

import * as vscode from 'vscode';
import { SCHEME } from './store.ts';

const SAVE_WITHOUT_FORMATTING = 'workbench.action.files.saveWithoutFormatting';
/**
 * A save window opened by onWillSaveTextDocument (a save VS Code started, e.g.
 * Ctrl+S) closes on did-save or after this long, so a save that fails without
 * did-save cannot keep a page "saving" - unsaved - for good.
 */
const SAVE_WINDOW_MS = 3000;

/** Saves clipboard-diff pages at once and tells a save's own edits from the user's. */
class PageSaver {
  readonly saving = new Map<string, number>(); // uri string -> time the save window opened
  private readonly onMarkedSaved: (
    doc: vscode.TextDocument,
    focused: boolean,
  ) => void;

  /**
   * `onMarkedSaved(doc, focused)` runs on did-save of a save whose edits counted
   * as save actions, so a user edit that landed after its write is not lost;
   * `focused` tells whether the page is the focused editor by then.
   */
  constructor(
    onMarkedSaved: (
      doc: vscode.TextDocument,
      focused: boolean,
    ) => void = () => {},
  ) {
    this.onMarkedSaved = onMarkedSaved;
  }

  /** Listeners that bracket a save's own edits; add them to the subscriptions. */
  register(): vscode.Disposable[] {
    return [
      vscode.workspace.onWillSaveTextDocument((e) => {
        if (e.document.uri.scheme === SCHEME)
          this.saving.set(e.document.uri.toString(), Date.now());
      }),
      vscode.workspace.onDidSaveTextDocument((doc) => {
        const marked = this.isSaving(doc);
        this.saving.delete(doc.uri.toString());
        if (marked) this.onMarkedSaved(doc, isFocused(doc));
      }),
    ];
  }

  /** True while a save of `doc` runs: its edits now are save actions. */
  isSaving(doc: vscode.TextDocument): boolean {
    const since = this.saving.get(doc.uri.toString());
    return since !== undefined && Date.now() - since < SAVE_WINDOW_MS;
  }

  /** Saves the page `doc` now; `onFailed` runs when it could not be saved. */
  save(doc: vscode.TextDocument, onFailed: () => void): void {
    const key = doc.uri.toString();
    const version = doc.version;
    const finish = (failed: boolean): void => {
      this.saving.delete(key);
      if (failed) onFailed();
      // An edit that arrived while this save ran saved nothing of its own;
      // save again rather than leave the page unsaved.
      else if (doc.isDirty) this.save(doc, onFailed);
    };
    const fail = () => finish(true);
    if (isFocused(doc)) {
      // The command resolves to nothing, success or not: an unsaved page at
      // the same version means this save failed; a newer one means an edit came.
      vscode.commands
        .executeCommand(SAVE_WITHOUT_FORMATTING)
        .then(() => finish(doc.isDirty && doc.version === version), fail);
    } else {
      this.saving.set(key, Date.now());
      // save() also resolves false when an edit came during it: only an
      // unsaved page at the same version means this save failed.
      doc
        .save()
        .then(
          (ok) => finish(!ok && doc.isDirty && doc.version === version),
          fail,
        );
    }
  }
}

// "Save without Formatting" saves the focused editor's document - in a diff
// either side (the left one being the selection page). So it saves `doc` when
// the focused editor shows it and the active tab has it on either side or alone.
function isFocused(doc: vscode.TextDocument): boolean {
  const key = doc.uri.toString();
  if (vscode.window.activeTextEditor?.document.uri.toString() !== key)
    return false;
  const input = vscode.window.tabGroups.activeTabGroup?.activeTab?.input;
  if (input instanceof vscode.TabInputTextDiff)
    return (
      input.modified.toString() === key || input.original.toString() === key
    );
  return input instanceof vscode.TabInputText && input.uri.toString() === key;
}

export { PageSaver, SAVE_WITHOUT_FORMATTING, SAVE_WINDOW_MS };
// Exported for tests only.
export const _internal = { isFocused };
