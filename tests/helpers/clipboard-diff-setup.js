// Shared fixture for the clipboard-diff binding tests: a fresh mock, the
// feature registered, one open Markdown file as the active editor.
import {
  install,
  loadFresh,
  makeUri,
  MockDocument,
  MockEditor,
  Selection,
  TabInputText,
} from './vscode-mock.js';

const SCHEME = 'markdown-workbench-clipboard';

/**
 * Registers the clipboard diff against a fresh mock with `text` open as
 * /ws/notes.md (or `path`). Returns { vscode, cd, file, editor, run, tick }:
 * `run(id, ...args)` invokes a registered command, `tick()` lets the deferred
 * tab-lifecycle check run, `focusFile()` activates the file's own tab again.
 */
async function setup(
  text,
  { path = '/ws/notes.md', scheme = 'file', selections } = {},
) {
  const vscode = install();
  const cd = await loadFresh('src/clipboard-diff/index.js');
  const context = { subscriptions: [] };
  cd.registerClipboardDiff(context);
  const file = new MockDocument(text, makeUri(scheme, path));
  vscode.workspace.textDocuments.push(file);
  const editor = new MockEditor(file);
  if (selections) {
    editor.selections = selections.map((s) => new Selection(...s));
    editor.selection = editor.selections[0];
  }
  vscode.window.activeTextEditor = editor;
  vscode._openTab(new TabInputText(file.uri));
  const run = (id, ...args) => vscode._commands[id](...args);
  // Makes the file's plain editor tab active again (a diff tab took focus).
  const focusFile = () => vscode._openTab(new TabInputText(file.uri));
  const tick = () => new Promise((r) => setTimeout(r, 5));
  return { vscode, cd, context, file, editor, run, tick, focusFile };
}

/** The document of a clipboard-diff page, opened through the mock. */
function pageDoc(vscode, uri) {
  return vscode.workspace.textDocuments.find(
    (d) => d.uri.toString() === uri.toString(),
  );
}

/** The last vscode.diff call: { left, right, title, options }. */
function lastDiff(vscode) {
  const call = vscode._executed.filter((e) => e.id === 'vscode.diff').at(-1);
  if (!call) return undefined;
  const [left, right, title, options] = call.args;
  return { left, right, title, options, argCount: call.args.length };
}

/** Replaces the whole text of `doc` through applyEdit (fires change events). */
async function setText(vscode, doc, text) {
  const edit = new vscode.WorkspaceEdit();
  edit.replace(
    doc.uri,
    new vscode.Range(doc.positionAt(0), doc.positionAt(doc.getText().length)),
    text,
  );
  await vscode.workspace.applyEdit(edit);
}

export { setup, pageDoc, lastDiff, setText, SCHEME };
