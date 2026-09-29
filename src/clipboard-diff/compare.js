// "Compare with Clipboard": picks the baseline (selection, hull of several
// selections, anchored section or the live file), unwraps the clipboard text
// into a candidate and opens the native diff baseline -> candidate without a
// title, so VS Code names the tab from the pages' role names
// (docs/DECISIONS.md #48).

import * as vscode from 'vscode';
import { findAnchor } from './anchor.js';
import { unwrapAnswer } from './unwrap.js';
import { normalizeEol, splitLines } from './lines.js';

/**
 * Opens a clipboard diff of `clipText` against the active text editor.
 * `sessions` is the ClipboardDiffSessions registry. Returns the session, or
 * undefined when nothing was opened (a message told the user why).
 */
async function compareWithText(sessions, clipText) {
  const editor = vscode.window.activeTextEditor;
  const input = vscode.window.tabGroups.activeTabGroup?.activeTab?.input;
  // The focused editor must be the active tab's: with focus in a panel editor
  // (e.g. Output) the baseline would be a document the user does not see.
  if (
    !editor ||
    !(input instanceof vscode.TabInputText) ||
    editor.document.uri.toString() !== input.uri.toString()
  ) {
    vscode.window.showInformationMessage(
      'Compare with Clipboard needs an active text editor.',
    );
    return undefined;
  }
  const unwrapped = unwrapAnswer(clipText || '');
  if (!unwrapped.text.trim()) {
    vscode.window.showInformationMessage(
      'The clipboard is empty - there is nothing to compare.',
    );
    return undefined;
  }
  const document = editor.document;
  const eol = document.eol === vscode.EndOfLine.CRLF ? '\r\n' : '\n';
  const clip = normalizeEol(unwrapped.text, eol);
  const target = await chooseBaseline(editor, clip);
  if (!target) return undefined;

  const session = sessions.create({
    document,
    clip: target.clip ?? clip,
    ...target.spec,
  });
  try {
    await openPages(session);
    const options = { preview: false };
    if (target.reveal) options.selection = target.reveal;
    await vscode.commands.executeCommand(
      'vscode.diff',
      session.baselineUri,
      session.candidateUri,
      undefined,
      options,
    );
  } finally {
    session.opening = false; // from now on the tab lifecycle decides
  }
  if (target.note) vscode.window.showInformationMessage(target.note);
  if (unwrapped.removed.length) {
    vscode.window.setStatusBarMessage(
      `Markdown Workbench: unwrapped the answer (${unwrapped.removed.join(', ')})`,
      5000,
    );
  }
  return session;
}

// The baseline shape and region for the editor's state:
// { spec: { shape, region, prefix, suffix, role }, reveal?, note?, clip? }.
async function chooseBaseline(editor, clip) {
  const document = editor.document;
  const selections = editor.selections.filter((s) => !s.isEmpty);
  if (selections.length) {
    const start = Math.min(
      ...selections.map((s) => document.offsetAt(s.start)),
    );
    const end = Math.max(...selections.map((s) => document.offsetAt(s.end)));
    return {
      spec: { shape: 'page', region: [start, end], role: 'Selection' },
      note:
        selections.length > 1
          ? `${selections.length} selections combined into one range.`
          : undefined,
    };
  }
  const text = document.getText();
  const anchor = findAnchor(text, clip);
  let match = anchor.confident ? anchor.matches[0] : undefined;
  if (!anchor.confident && anchor.matches.length) {
    match = await pickMatch(document, anchor.matches);
    if (match === null) return undefined; // picker dismissed
  }
  if (!match) return { spec: { shape: 'file', region: [0, text.length] } };
  return anchoredTarget(document, text, clip, match);
}

// The file shape with the matched lines as region: the candidate is the file
// with those lines replaced, and the diff opens with the span selected.
function anchoredTarget(document, text, clip, match) {
  const start = document.offsetAt(new vscode.Position(match.start, 0));
  const end = document.offsetAt(document.lineAt(match.end - 1).range.end);
  const body = trimOneTrailingBreak(clip);
  const prefix = text.slice(0, start);
  const lastLine = match.start + splitLines(body).length - 1;
  const lastLength = splitLines(body).pop().length;
  return {
    spec: {
      shape: 'file',
      region: [start, end],
      prefix,
      suffix: text.slice(end),
    },
    clip: body,
    reveal: new vscode.Range(match.start, 0, lastLine, lastLength),
    note: `Compared with lines ${match.start + 1}-${match.end} (${
      match.kind === 'heading' ? 'matching heading' : 'matching lines'
    }).`,
  };
}

function trimOneTrailingBreak(text) {
  return text.replace(/(?:\r\n|\n)$/, '');
}

// QuickPick over uncertain anchor matches plus "whole file". Returns the match,
// undefined for the whole file, or null when the picker was dismissed.
async function pickMatch(document, matches) {
  const items = matches.map((m) => ({
    label: `Lines ${m.start + 1}-${m.end}`,
    description: `${Math.round(m.score * 100)}% of the lines match`,
    detail: document.lineAt(m.start).text.trim(),
    match: m,
  }));
  items.push({
    label: 'Whole file',
    description: 'compare with the entire document',
    match: undefined,
  });
  const pick = await vscode.window.showQuickPick(items, {
    placeHolder: 'Which part of the file does the clipboard replace?',
  });
  return pick ? pick.match : null;
}

// Opens the pages as documents first so the candidate takes the baseline's
// language even where its name carries no extension (an untitled baseline).
async function openPages(session) {
  const uris = [session.candidateUri];
  if (session.shape === 'page') uris.push(session.baselineUri);
  for (const uri of uris) {
    const doc = await vscode.workspace.openTextDocument(uri);
    if (doc.languageId !== session.languageId) {
      await vscode.languages.setTextDocumentLanguage(doc, session.languageId);
    }
  }
}

export { compareWithText };
// Exported for tests only.
export const _internal = { chooseBaseline, pickMatch, trimOneTrailingBreak };
