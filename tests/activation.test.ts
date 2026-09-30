// Activation and webview wiring driven through the custom editor provider:
// message dispatch, config-before-render ordering, document lifecycle,
// scroll sync echo suppression.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Range,
  Position,
} from './helpers/vscode-mock.ts';
import type { MockContext, VscodeMock } from './helpers/vscode-mock.ts';
import { nth } from './helpers/nth.ts';

/** What the tests read of a message the extension posts to the webview. */
interface PanelMessage {
  type: string;
  html?: string;
  tables?: unknown;
  version?: number;
  maxWidth?: string;
  line?: number;
  documentUri?: string;
}

/** A webview panel as the extension drives it, recording what it is given. */
interface MockPanel {
  messages: PanelMessage[];
  disposed: boolean;
  revealed?: boolean;
  iconPath: unknown;
  viewColumn: number;
  webview: {
    cspSource: string;
    asWebviewUri(uri: unknown): string;
    options: unknown;
    html: string;
    postMessage(m: PanelMessage): number;
    onDidReceiveMessage(f: (message: object) => void): { dispose(): void };
  };
  _html?: string;
  _onMsg?: (message: object) => void;
  _onDispose?: () => void;
  _onViewState?: (e: unknown) => void;
  reveal(): void;
  onDidDispose(f: () => void): { dispose(): void };
  onDidChangeViewState(f: (e: unknown) => void): { dispose(): void };
  dispose(): void;
}

/** The activation entry as the tests call it, with the mock's context shape. */
interface Extension {
  activate(context: MockContext & { extensionUri: string }): {
    readonly viewStats: ReadonlySet<{ readonly documentUri: string }>;
  };
}

/** The serializer the extension registers for the preview viewType. */
interface PreviewSerializer {
  deserializeWebviewPanel(panel: MockPanel, state: unknown): Promise<void>;
}

function makePanel(): MockPanel {
  const panel: MockPanel = {
    messages: [],
    disposed: false,
    webview: {
      cspSource: 'vscode-webview://host',
      asWebviewUri: (uri) => `https://webview/${String(uri)}`,
      set options(_v) {},
      get options() {
        return undefined;
      },
      set html(v) {
        panel._html = v;
      },
      get html() {
        return panel._html ?? '';
      },
      postMessage: (m) => panel.messages.push(m),
      onDidReceiveMessage: (f) => {
        panel._onMsg = f;
        return { dispose() {} };
      },
    },
    iconPath: undefined,
    viewColumn: 1,
    reveal: () => {
      panel.revealed = true;
    },
    onDidDispose: (f) => {
      panel._onDispose = f;
      return { dispose() {} };
    },
    onDidChangeViewState: (f) => {
      panel._onViewState = f;
      return { dispose() {} };
    },
    dispose: () => {
      panel.disposed = true;
      if (panel._onDispose) panel._onDispose();
    },
  };
  return panel;
}

// Narrowing helpers: the mock holds what the extension registered as
// `unknown`, so each test reads it through a check that fails by name.
function send(panel: MockPanel, message: object): void {
  defined(panel._onMsg, 'message handler')(message);
}

function provider(vscode: VscodeMock) {
  return defined(vscode._customEditorProvider, 'custom editor provider');
}

function command(vscode: VscodeMock, id: string) {
  return defined(defined(vscode._commands, 'commands')[id], `command ${id}`);
}

function record(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null)
    throw new TypeError(`${what} is not an object`);
  return Object.fromEntries(Object.entries(value));
}

function previewSerializer(vscode: VscodeMock): PreviewSerializer {
  const serializer = defined(vscode._panelSerializers, 'serializers')[
    'markdownWorkbench.preview'
  ];
  if (
    typeof serializer !== 'object' ||
    serializer === null ||
    !('deserializeWebviewPanel' in serializer) ||
    typeof serializer.deserializeWebviewPanel !== 'function'
  )
    throw new TypeError('no preview serializer registered');
  const deserialize = serializer.deserializeWebviewPanel.bind(serializer);
  return {
    deserializeWebviewPanel: async (panel, state) => {
      await deserialize(panel, state);
    },
  };
}

async function setup() {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const doc = new MockDocument('- [ ] task\n\n| a |\n|---|\n| [ ] |');
  const panel = makePanel();
  vscode._applied.length = 0;
  return { vscode, ext, doc, panel };
}

test('activate registers all contributed commands', async () => {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  for (const id of [
    'markdownWorkbench.showPreview',
    'markdownWorkbench.showPreviewToSide',
    'markdownWorkbench.open',
    'markdownWorkbench.showSource',
    'markdownWorkbench.togglePreview',
    'markdownWorkbench.onEnterKey',
    'markdownWorkbench.joinForwardOrFallback',
    'markdownWorkbench.joinBackwardOrFallback',
    'markdownWorkbench.distributeTable',
    'markdownWorkbench.sortAscending',
  ]) {
    assert.ok(vscode._commands?.[id], `${id} registered`);
  }
});

test('activate exports the stats of the open views: one per wired view, gone when it closes (P8)', async () => {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  const { viewStats } = ext.activate({
    subscriptions: [],
    extensionUri: 'EXT',
  });
  const doc = new MockDocument('# a');
  const panel = makePanel();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  assert.deepStrictEqual(
    [...viewStats].map((s) => s.documentUri),
    [doc.uri.toString()],
  );
  panel.dispose();
  assert.strictEqual(viewStats.size, 0);
});

test('custom editor resolve sends config before render on ready', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  send(panel, { type: 'ready' });
  assert.strictEqual(nth(panel.messages, 0).type, 'config');
  assert.strictEqual(nth(panel.messages, 1).type, 'render');
  assert.match(String(nth(panel.messages, 1).html), /task-row/);
});

test('toggle message mutates the list line through a WorkspaceEdit', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  send(panel, { type: 'toggle', lines: [0], checked: true });
  assert.strictEqual(vscode._applied.length, 1);
  const applied = nth(vscode._applied, 0);
  assert.ok(applied.kind === 'replace');
  assert.strictEqual(applied.text, 'x');
});

test('toggleCell message flips the table cell bracket', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  send(panel, { type: 'toggleCell', line: 4, idx: 0, checked: true });
  assert.strictEqual(vscode._applied.length, 1);
  const applied = nth(vscode._applied, 0);
  assert.ok(applied.kind === 'replace');
  assert.strictEqual(applied.range.start.line, 4);
  assert.strictEqual(applied.text, 'x', 'checked: true writes the tick');
});

test('document change re-renders, other documents do not', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  const before = panel.messages.length;
  defined(vscode._docChangeListener, 'document listener')({ document: doc });
  assert.strictEqual(panel.messages.length, before + 1);
  defined(
    vscode._docChangeListener,
    'document listener',
  )({
    document: new MockDocument('other', 'mock://other.md'),
  });
  assert.strictEqual(panel.messages.length, before + 1);
});

test('configuration change pushes a fresh config message and re-renders', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  const before = panel.messages.length;
  vscode._config['preview.maxWidth'] = 'narrow';
  defined(
    vscode._configListener,
    'config listener',
  )({
    affectsConfiguration: (k: string) => k === 'markdownWorkbench',
  });
  // Both a config message (view options) and a render message (so render-relevant
  // settings like renderExtraMarkers/extraMarkers apply live) are sent.
  assert.strictEqual(panel.messages.length, before + 2);
  assert.strictEqual(
    defined(panel.messages.at(-2), 'a message').type,
    'config',
  );
  assert.strictEqual(
    defined(panel.messages.at(-2), 'a message').maxWidth,
    '72ch',
  );
  assert.strictEqual(
    defined(panel.messages.at(-1), 'a message').type,
    'render',
  );
});

test('webview scrolled message reveals the line in visible editors and suppresses the echo', async () => {
  const { vscode, doc, panel } = await setup();
  let visibleRangesHandler:
    | ((e: { textEditor: MockEditor }) => void)
    | undefined;
  vscode.window.onDidChangeTextEditorVisibleRanges = (f) => {
    visibleRangesHandler = f;
    return { dispose() {} };
  };
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  const editor = new MockEditor(doc);
  vscode.window.visibleTextEditors = [editor];
  // The clock stands still, so the window edges are exact: the reveal starts a 200 ms window.
  const realNow = Date.now;
  const start = realNow();
  const at = (ms: number) => {
    Date.now = () => start + ms;
  };
  const range = (line: number) => [
    new Range(new Position(line, 0), new Position(4, 0)),
  ];
  try {
    at(0);
    send(panel, { type: 'scrolled', line: 2.5 });
    assert.strictEqual(editor.revealed.length, 1);
    assert.strictEqual(nth(editor.revealed, 0).range.start.line, 2);
    // The editor-side visible-range event the reveal causes arrives right after: inside
    // the window it must not bounce back as a scrollTo, up to its last millisecond.
    const before = panel.messages.length;
    editor.visibleRanges = range(2);
    at(199);
    visibleRangesHandler?.({ textEditor: editor });
    assert.strictEqual(panel.messages.length, before, 'the echo is suppressed');
    // Once the window has passed, an editor scroll syncs to the webview again.
    editor.visibleRanges = range(3);
    at(201);
    visibleRangesHandler?.({ textEditor: editor });
  } finally {
    Date.now = realNow;
  }
  assert.strictEqual(
    panel.messages.at(-1)?.type,
    'scrollTo',
    'after the window the editor scroll is posted',
  );
});

test('editor scroll events post scrollTo for the matching document only', async () => {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  let visibleRangesHandler: ((event: unknown) => unknown) | undefined;
  vscode.window.onDidChangeTextEditorVisibleRanges = (f) => {
    visibleRangesHandler = f;
    return { dispose() {} };
  };
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const doc = new MockDocument('a\nb\nc\nd');
  const panel = makePanel();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(1, 0), new Position(3, 0))];
  defined(
    visibleRangesHandler,
    'visible-range handler',
  )({ textEditor: editor });
  assert.strictEqual(
    defined(panel.messages.at(-1), 'a message').type,
    'scrollTo',
  );
  assert.strictEqual(defined(panel.messages.at(-1), 'a message').line, 1);
  const other = new MockEditor(new MockDocument('x', 'mock://other.md'));
  const count = panel.messages.length;
  defined(visibleRangesHandler, 'visible-range handler')({ textEditor: other });
  assert.strictEqual(panel.messages.length, count);
});

test('the scrolled reveal is delta-gated: a sub-line change does not reveal again', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  const editor = new MockEditor(doc);
  vscode.window.visibleTextEditors = [editor];
  send(panel, { type: 'scrolled', line: 2.0 });
  assert.strictEqual(editor.revealed.length, 1);
  send(panel, { type: 'scrolled', line: 2.1 }); // within the 0.25 delta -> skipped
  assert.strictEqual(
    editor.revealed.length,
    1,
    'a sub-threshold change does not call revealRange',
  );
  send(panel, { type: 'scrolled', line: 3.0 }); // beyond the delta -> reveals
  assert.strictEqual(editor.revealed.length, 2, 'a meaningful change reveals');
});

test('editor->webview scrollTo is delta-gated: a sub-line change is not re-posted', async () => {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  let handler: ((event: unknown) => unknown) | undefined;
  vscode.window.onDidChangeTextEditorVisibleRanges = (f) => {
    handler = f;
    return { dispose() {} };
  };
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const line20 = 'x'.repeat(20);
  const doc = new MockDocument(
    [line20, line20, line20, line20, line20].join('\n'),
  );
  const panel = makePanel();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  const scrollTos = () =>
    panel.messages.filter((m) => m.type === 'scrollTo').length;
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(1, 0), new Position(3, 0))]; // line 1.0
  defined(handler, 'visible-range handler')({ textEditor: editor });
  const first = scrollTos();
  assert.ok(first >= 1, 'first visible-range change posts scrollTo');
  editor.visibleRanges = [new Range(new Position(1, 2), new Position(3, 0))]; // line ~1.09, sub-threshold
  defined(handler, 'visible-range handler')({ textEditor: editor });
  assert.strictEqual(
    scrollTos(),
    first,
    'a sub-threshold change is not re-posted',
  );
  editor.visibleRanges = [new Range(new Position(3, 0), new Position(4, 0))]; // line 3.0
  defined(handler, 'visible-range handler')({ textEditor: editor });
  assert.strictEqual(
    scrollTos(),
    first + 1,
    'a meaningful change is re-posted',
  );
});

test('panel disposal detaches all listeners', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  panel.dispose();
  assert.strictEqual(
    vscode._docChangeListener,
    undefined,
    'document listener disposed',
  );
  assert.strictEqual(
    vscode._configListener,
    undefined,
    'config listener disposed',
  );
});

// --- in-preview find (#24): the native find widget is enabled in both
// WebviewPanel construction paths. ---

test('the custom editor provider enables the find widget', async () => {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const opts = record(
    record(vscode._customEditorOptions, 'custom editor options').webviewOptions,
    'webview options',
  );
  assert.strictEqual(opts.enableFindWidget, true);
  assert.strictEqual(
    opts.retainContextWhenHidden,
    true,
    'existing option preserved',
  );
});

test('the side preview panel enables the find widget', async () => {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const panel = makePanel();
  vscode._panelFactory = () => panel;
  vscode.window.activeTextEditor = new MockEditor(
    new MockDocument('- [ ] task'),
  );
  await command(vscode, 'markdownWorkbench.showPreview')();
  const opts = record(
    nth(defined(vscode._panelArgs, 'panel arguments'), 3), // 4th argument of createWebviewPanel
    'panel options',
  );
  assert.strictEqual(opts.enableFindWidget, true);
  assert.strictEqual(opts.enableScripts, true, 'existing option preserved');
  assert.strictEqual(
    opts.retainContextWhenHidden,
    true,
    'existing option preserved',
  );
});

// --- preview panel orchestration (the second entry mode) ---

async function openPreview(commandId: string, docText: string) {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const doc = new MockDocument(docText);
  const panel = makePanel();
  vscode._panelFactory = () => panel;
  vscode.window.activeTextEditor = new MockEditor(doc);
  return { vscode, doc, panel, run: () => command(vscode, commandId)() };
}

test('showPreview opens a wired preview panel; ready triggers config then render', async () => {
  const { panel, run } = await openPreview(
    'markdownWorkbench.showPreview',
    '- [ ] task',
  );
  await run();
  assert.strictEqual(panel.iconPath !== undefined, true, 'tab icon assigned');
  send(panel, { type: 'ready' });
  assert.strictEqual(nth(panel.messages, 0).type, 'config');
  assert.strictEqual(nth(panel.messages, 1).type, 'render');
  assert.match(String(nth(panel.messages, 1).html), /task-row/);
});

test('showPreview reveals the existing panel instead of opening a second', async () => {
  const { panel, run } = await openPreview(
    'markdownWorkbench.showPreview',
    'x',
  );
  await run();
  await run();
  assert.strictEqual(panel.revealed, true);
});

test('togglePreview closes an already open preview panel', async () => {
  const { vscode, panel, run } = await openPreview(
    'markdownWorkbench.showPreviewToSide',
    'x',
  );
  await run();
  await command(vscode, 'markdownWorkbench.togglePreview')();
  assert.strictEqual(panel.disposed, true);
});

test('showSource bridges from the focused preview back to the source editor', async () => {
  const { vscode, run } = await openPreview(
    'markdownWorkbench.showPreview',
    'a\nb',
  );
  await run();
  vscode.window.visibleTextEditors = [];
  vscode.window.activeTextEditor = undefined;
  await command(vscode, 'markdownWorkbench.showSource')();
  assert.ok(
    vscode.window.activeTextEditor,
    'source document focused via showTextDocument',
  );
});

// showPreview opens in the active editor group, showPreviewToSide beside it
// (like the built-in preview); the view column is in the third argument of
// createWebviewPanel.
for (const [id, column] of [
  ['markdownWorkbench.showPreview', 'Active'],
  ['markdownWorkbench.showPreviewToSide', 'Beside'],
] as const) {
  test(`${id} opens the panel in the ${column} view column`, async () => {
    const { vscode, run } = await openPreview(id, 'x');
    await run();
    const showOptions = record(
      nth(defined(vscode._panelArgs, 'panel arguments'), 2),
      'panel show options',
    );
    assert.strictEqual(showOptions.viewColumn, vscode.ViewColumn[column]);
    assert.strictEqual(showOptions.preserveFocus, false, 'focus moves along');
  });
}

test('a second showPreview for the same document creates no second panel', async () => {
  const { vscode, doc, run } = await openPreview(
    'markdownWorkbench.showPreview',
    'x',
  );
  let created = 0;
  vscode._panelFactory = () => {
    created++;
    return makePanel();
  };
  await run();
  await run();
  assert.strictEqual(created, 1, 'the second call reveals, it does not create');
  // A different document gets a panel of its own.
  vscode.window.activeTextEditor = new MockEditor(
    new MockDocument(doc.getText(), 'mock://other.md'),
  );
  await run();
  assert.strictEqual(created, 2, 'one panel per document');
});

// "Open as Workbench" swaps the active editor in place; only a resource that is
// not the active one is opened with the custom editor instead. "Reopen as
// source file" swaps back to the default text editor.
async function executedAfter(
  commandId: string,
  ...args: unknown[]
): Promise<unknown[][]> {
  const { vscode, doc } = await setup();
  vscode.window.activeTextEditor = new MockEditor(doc);
  vscode._executed.length = 0;
  await command(vscode, commandId)(...args);
  return vscode._executed.map((e) => [e.id, ...e.args]);
}

test('open without a uri swaps the active editor in place', async () => {
  assert.deepStrictEqual(await executedAfter('markdownWorkbench.open'), [
    ['reopenActiveEditorWith', 'markdownWorkbench.editor'],
  ]);
});

test('open on the active resource swaps the active editor in place', async () => {
  const active = new MockDocument('x').uri;
  assert.deepStrictEqual(
    await executedAfter('markdownWorkbench.open', active),
    [['reopenActiveEditorWith', 'markdownWorkbench.editor']],
  );
});

test('open on another resource opens it with the custom editor instead', async () => {
  const other = new MockDocument('x', 'mock://other.md').uri;
  assert.deepStrictEqual(await executedAfter('markdownWorkbench.open', other), [
    ['vscode.openWith', other, 'markdownWorkbench.editor'],
  ]);
});

test('reopenAsSource swaps the active custom editor back to the default editor', async () => {
  const target = new MockDocument('x').uri;
  assert.deepStrictEqual(
    await executedAfter('markdownWorkbench.reopenAsSource', target),
    [['reopenActiveEditorWith', 'default']],
  );
});

// A read through a function: the assignments above narrow the property itself.
function activeEditor(vscode: VscodeMock) {
  return vscode.window.activeTextEditor;
}

test('showSource shows the last line the preview reported', async () => {
  const { vscode, doc, panel, run } = await openPreview(
    'markdownWorkbench.showPreview',
    'a\nb\nc\nd',
  );
  await run();
  send(panel, { type: 'scrolled', line: 2 });
  vscode.window.visibleTextEditors = [];
  vscode.window.activeTextEditor = undefined;
  await command(vscode, 'markdownWorkbench.showSource')();
  const editor = defined(activeEditor(vscode), 'the source editor');
  assert.strictEqual(editor.document, doc);
  assert.strictEqual(editor.revealed.length, 1, 'scrolled to the saved line');
  assert.strictEqual(nth(editor.revealed, 0).range.start.line, 2);
});

test('save and undo bridges route to the source document', async () => {
  const { vscode, doc, run } = await openPreview(
    'markdownWorkbench.showPreview',
    'a\nb',
  );
  let saved = false;
  doc.save = () => {
    saved = true;
    return Promise.resolve(true);
  };
  await run();
  command(vscode, 'markdownWorkbench.savePreviewSource')();
  assert.strictEqual(saved, true);
  vscode.window.visibleTextEditors = [];
  vscode._executed.length = 0;
  await command(vscode, 'markdownWorkbench.undoPreviewSource')();
  assert.ok(
    vscode._executed.some((e) => e.id === 'undo'),
    'undo routed to the source',
  );
});

// --- preview panel restore after a VS Code restart (#47). The WebviewPanel
// mode needs a serializer (the custom editor mode restores itself); the real
// restart is a declared manual check, the wiring/state roundtrip is headless. ---

async function activateFresh() {
  const vscode = install();
  const ext = await loadFresh<Extension>('src/extension.ts');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  return vscode;
}

test('a preview panel serializer is registered for the preview viewType', async () => {
  const vscode = await activateFresh();
  assert.ok(
    vscode._panelSerializers?.['markdownWorkbench.preview'],
    'registerWebviewPanelSerializer called for markdownWorkbench.preview',
  );
});

test('the config message carries the document URI so the webview can persist it', async () => {
  const { panel, run } = await openPreview(
    'markdownWorkbench.showPreview',
    'x',
  );
  await run();
  send(panel, { type: 'ready' });
  const config = panel.messages.find((m) => m.type === 'config');
  assert.ok(
    config?.documentUri,
    'config carries documentUri for setState persistence',
  );
});

test('deserializeWebviewPanel restores and re-wires a preview from its persisted URI', async () => {
  const vscode = await activateFresh();
  const panel = makePanel();
  await previewSerializer(vscode).deserializeWebviewPanel(panel, {
    documentUri: 'file:///ws/doc.md',
  });
  assert.strictEqual(
    panel.iconPath !== undefined,
    true,
    'restored tab gets the workbench icon',
  );
  assert.ok(
    panel._html,
    'skeleton wired via the shared attachPreviewPanel path',
  );
  send(panel, { type: 'ready' }); // same handshake as a fresh panel
  assert.strictEqual(nth(panel.messages, 0).type, 'config');
  assert.strictEqual(nth(panel.messages, 1).type, 'render');
});

test('deserializeWebviewPanel with no persisted state disposes the empty panel', async () => {
  const vscode = await activateFresh();
  const panel = makePanel();
  await previewSerializer(vscode).deserializeWebviewPanel(panel, undefined);
  assert.strictEqual(panel.disposed, true, 'no state -> no dead tab');
  assert.ok(!panel._html, 'panel left unwired');
});

test('deserializeWebviewPanel with a vanished document disposes cleanly and logs', async () => {
  const vscode = await activateFresh();
  vscode.workspace.openTextDocument = () =>
    Promise.reject(new Error('file not found'));
  const errors: unknown[][] = [];
  const originalError = console.error;
  console.error = (...a: unknown[]) => errors.push(a);
  try {
    const panel = makePanel();
    await previewSerializer(vscode).deserializeWebviewPanel(panel, {
      documentUri: 'file:///ws/gone.md',
    });
    assert.strictEqual(
      panel.disposed,
      true,
      'vanished document -> panel disposed',
    );
    assert.ok(!panel._html, 'panel left unwired');
    assert.ok(
      errors.some((a) => String(a[0]).includes('cannot restore preview')),
      'error is logged, not swallowed',
    );
  } finally {
    console.error = originalError;
  }
});

test('deserializeWebviewPanel does not open a second preview for the same document', async () => {
  const vscode = await activateFresh();
  const first = makePanel();
  await previewSerializer(vscode).deserializeWebviewPanel(first, {
    documentUri: 'file:///ws/doc.md',
  });
  const second = makePanel();
  await previewSerializer(vscode).deserializeWebviewPanel(second, {
    documentUri: 'file:///ws/doc.md',
  });
  assert.strictEqual(
    second.disposed,
    true,
    'duplicate restore for the same doc is closed',
  );
  assert.strictEqual(first.disposed, false, 'the first restored preview stays');
});

// Without an active text editor and without a URI argument, the preview
// commands have no document to act on: they open nothing and do not throw.
for (const id of [
  'markdownWorkbench.showPreview',
  'markdownWorkbench.showPreviewToSide',
  'markdownWorkbench.togglePreview',
  'markdownWorkbench.open',
]) {
  test(`${id} without an active editor opens nothing`, async () => {
    const { vscode } = await setup();
    vscode.window.activeTextEditor = undefined;
    let created = 0;
    vscode._panelFactory = () => {
      created++;
      return makePanel();
    };
    vscode._executed.length = 0;
    await command(vscode, id)();
    assert.strictEqual(created, 0, 'no webview panel created');
    assert.deepStrictEqual(vscode._executed, [], 'no command executed');
    assert.deepStrictEqual(vscode._applied, [], 'no edit applied');
  });
}

// Preview sort (REQ-045 to REQ-046, REQ-067 of docs/tasks/90-table-editing.md).
test('render carries the document version and config the previewSort flag', async () => {
  const { vscode, doc, panel } = await setup();
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  send(panel, { type: 'ready' });
  assert.deepStrictEqual(nth(panel.messages, 0).tables, { previewSort: true });
  assert.strictEqual(nth(panel.messages, 1).version, doc.version);
  assert.match(
    String(nth(panel.messages, 1).html),
    /class="mw-sort[^"]*" data-col="0"/,
  );
});

test('a sortTable message sorts the source table; a stale version is ignored', async () => {
  const { vscode, panel } = await setup();
  const doc = new MockDocument('| n |\n|---|\n| b |\n| a |');
  await provider(vscode).resolveCustomTextEditor(doc, panel);
  send(panel, {
    type: 'sortTable',
    line: 0,
    col: 0,
    dir: 'asc',
    version: doc.version + 1,
  });
  assert.deepStrictEqual(vscode._applied, [], 'stale: nothing applied');
  send(panel, {
    type: 'sortTable',
    line: 0,
    col: 0,
    dir: 'asc',
    version: doc.version,
  });
  assert.ok(vscode._applied.length > 0, 'sorted through a WorkspaceEdit');
});
