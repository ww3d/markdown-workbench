const vscode = require('vscode');

// Matches task list items: "- [ ] text", "* [x] text", "1. [X] text", with
// indentation; the label may be empty. Compound items carry a second list
// marker between the first marker and the box ("1. - [ ] text",
// "- 1. [ ] text") - generically (marker, whitespace) x2, box. Group 1
// spans the whole prefix up to the box, so applyToggle keeps hitting the
// box character exactly. Must classify the same lines as the render-side
// task-list plugin.
const CHECKBOX_RE =
  /^(\s*(?:[-*+]|\d+[.)])\s+(?:(?:[-*+]|\d+[.)])\s+)?)\[( |x|X)\](\s.*)?$/;

// Flip the nth "[ ]"/"[x]" occurrence on a source line (table cells).
// Code spans are blanked out (index-preserving) before counting, because the
// renderer does not convert brackets inside them either - otherwise the
// occurrence indices would drift apart.
function applyCellToggle(document, lineNo, idx, checked) {
  if (lineNo < 0 || lineNo >= document.lineCount) return;
  const text = document.lineAt(lineNo).text;
  const scannable = text.replace(/(`+)[^`]*?\1/g, (m) => ' '.repeat(m.length));
  const re = /\[( |x|X)\]/g;
  let i = 0;
  for (const m of scannable.matchAll(re)) {
    if (i++ === idx) {
      const edit = new vscode.WorkspaceEdit();
      edit.replace(
        document.uri,
        new vscode.Range(lineNo, m.index + 1, lineNo, m.index + 2),
        checked ? 'x' : ' ',
      );
      vscode.workspace.applyEdit(edit);
      return;
    }
  }
}

// Flip the single character inside [ ] / [x] on each given line.
// One WorkspaceEdit -> all toggles happen in parallel and form a single undo step.
function applyToggle(document, lines, checked) {
  const edit = new vscode.WorkspaceEdit();
  for (const lineNo of lines) {
    if (lineNo < 0 || lineNo >= document.lineCount) continue;
    const text = document.lineAt(lineNo).text;
    const m = CHECKBOX_RE.exec(text);
    if (!m) continue;
    const bracketContentPos = m[1].length + 1; // position of the char between [ ]
    edit.replace(
      document.uri,
      new vscode.Range(
        lineNo,
        bracketContentPos,
        lineNo,
        bracketContentPos + 1,
      ),
      checked ? 'x' : ' ',
    );
  }
  vscode.workspace.applyEdit(edit);
}

module.exports = { CHECKBOX_RE, applyCellToggle, applyToggle };
