// Webview wiring (src/views/wire.ts): the options a wired panel gets, its document
// lifecycle, the re-render triggers and the initial scroll handoff.
import { test } from 'node:test';
import assert from 'node:assert';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
  MockEditor,
  Position,
  Range,
} from '../helpers/vscode-mock.ts';
import type { VscodeMock } from '../helpers/vscode-mock.ts';

/** A message the panel received, as far as these tests read it. */
interface Posted {
  type?: unknown;
  line?: unknown;
}

/** A panel as wireWebview uses it, recording what it is given and sent. */
interface FakePanel {
  options?: unknown;
  messages: Posted[];
  disposed: boolean;
  receive: (message: unknown) => void;
  onDispose: () => void;
  webview: {
    cspSource: string;
    asWebviewUri(uri: unknown): string;
    options: unknown;
    html: string;
    postMessage(message: Posted): void;
    onDidReceiveMessage(fn: (message: unknown) => void): { dispose(): void };
  };
  onDidDispose(fn: () => void): { dispose(): void };
  onDidChangeViewState(fn: unknown): { dispose(): void };
  dispose(): void;
}

/** The wiring entry and the scroll capture, driven with fakes and mock documents. */
interface WireApi {
  setExtensionUri(uri: string): void;
  wireWebview(
    document: MockDocument,
    panel: FakePanel,
    closeWithDocument: boolean,
  ): void;
  captureScrollPosition(uri: MockDocument['uri']): void;
}

/** The render pipeline's re-render set, of the same module generation. */
interface RenderApi {
  activePosts: Set<() => void>;
}

function fakePanel(): FakePanel {
  const panel: FakePanel = {
    messages: [],
    disposed: false,
    receive: () => {
      throw new Error('the panel registered no message handler');
    },
    onDispose: () => {},
    webview: {
      cspSource: 'vscode-webview://host',
      asWebviewUri: (uri) => `https://webview/${String(uri)}`,
      set options(v: unknown) {
        panel.options = v;
      },
      get options() {
        return panel.options;
      },
      html: '',
      postMessage: (m) => {
        panel.messages.push(m);
      },
      onDidReceiveMessage: (fn) => {
        panel.receive = fn;
        return { dispose() {} };
      },
    },
    onDidDispose: (fn) => {
      panel.onDispose = fn;
      return { dispose() {} };
    },
    onDidChangeViewState: () => ({ dispose() {} }),
    dispose: () => {
      panel.disposed = true;
      panel.onDispose();
    },
  };
  return panel;
}

// A fresh mock and module generation with the extension root set.
async function setup(): Promise<{ vscode: VscodeMock; views: WireApi }> {
  const vscode = install();
  const views = await loadFresh<WireApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  return { vscode, views };
}

const types = (panel: FakePanel) => panel.messages.map((m) => m.type);

test('a wired webview may load exactly from dist/ and media/ (localResourceRoots)', async () => {
  const { views } = await setup();
  const panel = fakePanel();
  views.wireWebview(new MockDocument('# x'), panel, false);
  // The mock's Uri.joinPath joins with "/"; scripts stay enabled.
  assert.deepStrictEqual(panel.options, {
    enableScripts: true,
    localResourceRoots: ['EXT/dist', 'EXT/media'],
  });
});

test('the side preview closes with its source document, not with another one', async () => {
  const { vscode, views } = await setup();
  const doc = new MockDocument('# x', 'mock://a.md');
  const panel = fakePanel();
  views.wireWebview(doc, panel, true);
  const closed = defined(vscode._docCloseListener, 'document-close listener');
  closed(new MockDocument('# y', 'mock://b.md'));
  assert.strictEqual(panel.disposed, false, 'another document closing');
  closed(doc);
  assert.strictEqual(panel.disposed, true, 'its own document closing');
});

test('the custom editor does not close with the document (no close listener)', async () => {
  const { vscode, views } = await setup();
  views.wireWebview(new MockDocument('# x'), fakePanel(), false);
  assert.strictEqual(vscode._docCloseListener, undefined);
});

test('a color theme change re-renders the view (fence colors follow the theme)', async () => {
  const { vscode, views } = await setup();
  const panel = fakePanel();
  views.wireWebview(new MockDocument('# x'), panel, false);
  defined(vscode._themeListener, 'theme listener')({ kind: 1 });
  assert.deepStrictEqual(types(panel), ['render']);
});

test('a highlighter start re-renders every open view, until its panel is disposed', async () => {
  const { views } = await setup();
  // Same module generation as the views just loaded (no explicit ?gen: the current one).
  const render: RenderApi = await import(
    new URL('../../src/render/index.ts', import.meta.url).href
  );
  const panel = fakePanel();
  views.wireWebview(new MockDocument('# x'), panel, false);
  for (const post of render.activePosts) post(); // what initHighlighter does when ready
  assert.deepStrictEqual(types(panel), ['render']);
  panel.dispose();
  const before = panel.messages.length;
  for (const post of render.activePosts) post();
  assert.strictEqual(
    panel.messages.length,
    before,
    'a closed view is not re-posted',
  );
});

test('the editor position captured at open is delivered once, after config and render', async () => {
  const { vscode, views } = await setup();
  const doc = new MockDocument(
    Array.from({ length: 20 }, (_, i) => `l${i}`).join('\n'),
  );
  const editor = new MockEditor(doc);
  editor.visibleRanges = [new Range(new Position(7, 0), new Position(12, 0))];
  vscode.window.visibleTextEditors = [editor];
  views.captureScrollPosition(doc.uri);
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  panel.receive({ type: 'ready' });
  assert.deepStrictEqual(types(panel), ['config', 'render', 'scrollTo']);
  assert.strictEqual(panel.messages.at(-1)?.line, 7);
  panel.receive({ type: 'ready' }); // a reload of the webview: the handoff is spent
  assert.deepStrictEqual(types(panel).slice(3), ['config', 'render']);
});

test('no captured position (no editor on the document) sends no initial scroll', async () => {
  const { vscode, views } = await setup();
  const doc = new MockDocument('a\nb', 'mock://a.md');
  vscode.window.visibleTextEditors = [
    new MockEditor(new MockDocument('x', 'mock://other.md')),
  ];
  views.captureScrollPosition(doc.uri);
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  panel.receive({ type: 'ready' });
  assert.deepStrictEqual(types(panel), ['config', 'render']);
});
