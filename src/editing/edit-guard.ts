// Re-entrancy guard shared by the structural editing commands and the document
// change listener: while we apply our own edits, the listener must not also fire
// its manual-renumber/type-propagation pass on them.
import type * as vscode from 'vscode';

let propagating = false;

/** Whether a suppressed edit is currently running. */
function isPropagating(): boolean {
  return propagating;
}

/**
 * Set the re-entrancy guard directly, for a caller that cannot use
 * {@link suppressedEdit} (a bare edit block, or a test).
 */
function setPropagating(v: boolean): void {
  propagating = v;
}

/**
 * Run an editor edit with the change listener suppressed, so our own structural
 * renumbering is never re-processed as a manual marker change.
 * @returns whether the editor applied the edit
 */
async function suppressedEdit(
  editor: vscode.TextEditor,
  cb: (builder: vscode.TextEditorEdit) => void,
): Promise<boolean> {
  propagating = true;
  try {
    return await editor.edit(cb);
  } finally {
    propagating = false;
  }
}

export { suppressedEdit, isPropagating, setPropagating };
