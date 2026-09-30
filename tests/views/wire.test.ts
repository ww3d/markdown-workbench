// Webview wiring (src/views/wire.ts): the options a wired panel gets.
import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh, MockDocument } from '../helpers/vscode-mock.ts';

/** A panel as wireWebview uses it, recording the options it is given. */
interface FakePanel {
  options?: unknown;
  webview: {
    cspSource: string;
    asWebviewUri(uri: unknown): string;
    options: unknown;
    html: string;
    postMessage(message: unknown): void;
    onDidReceiveMessage(fn: unknown): { dispose(): void };
  };
  onDidDispose(fn: unknown): { dispose(): void };
  onDidChangeViewState(fn: unknown): { dispose(): void };
}

/** The wiring entry, driven with a fake panel and a mock document. */
interface WireApi {
  setExtensionUri(uri: string): void;
  wireWebview(
    document: MockDocument,
    panel: FakePanel,
    closeWithDocument: boolean,
  ): void;
}

function fakePanel(): FakePanel {
  const panel: FakePanel = {
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
      postMessage: () => {},
      onDidReceiveMessage: () => ({ dispose() {} }),
    },
    onDidDispose: () => ({ dispose() {} }),
    onDidChangeViewState: () => ({ dispose() {} }),
  };
  return panel;
}

test('a wired webview may load exactly from dist/ and media/ (localResourceRoots)', async () => {
  install();
  const views = await loadFresh<WireApi>('src/views/index.ts');
  views.setExtensionUri('EXT');
  const panel = fakePanel();
  views.wireWebview(new MockDocument('# x'), panel, false);
  // The mock's Uri.joinPath joins with "/"; scripts stay enabled.
  assert.deepStrictEqual(panel.options, {
    enableScripts: true,
    localResourceRoots: ['EXT/dist', 'EXT/media'],
  });
});
