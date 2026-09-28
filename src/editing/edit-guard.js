// Re-entrancy guard shared by the structural editing commands and the document
// change listener: while we apply our own edits, the listener must not also fire
// its manual-renumber/type-propagation pass on them.
let propagating = false;

function isPropagating() {
  return propagating;
}

function setPropagating(v) {
  propagating = v;
}

// Run an editor edit with the change listener suppressed, so our own structural
// renumbering is never re-processed as a manual marker change.
async function suppressedEdit(editor, cb) {
  propagating = true;
  try {
    return await editor.edit(cb);
  } finally {
    propagating = false;
  }
}

module.exports = { suppressedEdit, isPropagating, setPropagating };
