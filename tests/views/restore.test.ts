// The host half of the instant stand after a restart (src/views/restore.ts, wire.ts): a
// ready that names a stand of this build with the current key keeps it (no render, the
// version alone), anything else renders as before - one test per branch (REQ-074).
import { test } from 'node:test';
import type { TestContext } from 'node:test';
import assert from 'node:assert';
import { registerHooks } from 'node:module';
import {
  defined,
  install,
  loadFresh,
  MockDocument,
} from '../helpers/vscode-mock.ts';
import type { VscodeMock } from '../helpers/vscode-mock.ts';
import { TEST_BUILD_ID } from '../helpers/build-id.ts';

/** A message the panel received, as far as these tests read it. */
interface Posted {
  type?: unknown;
  key?: unknown;
  version?: unknown;
}

/** A panel as wireWebview uses it, recording what it is sent. */
interface FakePanel {
  messages: Posted[];
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

/** Render bookkeeping of one view, as src/views/restore.ts keeps it. */
interface Stats {
  documentUri: string;
  renders: number;
  restored: boolean;
  restoredInMs: number | undefined;
}

/** The wiring entry and the stats, of one module generation. */
interface ViewsApi {
  setExtensionUri(uri: string): void;
  wireWebview(document: MockDocument, panel: FakePanel, close: boolean): void;
  viewStats: Set<Stats>;
}

/** The highlighter of the same module generation. */
interface RenderApi {
  initHighlighter(): Promise<void>;
}

/** The key function and the wait bound of the same module generation. */
interface RestoreApi {
  HIGHLIGHTER_WAIT_MS: number;
  renderKey(inputs: {
    text: string;
    env: unknown;
    themeKind: number;
    highlighted: boolean;
  }): string;
}

function fakePanel(): FakePanel {
  const panel: FakePanel = {
    messages: [],
    receive: () => {
      throw new Error('the panel registered no message handler');
    },
    onDispose: () => {},
    webview: {
      cspSource: 'vscode-webview://host',
      asWebviewUri: (uri) => `https://webview/${String(uri)}`,
      options: undefined,
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
    dispose: () => panel.onDispose(),
  };
  return panel;
}

// A fresh mock and module generation (a restarted extension host).
async function setup(): Promise<{
  vscode: VscodeMock;
  views: ViewsApi;
  render: RenderApi;
  restore: RestoreApi;
}> {
  const vscode = install();
  const views = await loadFresh<ViewsApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  // Same module generation as the views just loaded (no explicit ?gen: the current one).
  const render: RenderApi = await import(
    new URL('../../src/render/index.ts', import.meta.url).href
  );
  const restore: RestoreApi = await import(
    new URL('../../src/views/restore.ts', import.meta.url).href
  );
  return { vscode, views, render, restore };
}

const types = (panel: FakePanel) => panel.messages.map((m) => m.type);
const TEXT = '# Title\n\n```js\nconst a = 1;\n```\n';
const ENV = {
  markdownWorkbench: { renderExtraMarkers: false, extraMarkers: [] },
};

// Open a view on `doc`, let it render once, and return the key the webview would persist.
async function renderedKey(doc: MockDocument): Promise<string> {
  const { views } = await setup();
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  panel.receive({ type: 'ready' });
  const render = panel.messages.find((m) => m.type === 'render');
  assert.ok(render && typeof render.key === 'string', 'a render with a key');
  return render.key;
}

// A restarted host: a fresh view receives a ready naming a restored stand.
async function restart(
  doc: MockDocument,
  ready: Record<string, unknown>,
  before?: (vscode: VscodeMock) => void,
): Promise<{ panel: FakePanel; views: ViewsApi }> {
  const { vscode, views } = await setup();
  before?.(vscode);
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  panel.receive({ type: 'ready', ...ready });
  return { panel, views };
}

test('restore hit: same build and key -> no render, the version goes out alone', async () => {
  const doc = new MockDocument(TEXT);
  const key = await renderedKey(doc);
  doc.version = 7;
  const { panel, views } = await restart(doc, {
    buildId: TEST_BUILD_ID,
    key,
    restoredInMs: 12,
  });
  assert.deepStrictEqual(types(panel), ['config', 'version']);
  assert.strictEqual(panel.messages[1]?.version, 7, 'the current version');
  const [stats] = views.viewStats;
  assert.deepStrictEqual(stats && { ...stats }, {
    documentUri: 'mock://doc.md',
    renders: 0,
    restored: true,
    restoredInMs: 12,
  });
});

test('restore miss: the text changed -> the host renders', async () => {
  const doc = new MockDocument(TEXT);
  const key = await renderedKey(doc);
  doc.lines = ['# Title changed'];
  const { panel } = await restart(doc, { buildId: TEST_BUILD_ID, key });
  assert.deepStrictEqual(types(panel), ['config', 'render']);
});

test('restore miss: the render settings changed -> the host renders', async () => {
  const doc = new MockDocument(TEXT);
  const key = await renderedKey(doc);
  const { panel } = await restart(
    doc,
    { buildId: TEST_BUILD_ID, key },
    (vs) => {
      vs._config['lists.renderExtraMarkers'] = true;
    },
  );
  assert.deepStrictEqual(types(panel), ['config', 'render']);
});

test('restore miss: the theme kind changed -> the host renders', async () => {
  const doc = new MockDocument(TEXT);
  const key = await renderedKey(doc);
  const { panel } = await restart(
    doc,
    { buildId: TEST_BUILD_ID, key },
    (vs) => {
      vs.window.activeColorTheme = { kind: 1 };
    },
  );
  assert.deepStrictEqual(types(panel), ['config', 'render']);
});

test('restore miss: another build id -> the host renders', async () => {
  const doc = new MockDocument(TEXT);
  const key = await renderedKey(doc);
  const { panel } = await restart(doc, { buildId: 'other-build', key });
  assert.deepStrictEqual(types(panel), ['config', 'render']);
});

test('a ready without a restored stand renders, and the render carries the key', async () => {
  const doc = new MockDocument(TEXT);
  const { panel, views } = await restart(doc, {});
  assert.deepStrictEqual(types(panel), ['config', 'render']);
  assert.match(String(panel.messages[1]?.key), /^[0-9a-f]{64}$/);
  const [stats] = views.viewStats;
  assert.strictEqual(stats?.renders, 1);
  assert.strictEqual(stats?.restored, false);
});

test('after a kept stand the next change renders as before', async () => {
  const doc = new MockDocument(TEXT);
  const key = await renderedKey(doc);
  const { vscode, views } = await setup();
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  panel.receive({ type: 'ready', buildId: TEST_BUILD_ID, key });
  doc.lines = ['# edited'];
  defined(
    vscode._docChangeListener,
    'document-change listener',
  )({
    document: doc,
  });
  assert.deepStrictEqual(types(panel), ['config', 'version', 'render']);
});

// A highlighted stand (persisted once Shiki was ready) meets a host whose Shiki still loads.
async function highlightedRestart(
  t: TestContext,
  ready: 'match' | 'miss',
): Promise<{ panel: FakePanel; init: Promise<void>; restore: RestoreApi }> {
  const { views, render, restore } = await setup();
  t.after(() => views.viewStats.clear());
  const doc = new MockDocument(ready === 'match' ? TEXT : `${TEXT}\nmore`);
  const key = restore.renderKey({
    text: TEXT,
    env: ENV,
    themeKind: 2,
    highlighted: true,
  });
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  const init = render.initHighlighter(); // loading until awaited
  panel.receive({ type: 'ready', buildId: TEST_BUILD_ID, key });
  return { panel, init, restore };
}

test('a highlighted stand waits for the loading highlighter and is kept once it is ready (0 renders)', async (t) => {
  const { panel, init } = await highlightedRestart(t, 'match');
  assert.deepStrictEqual(
    types(panel),
    ['config', 'version'],
    'no plain render',
  );
  await init;
  assert.ok(
    !types(panel).includes('render'),
    'the highlighter start renders nothing',
  );
});

test('a highlighted stand whose key does not match renders at once', async (t) => {
  const { panel, init } = await highlightedRestart(t, 'miss');
  assert.deepStrictEqual(types(panel), ['config', 'render']);
  await init;
});

test('a highlighter that fails to load renders the waiting stand in plain code', async (t) => {
  // Shiki cannot be resolved in this module generation: initHighlighter fails.
  const hooks = registerHooks({
    resolve(specifier, context, nextResolve) {
      if (specifier === 'shiki') throw new Error('shiki unavailable (test)');
      return nextResolve(specifier, context);
    },
  });
  t.after(() => hooks.deregister());
  t.mock.method(console, 'error', () => {}); // the expected failure log
  const { panel, init } = await highlightedRestart(t, 'match');
  assert.deepStrictEqual(types(panel), ['config', 'version']);
  await init;
  assert.deepStrictEqual(types(panel), ['config', 'version', 'render']);
});

test('a highlighter that never settles renders the waiting stand after the wait bound', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const { views, render, restore } = await setup();
  t.after(() => views.viewStats.clear());
  const doc = new MockDocument(TEXT);
  const key = restore.renderKey({
    text: TEXT,
    env: ENV,
    themeKind: 2,
    highlighted: true,
  });
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  // Shiki loading, not settled within the bound: the state a hung load leaves behind.
  void render.initHighlighter();
  panel.receive({ type: 'ready', buildId: TEST_BUILD_ID, key });
  assert.deepStrictEqual(types(panel), ['config', 'version']);
  t.mock.timers.tick(restore.HIGHLIGHTER_WAIT_MS - 1);
  assert.deepStrictEqual(types(panel), ['config', 'version'], 'still waiting');
  t.mock.timers.tick(1);
  assert.deepStrictEqual(types(panel), ['config', 'version', 'render']);
});

test('a re-post during the highlighter wait keeps the highlighted stand (no plain render)', async (t) => {
  const { vscode, views, render, restore } = await setup();
  t.after(() => views.viewStats.clear());
  const doc = new MockDocument(TEXT);
  const key = restore.renderKey({
    text: TEXT,
    env: ENV,
    themeKind: 2,
    highlighted: true,
  });
  const panel = fakePanel();
  views.wireWebview(doc, panel, false);
  const init = render.initHighlighter();
  panel.receive({ type: 'ready', buildId: TEST_BUILD_ID, key });
  // A settings change that does not touch the render re-posts while Shiki still loads.
  defined(
    vscode._configListener,
    'configuration listener',
  )({
    affectsConfiguration: () => true,
  });
  assert.deepStrictEqual(types(panel), [
    'config',
    'version',
    'config',
    'version',
  ]);
  await init;
  assert.ok(!types(panel).includes('render'));
});
