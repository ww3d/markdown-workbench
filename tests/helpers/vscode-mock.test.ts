// loadFresh gives each call its own module graph: state a source keeps at module level must not
// leak from one suite into the next, or a test passes or fails depending on the order it runs in.
import { test } from 'node:test';
import assert from 'node:assert';
import { install, loadFresh } from './vscode-mock.ts';

/**
 * src/views/index.ts as this test drives it, with strings for URIs. The extension root lives in
 * src/views/identity.ts: module-level state in a dependency of the entry, read by the skeleton.
 */
interface Views {
  setExtensionUri(uri: string): void;
  getWebviewHtml(webview: {
    cspSource: string;
    asWebviewUri(uri: unknown): string;
  }): string;
}

const skeleton = (views: Views): string =>
  views.getWebviewHtml({
    cspSource: 'csp',
    asWebviewUri: (uri) => `https://webview/${String(uri)}`,
  });

test('two loadFresh generations keep separate module state', async () => {
  install();
  const first = await loadFresh<Views>('src/views/index.ts');
  const second = await loadFresh<Views>('src/views/index.ts');
  assert.notStrictEqual(first, second, 'a new generation is a new module');

  first.setExtensionUri('FIRST');
  assert.match(skeleton(first), /FIRST/);
  assert.throws(() => skeleton(second), /extension URI not set/);

  second.setExtensionUri('SECOND');
  assert.match(skeleton(first), /FIRST/);
  assert.match(skeleton(second), /SECOND/);
  assert.doesNotMatch(skeleton(first), /SECOND/);
});

test('getConfiguration answers per section: an unknown section reads its defaults', () => {
  const vscode = install();
  vscode._config['tables.enabled'] = false;
  vscode._editorConfig.wordWrap = 'on';
  const get = (section: string, key: string) =>
    vscode.workspace.getConfiguration(section).get(key, 'default');
  assert.strictEqual(get('markdownWorkbench', 'tables.enabled'), false);
  assert.strictEqual(get('editor', 'wordWrap'), 'on');
  assert.strictEqual(get('wrongSection', 'tables.enabled'), 'default');
  assert.strictEqual(get('markdownWorkbench', 'wordWrap'), 'default');
});
