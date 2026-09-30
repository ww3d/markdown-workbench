import * as vscode from 'vscode';

// Scroll-position handoff between source editor and workbench views:
// pendingInitialScroll carries the editor's top line into a freshly opened
// view; lastKnownTopLine tracks the current top line per document (updated
// from both sync directions) for the way back to the source.

/** Editor top line to scroll a freshly opened view to, by document URI string. */
const pendingInitialScroll = new Map<string, number>();
/** Current top line per document URI string, updated from both sync directions. */
const lastKnownTopLine = new Map<string, number>();
// Last value actually pushed in each sync direction, per document, so a
// sub-threshold change does not trigger another revealRange / scrollTo. The
// webview already coalesces its 'scrolled' posts to ~30Hz; these drop the
// residual redundant host work (a big source file lagged at ~60Hz otherwise).
/** Line last revealed in the editor, by document URI string. */
const lastRevealedLine = new Map<string, number>();
/** Line last posted to the webview as `scrollTo`, by document URI string. */
const lastPostedScrollTo = new Map<string, number>();
/** Fractional-line change below which a sync in either direction is skipped. */
const SYNC_LINE_DELTA = 0.25;

/**
 * Fractional top line of an editor, like the built-in preview: line number
 * plus how far the viewport top has progressed into that (wrapped) line.
 * `undefined` while the editor shows no range.
 */
function getVisibleLine(editor: vscode.TextEditor): number | undefined {
  const first = editor.visibleRanges[0];
  if (!first) return undefined;
  const firstVisiblePosition = first.start;
  const lineNumber = firstVisiblePosition.line;
  const line = editor.document.lineAt(lineNumber);
  const progress = firstVisiblePosition.character / (line.text.length + 2);
  return lineNumber + progress;
}

/**
 * Reveal a fractional line: the fraction is encoded as a character offset
 * into the line, which AtTop positions proportionally (built-in technique).
 */
function scrollEditorToLine(line: number, editor: vscode.TextEditor): void {
  line = Math.max(0, line);
  const sourceLine = Math.floor(line);
  if (sourceLine >= editor.document.lineCount) {
    const last = editor.document.lineCount - 1;
    editor.revealRange(
      new vscode.Range(last, 0, last, 0),
      vscode.TextEditorRevealType.AtTop,
    );
    return;
  }
  const fraction = line - sourceLine;
  const text = editor.document.lineAt(sourceLine).text;
  const start = Math.floor(fraction * text.length);
  editor.revealRange(
    new vscode.Range(sourceLine, start, sourceLine + 1, 0),
    vscode.TextEditorRevealType.AtTop,
  );
}

/**
 * Record the visible top line of `uri`'s open editor (if any) into
 * {@link pendingInitialScroll}, for a workbench view about to open on it.
 */
function captureScrollPosition(uri: vscode.Uri): void {
  const target = uri.toString();
  const editor = vscode.window.visibleTextEditors.find(
    (e) => e.document.uri.toString() === target,
  );
  if (editor) {
    const line = getVisibleLine(editor);
    if (line !== undefined) pendingInitialScroll.set(target, line);
  }
}

/** Scroll `editor` back to the last line known synced for its document, if any. */
function revealLastKnownLine(editor: vscode.TextEditor): void {
  const line = lastKnownTopLine.get(editor.document.uri.toString());
  if (line != null) scrollEditorToLine(line, editor);
}

export {
  pendingInitialScroll,
  lastKnownTopLine,
  lastRevealedLine,
  lastPostedScrollTo,
  SYNC_LINE_DELTA,
  getVisibleLine,
  scrollEditorToLine,
  captureScrollPosition,
  revealLastKnownLine,
};
