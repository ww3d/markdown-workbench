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
import type { ClipboardDiffSession } from '../../src/clipboard-diff/session.ts';

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
  deactivateClipboardDiff(): void;
  _internal: { swapDiffSides(): Promise<boolean> };
}

/** The extension context as the fixture hands it over; a test may add state stores to it. */
interface TestContext {
  subscriptions: unknown[];
  globalState?: unknown;
  workspaceState?: unknown;
}

/** The commands that open a diff and so resolve to its session (or to nothing). */
type SessionCommand =
  | 'markdownWorkbench.compareWithClipboard'
  | 'markdownWorkbench.compareWithEarlierClipboard';

function isSession(value: unknown): value is ClipboardDiffSession {
  return typeof value === 'object' && value !== null && 'candidateUri' in value;
}

/** The session a compare command opened; none opened fails the test by name. */
async function opened(
  result: Promise<ClipboardDiffSession | undefined>,
): Promise<ClipboardDiffSession> {
  const session = await result;
  if (!session) throw new TypeError('the command opened no clipboard diff');
  return session;
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
    'src/clipboard-diff/index.ts',
  );
  const context: TestContext = { subscriptions: [] };
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
  function run(
    id: SessionCommand,
    ...args: unknown[]
  ): Promise<ClipboardDiffSession | undefined>;
  function run(id: string, ...args: unknown[]): Promise<unknown>;
  async function run(id: string, ...args: unknown[]): Promise<unknown> {
    const command = vscode._commands?.[id];
    if (!command) throw new TypeError(`command ${id} is not registered`);
    const result = await command(...args);
    if (id.startsWith('markdownWorkbench.compareWith'))
      return isSession(result) ? result : undefined;
    return result;
  }
  // Makes the file's plain editor tab active again (a diff tab took focus).
  const focusFile = () => vscode._openTab(new TabInputText(file.uri));
  const tick = () => new Promise((r) => setTimeout(r, 5));
  return { vscode, cd, context, file, editor, run, tick, focusFile };
}

/** The registered page file system as the tests read it. */
interface PageStore {
  textOf(uri: MockUri): string | undefined;
  stat(uri: MockUri): { mtime: number };
  has(uri: MockUri): boolean;
  writeFile(
    uri: MockUri,
    content: Uint8Array,
    options: { create: boolean; overwrite: boolean },
  ): void;
}

function isPageStore(value: unknown): value is PageStore {
  return (
    typeof value === 'object' &&
    value !== null &&
    'textOf' in value &&
    typeof value.textOf === 'function' &&
    'stat' in value &&
    typeof value.stat === 'function' &&
    'has' in value &&
    typeof value.has === 'function' &&
    'writeFile' in value &&
    typeof value.writeFile === 'function'
  );
}

/** The clipboard-diff page file system the feature registered; none fails the test by name. */
function pageStore(vscode: VscodeMock): PageStore {
  const store = vscode._fsProviders[SCHEME];
  if (!isPageStore(store))
    throw new TypeError('no page file system registered');
  return store;
}

/** Whether any recorded message matches `pattern`; messages are unknown values, read as text. */
function anyMessage(
  messages: readonly unknown[] | undefined,
  pattern: RegExp,
): boolean {
  return (messages ?? []).some((m) => pattern.test(String(m)));
}

/** The options a warning was shown with (`showWarningMessage(message, options, ...items)`). */
function warningOptions(warning: { rest: readonly unknown[] }): {
  modal: unknown;
  detail: string | undefined;
} {
  const [options] = warning.rest;
  if (typeof options !== 'object' || options === null)
    throw new TypeError('the warning was shown without options');
  const detail = 'detail' in options ? options.detail : undefined;
  return {
    modal: 'modal' in options ? options.modal : undefined,
    detail: typeof detail === 'string' ? detail : undefined,
  };
}

/** A diagnostic as the feature publishes it: `code` and `source` are set on the mock's class. */
type PublishedDiagnostic = InstanceType<VscodeMock['Diagnostic']> & {
  code?: unknown;
  source?: unknown;
};

/** The diagnostics published for a page key (its URI string), or undefined when it has none. */
function diagnosticsOf(
  vscode: VscodeMock,
  key: string,
): PublishedDiagnostic[] | undefined {
  const list = vscode._diagnostics?.get(key);
  if (list === undefined) return undefined;
  if (!Array.isArray(list))
    throw new TypeError('published diagnostics are no list');
  return list.map((d: unknown) => {
    if (!(d instanceof vscode.Diagnostic))
      throw new TypeError('not a diagnostic');
    return d;
  });
}

/** A code action as the quick-fix provider returns it. */
type QuickFix = InstanceType<VscodeMock['CodeAction']> & {
  edit?: InstanceType<VscodeMock['WorkspaceEdit']>;
};

/** Asks the registered quick-fix provider for the actions of `doc` given its published diagnostics. */
async function quickFixes(
  vscode: VscodeMock,
  doc: MockDocument,
): Promise<QuickFix[]> {
  const registered = vscode._codeActionProviders[0];
  if (!registered) throw new TypeError('no quick-fix provider registered');
  const { provider } = registered;
  if (
    typeof provider !== 'object' ||
    provider === null ||
    !('provideCodeActions' in provider) ||
    typeof provider.provideCodeActions !== 'function'
  )
    throw new TypeError('the quick-fix provider has no provideCodeActions');
  const diagnostics = diagnosticsOf(vscode, doc.uri.toString()) ?? [];
  const actions: unknown = await provider.provideCodeActions(
    doc,
    new vscode.Range(0, 0, 0, 0),
    { diagnostics },
  );
  if (!Array.isArray(actions))
    throw new TypeError('provideCodeActions returned no list');
  return actions.map((a: unknown) => {
    if (!(a instanceof vscode.CodeAction))
      throw new TypeError('not a code action');
    return a;
  });
}

/** An item of a QuickPick as the feature offers it. */
interface PickItem {
  label: string;
  description?: string;
  detail?: string;
}

/** The items of the `index`-th QuickPick the feature showed (-1 = the last); none fails the test by name. */
function quickPickItems(vscode: VscodeMock, index = -1): PickItem[] {
  const call = vscode._quickPickCalls?.at(index);
  if (!call) throw new TypeError('no QuickPick was shown');
  const { items } = call;
  if (!Array.isArray(items)) throw new TypeError('the QuickPick has no items');
  return items.map((item: unknown) => {
    if (typeof item !== 'object' || item === null || !('label' in item))
      throw new TypeError('a QuickPick item has no label');
    const { label } = item;
    if (typeof label !== 'string')
      throw new TypeError('a QuickPick label is no string');
    const description =
      'description' in item && typeof item.description === 'string'
        ? item.description
        : undefined;
    const detail =
      'detail' in item && typeof item.detail === 'string'
        ? item.detail
        : undefined;
    return { label, description, detail };
  });
}

/** The open document of a clipboard-diff page; a page that is not open fails the test by name. */
function pageDoc(vscode: VscodeMock, uri: MockUri): MockDocument {
  const page = vscode.workspace.textDocuments.find(
    (d) => d.uri.toString() === uri.toString(),
  );
  if (!page) throw new TypeError(`the page ${uri} is not open`);
  return page;
}

function isUri(value: unknown): value is MockUri {
  return (
    typeof value === 'object' &&
    value !== null &&
    'scheme' in value &&
    'path' in value
  );
}

/** The last vscode.diff call: { left, right, title, options }. */
function lastDiff(vscode: VscodeMock) {
  const call = vscode._executed.filter((e) => e.id === 'vscode.diff').at(-1);
  if (!call) return undefined;
  const [left, right, title, options] = call.args;
  if (!isUri(left) || !isUri(right))
    throw new TypeError('vscode.diff was called without two uris');
  return { left, right, title, options, argCount: call.args.length };
}

/** The last vscode.diff call; none fails the test by name. */
function expectDiff(vscode: VscodeMock) {
  const diff = lastDiff(vscode);
  if (!diff) throw new TypeError('no vscode.diff call was made');
  return diff;
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

export type { PickItem };
export {
  anyMessage,
  diagnosticsOf,
  expectDiff,
  lastDiff,
  opened,
  pageDoc,
  pageStore,
  quickFixes,
  quickPickItems,
  setText,
  setup,
  warningOptions,
  SCHEME,
};
