// Shared fixture for the clipboard-diff binding tests: a fresh mock, the
// feature registered, one open Markdown file as the active editor.
import {
  install,
  loadFresh,
  type MockUri,
  makeUri,
  MockDocument,
  MockEditor,
  Selection,
  TabInputText,
  type VscodeMock,
} from './vscode-mock.ts';

const SCHEME = 'markdown-workbench-clipboard';

/** Where the fixture opens its file and which selections the editor gets. */
interface SetupOptions {
  path?: string;
  scheme?: string;
  /** Selections as [anchorLine, anchorCharacter, activeLine, activeCharacter]. */
  selections?: [number, number, number, number][];
}

/** The clipboard-diff entry module as the fixture uses it. */
interface ClipboardDiffModule {
  registerClipboardDiff(context: { subscriptions: unknown[] }): void;
  [member: string]: unknown;
}

/**
 * Registers the clipboard diff against a fresh mock with `text` open as
 * /ws/notes.md (or `path`). Returns { vscode, cd, file, editor, run, tick }:
 * `run(id, ...args)` invokes a registered command, `tick()` lets the deferred
 * tab-lifecycle check run, `focusFile()` activates the file's own tab again.
 */
async function setup(
  text: string,
  { path = '/ws/notes.md', scheme = 'file', selections }: SetupOptions = {},
) {
  const vscode = install();
  const cd = await loadFresh<ClipboardDiffModule>(
    'src/clipboard-diff/index.js',
  );
  const context = { subscriptions: [] };
  cd.registerClipboardDiff(context);
  const file = new MockDocument(text, makeUri(scheme, path));
  vscode.workspace.textDocuments.push(file);
  const editor = new MockEditor(file);
  if (selections) {
    editor.selections = selections.map((s) => new Selection(...s));
    const [first] = editor.selections;
    if (first) editor.selection = first;
  }
  vscode.window.activeTextEditor = editor;
  vscode._openTab(new TabInputText(file.uri));
  const run = (id: string, ...args: unknown[]) => {
    const command = vscode._commands?.[id];
    if (!command) throw new TypeError(`command ${id} is not registered`);
    return command(...args);
  };
  // Makes the file's plain editor tab active again (a diff tab took focus).
  const focusFile = () => vscode._openTab(new TabInputText(file.uri));
  const tick = () => new Promise((r) => setTimeout(r, 5));
  return { vscode, cd, context, file, editor, run, tick, focusFile };
}

/** The document of a clipboard-diff page, opened through the mock. */
function pageDoc(vscode: VscodeMock, uri: MockUri) {
  return vscode.workspace.textDocuments.find(
    (d) => d.uri.toString() === uri.toString(),
  );
}

/** The last vscode.diff call: { left, right, title, options }. */
function lastDiff(vscode: VscodeMock) {
  const call = vscode._executed.filter((e) => e.id === 'vscode.diff').at(-1);
  if (!call) return undefined;
  const [left, right, title, options] = call.args;
  return { left, right, title, options, argCount: call.args.length };
}

/** Replaces the whole text of `doc` through applyEdit (fires change events). */
async function setText(vscode: VscodeMock, doc: MockDocument, text: string) {
  const edit = new vscode.WorkspaceEdit();
  edit.replace(
    doc.uri,
    new vscode.Range(doc.positionAt(0), doc.positionAt(doc.getText().length)),
    text,
  );
  await vscode.workspace.applyEdit(edit);
}

export { setup, pageDoc, lastDiff, setText, SCHEME };
