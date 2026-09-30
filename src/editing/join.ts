// --- Ctrl+Delete / Ctrl+Backspace: join content lines across whitespace --------
//
// Two mirror-image commands, each gated on its own setting via the keybinding
// when-clause and falling back to a configurable command otherwise. They merge
// the current line with the next/previous line that has real content, deleting
// any blank or whitespace-only lines in between, and normalize the seam to
// exactly joinSpaces spaces (shared setting; 0 = no space).
import * as vscode from 'vscode';
import { leadingWhitespace } from './list-structure.ts';
import type { TextLines } from './list-structure.ts';
import { suppressedEdit } from './edit-guard.ts';

/**
 * Configured seam width in spaces for a join (`editing.joinSpaces`), 0 allowed
 * (no space), falling back to 1 when unset or not finite.
 */
function joinSpacesCount(): number {
  const n = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get<unknown>('editing.joinSpaces', 1);
  return typeof n === 'number' && Number.isFinite(n)
    ? Math.max(0, Math.floor(n))
    : 1;
}

// The command a join hands over to when it does not apply; a setting that is
// not a string falls back to the default.
function fallbackCommand(key: string, fallback: string): string {
  const command = vscode.workspace
    .getConfiguration('markdownWorkbench')
    .get<unknown>(key, fallback);
  return typeof command === 'string' ? command : fallback;
}

/**
 * Pure: the edit that merges line `rightLine` onto the end of line `leftLine`.
 * Replaces everything from the left line's last visible character through the
 * right line's first non-whitespace character (line break, any whitespace-only
 * lines in between, both sides' seam whitespace) with the join spaces. The
 * spaces are inserted only when BOTH sides have visible content; if either side
 * is empty/whitespace-only (e.g. the cursor was on an empty line) no leading or
 * trailing space is added - the texts meet directly. Returns the range, the
 * replacement text and the resulting seam column on the left line (cursor).
 */
function joinSeam(
  document: TextLines,
  leftLine: number,
  rightLine: number,
  joinSpaces: number,
): { range: vscode.Range; text: string; seam: number } {
  const leftText = document.lineAt(leftLine).text;
  const rightText = document.lineAt(rightLine).text;
  const leftEnd = leftText.replace(/[ \t]+$/, '').length;
  const rightWs = leadingWhitespace(rightText);
  const spaces =
    leftText.trim() !== '' && rightText.trim() !== '' ? joinSpaces : 0;
  return {
    range: new vscode.Range(leftLine, leftEnd, rightLine, rightWs),
    text: ' '.repeat(spaces),
    seam: leftEnd + spaces,
  };
}

/**
 * The first line at or beyond `from` in direction `step` (+1 down, -1 up) whose
 * text has non-whitespace content; -1 if none before the document edge.
 */
function nextContentLine(
  document: TextLines,
  from: number,
  step: number,
): number {
  for (let l = from; l >= 0 && l < document.lineCount; l += step) {
    if (document.lineAt(l).text.trim() !== '') return l;
  }
  return -1;
}

/**
 * Ctrl+Delete: join the current line with the next content line, or fall back to
 * the configured command when the cursor is not at the end of visible content.
 */
async function joinForwardOrFallback() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () =>
    vscode.commands.executeCommand(
      fallbackCommand('editing.forwardJoin.fallbackCommand', 'deleteWordRight'),
    );
  if (editor?.selections.length !== 1 || !editor.selection.isEmpty)
    return fallback();

  const pos = editor.selection.active;
  const doc = editor.document;
  const lineText = doc.lineAt(pos.line).text;
  // Trigger: cursor at the end of the visible content (only whitespace to its
  // right). An empty/whitespace-only line counts - the cursor is at its end.
  if (/\S/.test(lineText.slice(pos.character))) return fallback();
  const target = nextContentLine(doc, pos.line + 1, +1);
  if (target === -1) return fallback();

  const seam = joinSeam(doc, pos.line, target, joinSpacesCount());
  await suppressedEdit(editor, (b) => b.replace(seam.range, seam.text));
  editor.selection = new vscode.Selection(
    pos.line,
    seam.seam,
    pos.line,
    seam.seam,
  );
}

/**
 * Ctrl+Backspace: join the current line with the previous content line, or fall
 * back to the configured command when the cursor is not at the start of visible
 * content.
 */
async function joinBackwardOrFallback() {
  const editor = vscode.window.activeTextEditor;
  const fallback = () =>
    vscode.commands.executeCommand(
      fallbackCommand('editing.backwardJoin.fallbackCommand', 'deleteWordLeft'),
    );
  if (editor?.selections.length !== 1 || !editor.selection.isEmpty)
    return fallback();

  const pos = editor.selection.active;
  const doc = editor.document;
  const lineText = doc.lineAt(pos.line).text;
  // Trigger: cursor at the start of the visible content (at or before the first
  // non-whitespace character). An empty/whitespace-only line counts - the
  // cursor is at its start.
  if (pos.character > leadingWhitespace(lineText)) return fallback();
  const target = nextContentLine(doc, pos.line - 1, -1);
  if (target === -1) return fallback();

  const seam = joinSeam(doc, target, pos.line, joinSpacesCount());
  await suppressedEdit(editor, (b) => b.replace(seam.range, seam.text));
  editor.selection = new vscode.Selection(target, seam.seam, target, seam.seam);
}

export {
  joinSpacesCount,
  joinSeam,
  nextContentLine,
  joinForwardOrFallback,
  joinBackwardOrFallback,
};
