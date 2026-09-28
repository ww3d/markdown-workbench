const vscode = require('vscode');

// Scroll-position handoff between source editor and workbench views:
// pendingInitialScroll carries the editor's top line into a freshly opened
// view; lastKnownTopLine tracks the current top line per document (updated
// from both sync directions) for the way back to the source.
const pendingInitialScroll = new Map(); // uri string -> line
const lastKnownTopLine = new Map(); // uri string -> line
// Last value actually pushed in each sync direction, per document, so a
// sub-threshold change does not trigger another revealRange / scrollTo. The
// webview already coalesces its 'scrolled' posts to ~30Hz; these drop the
// residual redundant host work (a big source file lagged at ~60Hz otherwise).
const lastRevealedLine = new Map(); // uri string -> line last revealed in the editor
const lastPostedScrollTo = new Map(); // uri string -> line last posted to the webview
const SYNC_LINE_DELTA = 0.25; // fractional-line change below which a sync is skipped

// Fractional top line of an editor, like the built-in preview: line number
// plus how far the viewport top has progressed into that (wrapped) line.
function getVisibleLine(editor) {
  if (!editor.visibleRanges.length) return undefined;
  const firstVisiblePosition = editor.visibleRanges[0].start;
  const lineNumber = firstVisiblePosition.line;
  const line = editor.document.lineAt(lineNumber);
  const progress = firstVisiblePosition.character / (line.text.length + 2);
  return lineNumber + progress;
}

// Reveal a fractional line: the fraction is encoded as a character offset
// into the line, which AtTop positions proportionally (built-in technique).
function scrollEditorToLine(line, editor) {
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

function captureScrollPosition(uri) {
  const target = uri.toString();
  const editor = vscode.window.visibleTextEditors.find(
    (e) => e.document.uri.toString() === target,
  );
  if (editor) {
    const line = getVisibleLine(editor);
    if (line !== undefined) pendingInitialScroll.set(target, line);
  }
}

function revealLastKnownLine(editor) {
  const line = lastKnownTopLine.get(editor.document.uri.toString());
  if (line != null) scrollEditorToLine(line, editor);
}

module.exports = {
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
