// The webview entry: loading main.ts registers the host message listener.
import { test } from 'node:test';
import assert from 'node:assert';
import { startWebview } from '../helpers/webview-dom.ts';

test('webview script parses and registers a message listener', async () => {
  const { state } = await startWebview();
  assert.ok(state.listeners.window.message);
});

test('the webview posts ready once it has loaded, and nothing before', async () => {
  const { state } = await startWebview();
  assert.deepStrictEqual(state.posted, [{ type: 'ready' }]);
});

test('the webview acquires the VS Code API once and keeps the handle (VS Code allows one call)', async () => {
  const r = await startWebview();
  r.send({
    type: 'config',
    documentUri: 'file:///ws/doc.md',
    maxWidth: '980px',
    minimap: { enabled: false },
  });
  r.send({ type: 'render', html: '<p>a</p>', key: 'k1' });
  assert.strictEqual(r.state.apiAcquired, 1);
});
