import * as vscode from 'vscode';

import { CHECKBOX_RE, checkboxBoxPos } from '../markdown/syntax.ts';

/**
 * Flip the nth "[ ]"/"[x]" occurrence on a source line (table cells).
 * Code spans are blanked out (index-preserving) before counting, because the
 * renderer does not convert brackets inside them either - otherwise the
 * occurrence indices would drift apart.
 */
function applyCellToggle(
  document: vscode.TextDocument,
  lineNo: number,
  idx: number,
  checked: boolean,
): void {
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

/**
 * Flip the single character inside [ ] / [x] on each given line.
 * One WorkspaceEdit -> all toggles happen in parallel and form a single undo step.
 */
function applyToggle(
  document: vscode.TextDocument,
  lines: readonly number[],
  checked: boolean,
): void {
  const edit = new vscode.WorkspaceEdit();
  for (const lineNo of lines) {
    if (lineNo < 0 || lineNo >= document.lineCount) continue;
    const text = document.lineAt(lineNo).text;
    const m = CHECKBOX_RE.exec(text);
    if (!m) continue;
    const bracketContentPos = checkboxBoxPos(m);
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

export { CHECKBOX_RE, applyCellToggle, applyToggle };
