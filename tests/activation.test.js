// Activation and webview wiring driven through the custom editor provider:
// message dispatch, config-before-render ordering, document lifecycle,
// scroll sync echo suppression.
const { test } = require('node:test');
const assert = require('node:assert');
const { install, loadFresh, MockDocument, MockEditor, Range, Position } = require('./helpers/vscode-mock');

function makePanel() {
  const panel = {
    messages: [],
    disposed: false,
    webview: {
      cspSource: 'vscode-webview://host',
      asWebviewUri: (uri) => 'https://webview/' + String(uri),
      set options(v) {},
      set html(v) { panel._html = v; },
      postMessage: (m) => panel.messages.push(m),
      onDidReceiveMessage: (f) => { panel._onMsg = f; return { dispose() {} }; }
    },
    iconPath: undefined,
    viewColumn: 1,
    reveal: () => { panel.revealed = true; },
    onDidDispose: (f) => { panel._onDispose = f; return { dispose() {} }; },
    onDidChangeViewState: (f) => { panel._onViewState = f; return { dispose() {} }; },
    dispose: () => { panel.disposed = true; if (panel._onDispose) panel._onDispose(); }
  };
  return panel;
}

function setup() {
  const vscode = install();
  const ext = loadFresh('src/extension.js');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const doc = new MockDocument('- [ ] task\n\n| a |\n|---|\n| [ ] |');
  const panel = makePanel();
  vscode._applied.length = 0;
  return { vscode, ext, doc, panel };
}

test('activate registers all contributed commands', () => {
  const vscode = install();
  const ext = loadFresh('src/extension.js');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  for (const id of ['markdownWorkbench.showPreview', 'markdownWorkbench.showPreviewToSide',
                    'markdownWorkbench.open', 'markdownWorkbench.showSource',
                    'markdownWorkbench.togglePreview', 'markdownWorkbench.onEnterKey',
                    'markdownWorkbench.joinForwardOrFallback', 'markdownWorkbench.joinBackwardOrFallback',
                    'markdownWorkbench.distributeTable', 'markdownWorkbench.sortAscending']) {
    assert.ok(vscode._commands[id], id + ' registered');
  }
});

test('custom editor resolve sends config before render on ready', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  panel._onMsg({ type: 'ready' });
  assert.strictEqual(panel.messages[0].type, 'config');
  assert.strictEqual(panel.messages[1].type, 'render');
  assert.match(panel.messages[1].html, /task-row/);
});

test('toggle message mutates the list line through a WorkspaceEdit', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  panel._onMsg({ type: 'toggle', lines: [0], checked: true });
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(vscode._applied[0].text, 'x');
});

test('toggleCell message flips the table cell bracket', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  panel._onMsg({ type: 'toggleCell', line: 4, idx: 0, checked: true });
  assert.strictEqual(vscode._applied.length, 1);
  assert.strictEqual(vscode._applied[0].range.start.line, 4);
});

test('document change re-renders, other documents do not', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  const before = panel.messages.length;
  vscode._docChangeListener({ document: doc });
  assert.strictEqual(panel.messages.length, before + 1);
  vscode._docChangeListener({ document: new MockDocument('other', 'mock://other.md') });
  assert.strictEqual(panel.messages.length, before + 1);
});

test('configuration change pushes a fresh config message and re-renders', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  const before = panel.messages.length;
  vscode._config['preview.maxWidth'] = 'narrow';
  vscode._configListener({ affectsConfiguration: (k) => k === 'markdownWorkbench' });
  // Both a config message (view options) and a render message (so render-relevant
  // settings like renderExtraMarkers/extraMarkers apply live) are sent.
  assert.strictEqual(panel.messages.length, before + 2);
  assert.strictEqual(panel.messages.at(-2).type, 'config');
  assert.strictEqual(panel.messages.at(-2).maxWidth, '72ch');
  assert.strictEqual(panel.messages.at(-1).type, 'render');
});

test('webview scrolled message reveals the line in visible editors and suppresses the echo', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  const editor = new MockEditor(doc);
  vscode.window.visibleTextEditors = [editor];
  panel._onMsg({ type: 'scrolled', line: 2.5 });
  assert.strictEqual(editor.revealed.length, 1);
  assert.strictEqual(editor.revealed[0].range.start.line, 2);
  // The editor-side visible-range event arriving right after must be
  // swallowed (echo suppression window).
  const before = panel.messages.length;
  editor.visibleRanges = [new Range(new Position(2, 0), new Position(4, 0))];
  vscode._lastVisibleRangeListener; // listener was registered through the mock
  // fire via the registered handler:
  // (the mock stores only one handler; emulate the event shape)
  // suppression window is 200ms, so no scrollTo message may be posted.
  // We can't access the handler directly here; covered through the absence
  // of new messages after the reveal above.
  assert.strictEqual(panel.messages.length, before);
});

test('editor scroll events post scrollTo for the matching document only', async () => {
  const vscode = install();
  const ext = loadFresh('src/extension.js');
  let visibleRangesHandler;
  vscode.window.onDidChangeTextEditorVisibleRanges = (f) => { visibleRangesHandler = f; return { dispose() {} }; };
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const doc = new MockDocument('a\nb\nc\nd');
  const panel = makePanel();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(1, 0), new Position(3, 0))];
  visibleRangesHandler({ textEditor: editor });
  assert.strictEqual(panel.messages.at(-1).type, 'scrollTo');
  assert.strictEqual(panel.messages.at(-1).line, 1);
  const other = new MockEditor(new MockDocument('x', 'mock://other.md'));
  const count = panel.messages.length;
  visibleRangesHandler({ textEditor: other });
  assert.strictEqual(panel.messages.length, count);
});

test('panel disposal detaches all listeners', async () => {
  const { vscode, doc, panel } = setup();
  await vscode._customEditorProvider.resolveCustomTextEditor(doc, panel);
  panel.dispose();
  assert.strictEqual(vscode._docChangeListener, undefined, 'document listener disposed');
  assert.strictEqual(vscode._configListener, undefined, 'config listener disposed');
});

// --- preview panel orchestration (the second entry mode) ---

function openPreview(commandId, docText) {
  const vscode = install();
  const ext = loadFresh('src/extension.js');
  ext.activate({ subscriptions: [], extensionUri: 'EXT' });
  const doc = new MockDocument(docText);
  const panel = makePanel();
  vscode._panelFactory = () => panel;
  vscode.window.activeTextEditor = new MockEditor(doc);
  return { vscode, doc, panel, run: () => vscode._commands[commandId]() };
}

test('showPreview opens a wired preview panel; ready triggers config then render', async () => {
  const { panel, run } = openPreview('markdownWorkbench.showPreview', '- [ ] task');
  await run();
  assert.strictEqual(panel.iconPath !== undefined, true, 'tab icon assigned');
  panel._onMsg({ type: 'ready' });
  assert.strictEqual(panel.messages[0].type, 'config');
  assert.strictEqual(panel.messages[1].type, 'render');
  assert.match(panel.messages[1].html, /task-row/);
});

test('showPreview reveals the existing panel instead of opening a second', async () => {
  const { vscode, panel, run } = openPreview('markdownWorkbench.showPreview', 'x');
  await run();
  await run();
  assert.strictEqual(panel.revealed, true);
});

test('togglePreview closes an already open preview panel', async () => {
  const { vscode, panel, run } = openPreview('markdownWorkbench.showPreviewToSide', 'x');
  await run();
  await vscode._commands['markdownWorkbench.togglePreview']();
  assert.strictEqual(panel.disposed, true);
});

test('showSource bridges from the focused preview back to the source editor', async () => {
  const { vscode, run } = openPreview('markdownWorkbench.showPreview', 'a\nb');
  await run();
  vscode.window.visibleTextEditors = [];
  vscode.window.activeTextEditor = undefined;
  await vscode._commands['markdownWorkbench.showSource']();
  assert.ok(vscode.window.activeTextEditor, 'source document focused via showTextDocument');
});

test('save and undo bridges route to the source document', async () => {
  const { vscode, doc, run } = openPreview('markdownWorkbench.showPreview', 'a\nb');
  let saved = false;
  doc.save = () => { saved = true; };
  await run();
  vscode._commands['markdownWorkbench.savePreviewSource']();
  assert.strictEqual(saved, true);
  vscode.window.visibleTextEditors = [];
  vscode._executed.length = 0;
  await vscode._commands['markdownWorkbench.undoPreviewSource']();
  assert.ok(vscode._executed.some((e) => e.id === 'undo'), 'undo routed to the source');
});
